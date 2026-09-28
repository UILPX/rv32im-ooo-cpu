module dispatch_buffer_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic flush;
    logic [1:0] push_valid;
    rob_uop_t push_data_0;
    rob_uop_t push_data_1;
    logic [1:0] push_ready;
    logic [1:0] dispatch_valid;
    rob_uop_t dispatch_data_0;
    rob_uop_t dispatch_data_1;
    logic [1:0] dispatch_ready;
    wb_bus_t wb_bus_0;
    wb_bus_t wb_bus_1;
    logic [2:0] count;

    dispatch_buffer #(.DEPTH(4)) dut (.*);

    always #5ns clk = ~clk;

    function automatic rob_uop_t make_uop(input rob_tag_t tag);
        rob_uop_t result;
        result = '0;
        result.rob_tag = tag;
        result.renamed.decoded.fetch.rvfi_order = 64'(tag);
        make_uop = result;
    endfunction

    initial begin
        rob_uop_t held_0;
        rob_uop_t held_1;

        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        push_valid = 2'b00;
        push_data_0 = '0;
        push_data_1 = '0;
        dispatch_ready = 2'b00;
        wb_bus_0 = '0;
        wb_bus_1 = '0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        push_valid = 2'b11;
        push_data_0 = make_uop(4'd0);
        push_data_1 = make_uop(4'd1);
        push_data_0.renamed.phy_rs1 = 6'd40;
        push_data_0.renamed.ready_rs1 = 1'b0;
        push_data_1.renamed.phy_rs2 = 6'd41;
        push_data_1.renamed.ready_rs2 = 1'b0;
        #1ns;
        if (push_ready != 2'b11) begin
            $fatal(1, "empty dispatch buffer was not ready");
        end
        @(posedge clk);
        @(negedge clk);
        push_valid = 2'b00;
        #1ns;
        if ((count != 3'd2) || (dispatch_valid != 2'b11) ||
            (dispatch_data_0.rob_tag != 4'd0) ||
            (dispatch_data_1.rob_tag != 4'd1)) begin
            $fatal(1, "dual push did not preserve dispatch order");
        end

        wb_bus_0.valid = 1'b1;
        wb_bus_0.phy_rd = 6'd40;
        wb_bus_1.valid = 1'b1;
        wb_bus_1.phy_rd = 6'd41;
        @(posedge clk);
        @(negedge clk);
        wb_bus_0 = '0;
        wb_bus_1 = '0;
        #1ns;
        if (!dispatch_data_0.renamed.ready_rs1 ||
            !dispatch_data_1.renamed.ready_rs2) begin
            $fatal(1, "buffered operands missed a completed writeback");
        end

        held_0 = dispatch_data_0;
        held_1 = dispatch_data_1;
        @(posedge clk);
        @(negedge clk);
        #1ns;
        if ((dispatch_data_0 != held_0) || (dispatch_data_1 != held_1)) begin
            $fatal(1, "blocked dispatch buffer data changed");
        end

        dispatch_ready = 2'b01;
        push_valid = 2'b01;
        push_data_0 = make_uop(4'd2);
        @(posedge clk);
        @(negedge clk);
        dispatch_ready = 2'b00;
        push_valid = 2'b00;
        #1ns;
        if ((count != 3'd2) || (dispatch_data_0.rob_tag != 4'd1) ||
            (dispatch_data_1.rob_tag != 4'd2)) begin
            $fatal(1, "simultaneous pop/push did not compact in order");
        end

        dispatch_ready = 2'b11;
        push_valid = 2'b11;
        push_data_0 = make_uop(4'd3);
        push_data_1 = make_uop(4'd4);
        @(posedge clk);
        @(negedge clk);
        dispatch_ready = 2'b00;
        push_valid = 2'b00;
        #1ns;
        if ((count != 3'd2) || (dispatch_data_0.rob_tag != 4'd3) ||
            (dispatch_data_1.rob_tag != 4'd4)) begin
            $fatal(1, "dual replace did not preserve the new bundle");
        end

        flush = 1'b1;
        #1ns;
        if ((dispatch_valid != 2'b00) || (push_ready != 2'b00)) begin
            $fatal(1, "flush did not suppress dispatch buffer transfers");
        end
        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        #1ns;
        if (count != '0) begin
            $fatal(1, "flush did not clear dispatch buffer");
        end

        $display("dispatch_buffer_tb: PASS");
        $finish;
    end

endmodule : dispatch_buffer_tb
