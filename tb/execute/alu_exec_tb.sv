module alu_exec_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic flush;
    logic issue_valid;
    res_stat_t issue_data;
    logic issue_ready;
    wb_bus_t wb_data;
    logic wb_grant;
    logic result_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    rob_complete_t complete_data;
    /* verilator lint_on UNUSEDSIGNAL */

    alu_exec dut (.*);

    always #5ns clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        issue_valid = 1'b0;
        issue_data = '0;
        wb_grant = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        issue_valid = 1'b1;
        issue_data.op = OP_ADD;
        issue_data.phy_rd = 6'd32;
        issue_data.value_1 = 32'd19;
        issue_data.value_2 = 32'd23;
        issue_data.rob_tag = 4'd3;
        #1ns;
        if (!issue_ready) begin
            $fatal(1, "ALU execution adapter rejected a supported issue");
        end
        @(posedge clk);
        @(negedge clk);
        issue_valid = 1'b0;
        #1ns;
        if (!result_valid || !wb_data.valid || (wb_data.phy_rd != 6'd32) ||
            (wb_data.value != 32'd42) || complete_data.valid) begin
            $fatal(1, "ALU result completed before writeback grant");
        end

        wb_grant = 1'b1;
        #1ns;
        if (!complete_data.valid || (complete_data.rob_tag != 4'd3) ||
            !complete_data.rd_write || (complete_data.rd_value != 32'd42)) begin
            $fatal(1, "ALU writeback grant did not complete the ROB tag");
        end
        @(posedge clk);
        @(negedge clk);
        wb_grant = 1'b0;
        #1ns;
        if (result_valid || wb_data.valid || complete_data.valid) begin
            $fatal(1, "granted ALU result did not clear");
        end

        issue_valid = 1'b1;
        issue_data.op = OP_ADDI;
        issue_data.phy_rd = '0;
        issue_data.value_1 = 32'd1;
        issue_data.value_2 = 32'd2;
        issue_data.rob_tag = 4'd4;
        @(posedge clk);
        @(negedge clk);
        issue_valid = 1'b0;
        #1ns;
        if (!result_valid || wb_data.valid || !complete_data.valid ||
            complete_data.rd_write ||
            (complete_data.rd_value != 32'd3) ||
            (complete_data.rob_tag != 4'd4)) begin
            $fatal(1, "x0 ALU destination consumed writeback bandwidth");
        end
        @(posedge clk);
        @(negedge clk);

        issue_valid = 1'b1;
        issue_data.op = OP_SUB;
        issue_data.phy_rd = 6'd33;
        issue_data.value_1 = 32'd7;
        issue_data.value_2 = 32'd2;
        issue_data.rob_tag = 4'd5;
        @(posedge clk);
        @(negedge clk);
        issue_valid = 1'b0;
        flush = 1'b1;
        #1ns;
        if (result_valid || wb_data.valid || complete_data.valid || issue_ready) begin
            $fatal(1, "flush did not suppress buffered ALU execution state");
        end
        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        issue_valid = 1'b1;
        issue_data.op = OP_JAL;
        #1ns;
        if (issue_ready) begin
            $fatal(1, "ALU execution adapter accepted a branch operation");
        end

        $display("alu_exec_tb: PASS");
        $finish;
    end

endmodule : alu_exec_tb
