module cache_adapter_ooo_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic            clk;
    logic            rst;
    logic            ic_req_valid;
    logic            ic_req_ready;
    cache_mem_req_t  ic_req;
    logic            ic_resp_valid;
    logic            ic_resp_ready;
    cache_mem_resp_t ic_resp;
    logic            dc_req_valid;
    logic            dc_req_ready;
    cache_mem_req_t  dc_req;
    logic            dc_resp_valid;
    logic            dc_resp_ready;
    cache_mem_resp_t dc_resp;
    logic [31:0]     dram_addr;
    logic            dram_read;
    logic            dram_write;
    logic [63:0]     dram_wdata;
    logic            dram_ready;
    logic [31:0]     dram_raddr;
    logic [63:0]     dram_rdata;
    logic            dram_rvalid;
    logic            _unused_response_bits;

    cache_adapter_ooo #(
        .ICACHE_DEMAND_ENTRIES(2),
        .ICACHE_PREFETCH_ENTRIES(1),
        .DCACHE_ENTRIES(2),
        .OUTSTANDING_ENTRIES(4)
    ) dut (.*);

    always #5ns clk = ~clk;

    assign _unused_response_bits = &{1'b0, ic_resp.src, dc_resp.src};

    function automatic cache_mem_req_t make_request(
        input cache_src_t      src,
        input cache_req_kind_t kind,
        input xlen_t           line_addr,
        input logic [CACHE_MSHR_ID_BITS-1:0] mshr_id
    );
        cache_mem_req_t req;
        req = '0;
        req.src = src;
        req.kind = kind;
        req.line_addr = line_addr;
        req.set_idx = line_addr[CACHE_OFFSET_BITS +: CACHE_SET_BITS];
        req.fill_way = CACHE_WAY_BITS'(1);
        req.mshr_id = mshr_id;
        req.icache_port_mask = 2'b01;
        req.critical = (kind != cache_req_prefetch_read);
        return req;
    endfunction

    task automatic clear_requests;
        ic_req_valid = 1'b0;
        ic_req = '0;
        dc_req_valid = 1'b0;
        dc_req = '0;
    endtask

    task automatic reset_dut;
        rst = 1'b1;
        clear_requests();
        ic_resp_ready = 1'b0;
        dc_resp_ready = 1'b0;
        dram_ready = 1'b1;
        dram_raddr = '0;
        dram_rdata = '0;
        dram_rvalid = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic send_ic_read(
        input xlen_t line_addr,
        input logic [CACHE_MSHR_ID_BITS-1:0] mshr_id
    );
        @(negedge clk);
        ic_req = make_request(cache_src_icache,
                              cache_req_demand_read,
                              line_addr,
                              mshr_id);
        ic_req_valid = 1'b1;
        #1ns;
        if (!ic_req_ready || !dram_read || (dram_addr !== line_addr)) begin
            $fatal(1, "I-cache read was not accepted and issued");
        end
        @(posedge clk);
        @(negedge clk);
        clear_requests();
    endtask

    task automatic return_line(
        input xlen_t line_addr,
        input logic [CACHE_LINE_BITS-1:0] line_data
    );
        for (integer unsigned beat = 0; beat < 4; beat = beat + 1) begin
            @(negedge clk);
            dram_rvalid = 1'b1;
            dram_raddr = line_addr;
            dram_rdata = line_data[beat*64 +: 64];
            @(posedge clk);
        end
        @(negedge clk);
        dram_rvalid = 1'b0;
        dram_raddr = '0;
        dram_rdata = '0;
    endtask

    task automatic test_read_and_backpressure;
        logic [CACHE_LINE_BITS-1:0] expected;
        cache_mem_resp_t held;

        expected = {
            64'h4444444444444444,
            64'h3333333333333333,
            64'h2222222222222222,
            64'h1111111111111111
        };

        reset_dut();
        send_ic_read(32'h00001000, CACHE_MSHR_ID_BITS'(3));
        return_line(32'h00001000, expected);
        #1ns;

        if (!ic_resp_valid || (ic_resp.mshr_id !== CACHE_MSHR_ID_BITS'(3)) ||
            (ic_resp.line_addr !== 32'h00001000) ||
            (ic_resp.line_data !== expected)) begin
            $fatal(1, "I-cache line response was incorrect");
        end

        held = ic_resp;
        @(posedge clk);
        #1ns;
        if (!ic_resp_valid || (ic_resp !== held)) begin
            $fatal(1, "I-cache response changed under backpressure");
        end

        @(negedge clk);
        ic_resp_ready = 1'b1;
        @(posedge clk);
        #1ns;
        ic_resp_ready = 1'b0;
        if (ic_resp_valid) begin
            $fatal(1, "I-cache response did not retire after ready");
        end
    endtask

    task automatic test_cross_cache_merge;
        logic [CACHE_LINE_BITS-1:0] expected;

        expected = {
            64'ha4a4a4a4a4a4a4a4,
            64'ha3a3a3a3a3a3a3a3,
            64'ha2a2a2a2a2a2a2a2,
            64'ha1a1a1a1a1a1a1a1
        };

        reset_dut();
        send_ic_read(32'h00002000, CACHE_MSHR_ID_BITS'(4));

        @(negedge clk);
        dc_req = make_request(cache_src_dcache,
                              cache_req_demand_read,
                              32'h00002000,
                              CACHE_MSHR_ID_BITS'(7));
        dc_req_valid = 1'b1;
        #1ns;
        if (!dc_req_ready || dram_read) begin
            $fatal(1, "same-line D-cache request was not merged");
        end
        @(posedge clk);
        @(negedge clk);
        clear_requests();

        return_line(32'h00002000, expected);
        #1ns;
        if (!ic_resp_valid || !dc_resp_valid ||
            (ic_resp.mshr_id !== CACHE_MSHR_ID_BITS'(4)) ||
            (dc_resp.mshr_id !== CACHE_MSHR_ID_BITS'(7)) ||
            (ic_resp.line_data !== expected) || (dc_resp.line_data !== expected)) begin
            $fatal(1, "merged response did not wake both caches");
        end

        ic_resp_ready = 1'b1;
        @(posedge clk);
        #1ns;
        ic_resp_ready = 1'b0;
        if (ic_resp_valid || !dc_resp_valid) begin
            $fatal(1, "independent merged-response backpressure failed");
        end

        dc_resp_ready = 1'b1;
        @(posedge clk);
        #1ns;
        dc_resp_ready = 1'b0;
        if (dc_resp_valid) begin
            $fatal(1, "merged entry did not retire after both consumers");
        end
    endtask

    task automatic test_priority;
        reset_dut();
        @(negedge clk);
        ic_req = make_request(cache_src_icache,
                              cache_req_prefetch_read,
                              32'h00003000,
                              CACHE_MSHR_ID_BITS'(1));
        dc_req = make_request(cache_src_dcache,
                              cache_req_demand_read,
                              32'h00004000,
                              CACHE_MSHR_ID_BITS'(2));
        ic_req_valid = 1'b1;
        dc_req_valid = 1'b1;
        #1ns;

        if (ic_req_ready || !dc_req_ready || !dram_read ||
            (dram_addr !== 32'h00004000)) begin
            $fatal(1, "D-cache demand did not outrank I-cache prefetch");
        end
    endtask

    task automatic test_writeback;
        logic [CACHE_LINE_BITS-1:0] write_line;

        write_line = {
            64'hd4d4d4d4d4d4d4d4,
            64'hd3d3d3d3d3d3d3d3,
            64'hd2d2d2d2d2d2d2d2,
            64'hd1d1d1d1d1d1d1d1
        };

        reset_dut();
        @(negedge clk);
        dc_req = make_request(cache_src_dcache,
                              cache_req_writeback,
                              32'h00005000,
                              CACHE_MSHR_ID_BITS'(9));
        dc_req.line_wdata = write_line;
        dc_req_valid = 1'b1;
        #1ns;
        if (!dc_req_ready || dram_write) begin
            $fatal(1, "writeback request acceptance was incorrect");
        end

        @(posedge clk);
        @(negedge clk);
        clear_requests();

        for (integer unsigned beat = 0; beat < 4; beat = beat + 1) begin
            #1ns;
            if (!dram_write || (dram_addr !== 32'h00005000) ||
                (dram_wdata !== write_line[beat*64 +: 64])) begin
                $fatal(1, "writeback beat %0d was incorrect", beat);
            end
            @(posedge clk);
            if (beat != 3) begin
                @(negedge clk);
            end
        end

        #1ns;
        if (!dc_resp_valid || (dc_resp.mshr_id !== CACHE_MSHR_ID_BITS'(9)) ||
            (dc_resp.line_addr !== 32'h00005000)) begin
            $fatal(1, "writeback completion response was incorrect");
        end

        dc_resp_ready = 1'b1;
        @(posedge clk);
        #1ns;
        dc_resp_ready = 1'b0;
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        clear_requests();
        ic_resp_ready = 1'b0;
        dc_resp_ready = 1'b0;
        dram_ready = 1'b1;
        dram_raddr = '0;
        dram_rdata = '0;
        dram_rvalid = 1'b0;

        test_read_and_backpressure();
        test_cross_cache_merge();
        test_priority();
        test_writeback();

        $display("cache_adapter_ooo_tb: PASS");
        $finish;
    end
endmodule : cache_adapter_ooo_tb
