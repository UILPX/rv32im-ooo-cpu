module fetch_queue_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer unsigned DEPTH = 4;
    localparam integer unsigned COUNT_WIDTH = $clog2(DEPTH + 1);

    logic clk;
    logic rst;
    logic flush;
    logic [1:0] push_mask;
    fetch_inst_t push_data_0;
    fetch_inst_t push_data_1;
    logic [COUNT_WIDTH-1:0] slots_available;
    logic [1:0] dispatch_valid;
    fetch_inst_t dispatch_data_0;
    fetch_inst_t dispatch_data_1;
    logic [1:0] dispatch_ready;

    fetch_queue #(
        .DEPTH(DEPTH),
        .DISPATCH_WIDTH(2)
    ) dut (.*);

    always #5ns clk = ~clk;

    function automatic fetch_inst_t make_inst(
        input logic [31:0] pc,
        input logic [63:0] order
    );
        fetch_inst_t result;

        result = '0;
        result.pc = pc;
        result.inst = pc;
        result.rvfi_order = order;
        result.pred_pc = pc + 32'd4;
        return result;
    endfunction

    initial begin
        fetch_inst_t held_0;
        fetch_inst_t held_1;

        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        push_mask = 2'b00;
        push_data_0 = '0;
        push_data_1 = '0;
        dispatch_ready = 2'b00;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        push_mask = 2'b11;
        push_data_0 = make_inst(32'h1000, 64'd0);
        push_data_1 = make_inst(32'h1004, 64'd1);
        @(posedge clk);
        #1ns;
        push_mask = 2'b00;

        if ((dispatch_valid !== 2'b11) ||
            (dispatch_data_0.rvfi_order !== 64'd0) ||
            (dispatch_data_1.rvfi_order !== 64'd1)) begin
            $fatal(1, "dual push did not preserve instruction order");
        end

        held_0 = dispatch_data_0;
        held_1 = dispatch_data_1;
        @(posedge clk);
        #1ns;
        if ((dispatch_data_0 !== held_0) || (dispatch_data_1 !== held_1)) begin
            $fatal(1, "dispatch backpressure did not hold queue outputs stable");
        end

        @(negedge clk);
        dispatch_ready = 2'b01;
        @(posedge clk);
        #1ns;
        dispatch_ready = 2'b00;
        if ((dispatch_valid !== 2'b01) ||
            (dispatch_data_0.rvfi_order !== 64'd1)) begin
            $fatal(1, "single-lane dispatch did not advance by one entry");
        end

        @(negedge clk);
        dispatch_ready = 2'b01;
        push_mask = 2'b11;
        push_data_0 = make_inst(32'h1008, 64'd2);
        push_data_1 = make_inst(32'h100c, 64'd3);
        @(posedge clk);
        #1ns;
        dispatch_ready = 2'b00;
        push_mask = 2'b00;
        if ((dispatch_valid !== 2'b11) ||
            (dispatch_data_0.rvfi_order !== 64'd2) ||
            (dispatch_data_1.rvfi_order !== 64'd3)) begin
            $fatal(1, "simultaneous dequeue/enqueue corrupted queue order");
        end

        @(negedge clk);
        dispatch_ready = 2'b10;
        @(posedge clk);
        #1ns;
        dispatch_ready = 2'b00;
        if ((dispatch_data_0.rvfi_order !== 64'd2) ||
            (dispatch_data_1.rvfi_order !== 64'd3)) begin
            $fatal(1, "lane one dispatched without the older lane zero");
        end

        @(negedge clk);
        flush = 1'b1;
        #1ns;
        if (dispatch_valid != 2'b00) begin
            $fatal(1, "flush did not suppress dispatch immediately");
        end
        @(posedge clk);
        #1ns;
        flush = 1'b0;
        if ((dispatch_valid != 2'b00) ||
            (slots_available != COUNT_WIDTH'(DEPTH))) begin
            $fatal(1, "flush did not empty the fetch queue");
        end

        $display("fetch_queue_tb: PASS");
        $finish;
    end

endmodule : fetch_queue_tb
