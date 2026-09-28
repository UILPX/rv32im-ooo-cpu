module lsu_tb;
    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic flush;
    logic [1:0] select;
    logic [1:0] port_bus1_sel;
    rv32im_types::res_stat_t dispatch_data_0;
    rv32im_types::res_stat_t dispatch_data_1;
    logic [1:0] port_ready;
    rv32im_types::wb_bus_t wb_bus_0;
    rv32im_types::wb_bus_t wb_bus_1;
    logic rob_head_valid;
    rv32im_types::rob_tag_t rob_head_tag;
    logic mem_req_valid;
    logic mem_req_ready;
    rv32im_types::dcache_cpu_req_t mem_req;
    logic mem_resp_valid;
    logic mem_resp_ready;
    rv32im_types::dcache_cpu_resp_t mem_resp;
    rv32im_types::wb_bus_t wb_data;
    logic wb_grant;
    rv32im_types::rob_complete_t complete_data;
    logic complete_grant;
    logic [2:0] count;
    logic _unused_outputs;

    lsu #(.DEPTH(4)) dut (.*);

    assign _unused_outputs = &{1'b0, port_ready, wb_data, complete_data};

    always #5ns clk = ~clk;

    function automatic rv32im_types::res_stat_t make_mem(
        input rv32im_types::uop_t op,
        input logic [3:0] tag,
        input logic [5:0] phy_rd,
        input logic [31:0] base,
        input logic [31:0] offset,
        input logic [31:0] store_data
    );
        rv32im_types::res_stat_t result;
        begin
            result = '0;
            result.op = op;
            result.rob_tag = tag;
            result.phy_rd = phy_rd;
            result.ready_1 = 1'b1;
            result.ready_2 = 1'b1;
            result.value_1 = base;
            result.value_2 = store_data;
            result.imm = offset;
            make_mem = result;
        end
    endfunction

    task automatic clear_inputs;
        select = 2'b00;
        port_bus1_sel = 2'b00;
        dispatch_data_0 = '0;
        dispatch_data_1 = '0;
        wb_bus_0 = '0;
        wb_bus_1 = '0;
        rob_head_valid = 1'b0;
        rob_head_tag = '0;
        mem_req_ready = 1'b0;
        mem_resp_valid = 1'b0;
        mem_resp = '0;
        wb_grant = 1'b0;
        complete_grant = 1'b0;
    endtask

    task automatic dispatch_one(input rv32im_types::res_stat_t entry);
        @(negedge clk);
        dispatch_data_0 = entry;
        select = 2'b01;
        #1ns;
        if (!port_ready[0]) $fatal(1, "LSU queue unexpectedly full");
        @(posedge clk);
        @(negedge clk);
        select = 2'b00;
        dispatch_data_0 = '0;
    endtask

    task automatic accept_request;
        while (!mem_req_valid) @(negedge clk);
        mem_req_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        mem_req_ready = 1'b0;
    endtask

    task automatic return_response(input logic [31:0] data);
        mem_resp_valid = 1'b1;
        mem_resp.rdata = data;
        mem_resp.id = mem_req.id;
        while (!mem_resp_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        mem_resp_valid = 1'b0;
        mem_resp = '0;
    endtask

    task automatic grant_result;
        complete_grant = 1'b1;
        wb_grant = 1'b1;
        @(posedge clk);
        @(negedge clk);
        complete_grant = 1'b0;
        wb_grant = 1'b0;
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        dispatch_one(make_mem(rv32im_types::OP_LB, 4'd1, 6'd32,
                              32'h1000, 32'd1, 32'd0));
        accept_request();
        if (mem_req.addr != 32'h1001 || mem_req.rmask != 4'b0001 ||
            mem_req.wmask != 4'b0000)
            $fatal(1, "byte-load request formatting failed");
        return_response(32'h0000_0080);
        #1ns;
        if (!complete_data.valid || complete_data.rob_tag != 4'd1 ||
            !complete_data.rd_write || complete_data.rd_value != 32'hffff_ff80 ||
            !complete_data.mem_valid || complete_data.mem_addr != 32'h1001 ||
            wb_data.value != 32'hffff_ff80)
            $fatal(1, "signed byte-load completion failed");
        grant_result();

        dispatch_one(make_mem(rv32im_types::OP_SW, 4'd2, 6'd0,
                              32'h2000, 32'd0, 32'hdead_beef));
        repeat (2) @(negedge clk);
        if (mem_req_valid) $fatal(1, "store issued before reaching ROB head");
        rob_head_valid = 1'b1;
        rob_head_tag = 4'd2;
        accept_request();
        if (mem_req.addr != 32'h2000 || mem_req.wmask != 4'b1111 ||
            mem_req.wdata != 32'hdead_beef)
            $fatal(1, "store request formatting failed");
        return_response(32'd0);
        #1ns;
        if (!complete_data.valid || complete_data.rd_write ||
            complete_data.mem_wmask != 4'b1111 ||
            complete_data.mem_wdata != 32'hdead_beef || wb_data.valid)
            $fatal(1, "store completion failed");
        grant_result();
        rob_head_valid = 1'b0;

        dispatch_one(make_mem(rv32im_types::OP_LH, 4'd3, 6'd33,
                              32'h3000, 32'd1, 32'd0));
        repeat (2) @(negedge clk);
        if (!complete_data.valid || !complete_data.exception_valid ||
            complete_data.exception_cause != rv32im_types::EXC_LOAD_MISALIGNED ||
            mem_req_valid)
            $fatal(1, "misaligned load did not trap locally");
        grant_result();

        dispatch_data_0 = make_mem(rv32im_types::OP_LW, 4'd4, 6'd34,
                                   32'h0, 32'd0, 32'd0);
        dispatch_data_0.ready_1 = 1'b0;
        dispatch_data_0.phy_rs1 = 6'd40;
        dispatch_one(dispatch_data_0);
        repeat (2) @(negedge clk);
        if (mem_req_valid) $fatal(1, "load issued before base wakeup");
        wb_bus_0.valid = 1'b1;
        wb_bus_0.phy_rd = 6'd40;
        wb_bus_0.value = 32'h4000;
        @(posedge clk);
        @(negedge clk);
        wb_bus_0 = '0;
        accept_request();
        return_response(32'h1234_5678);
        #1ns;
        if (wb_data.value != 32'h1234_5678)
            $fatal(1, "woken word load returned wrong value");
        grant_result();

        dispatch_one(make_mem(rv32im_types::OP_LW, 4'd5, 6'd35,
                              32'h5000, 32'd0, 32'd0));
        accept_request();
        flush = 1'b1;
        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        #1ns;
        if (complete_data.valid || !mem_resp_ready || count != '0)
            $fatal(1, "flush did not enter response drain state");
        return_response(32'hfeed_face);
        repeat (2) @(negedge clk);
        if (complete_data.valid)
            $fatal(1, "flushed load produced a stale completion");

        $display("lsu_tb: PASS");
        $finish;
    end

endmodule : lsu_tb
