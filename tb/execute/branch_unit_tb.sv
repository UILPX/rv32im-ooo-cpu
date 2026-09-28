module branch_unit_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic flush;
    logic issue_valid;
    branch_issue_t issue_data;
    logic issue_ready;
    wb_bus_t wb_data;
    logic wb_grant;
    logic result_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    rob_complete_t complete_data;
    /* verilator lint_on UNUSEDSIGNAL */

    branch_unit dut (.*);

    always #5ns clk = ~clk;

    task automatic run_branch(
        input uop_t op,
        input logic [31:0] value_1,
        input logic [31:0] value_2,
        input logic expected_taken,
        input logic expected_mispredict,
        input rob_tag_t tag
    );
        logic [31:0] expected_target;
        logic [31:0] expected_next_pc;
        expected_target = 32'h8000_0100 + 32'd16;
        expected_next_pc = expected_taken ? expected_target : 32'h8000_0104;

        @(negedge clk);
        issue_valid = 1'b1;
        issue_data = '0;
        issue_data.pc = 32'h8000_0100;
        issue_data.imm = 32'd16;
        issue_data.op = op;
        issue_data.value_1 = value_1;
        issue_data.value_2 = value_2;
        issue_data.rob_tag = tag;
        issue_data.pred_pc = expected_mispredict
            ? (expected_taken ? 32'h8000_0104 : expected_target)
            : (expected_taken ? expected_target : 32'h8000_0104);
        #1ns;
        if (!issue_ready) begin
            $fatal(1, "branch unit rejected operation %0d", op);
        end
        @(posedge clk);
        @(negedge clk);
        issue_valid = 1'b0;
        #1ns;
        if (!result_valid || wb_data.valid || !complete_data.valid ||
            (complete_data.rob_tag != tag) ||
            !complete_data.branch_valid ||
            (complete_data.branch_taken != expected_taken) ||
            (complete_data.branch_target != expected_next_pc) ||
            (complete_data.branch_mispredict != expected_mispredict)) begin
            $fatal(1, "branch resolution mismatch for operation %0d", op);
        end
        @(posedge clk);
    endtask

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
        run_branch(OP_BEQ,  32'd7, 32'd7, 1'b1,  1'b0, 4'd0);
        run_branch(OP_BNE,  32'd7, 32'd7, 1'b0,  1'b0, 4'd1);
        run_branch(OP_BLT,  32'hffff_ffff, 32'd1, 1'b1, 1'b1, 4'd2);
        run_branch(OP_BGE,  32'hffff_ffff, 32'd1, 1'b0, 1'b1, 4'd3);
        run_branch(OP_BLTU, 32'hffff_ffff, 32'd1, 1'b0, 1'b0, 4'd4);
        run_branch(OP_BGEU, 32'hffff_ffff, 32'd1, 1'b1, 1'b0, 4'd5);

        @(negedge clk);
        issue_valid = 1'b1;
        issue_data = '0;
        issue_data.pc = 32'h8000_0200;
        issue_data.imm = 32'd12;
        issue_data.op = OP_JAL;
        issue_data.phy_rd = 6'd40;
        issue_data.rob_tag = 4'd6;
        issue_data.pred_pc = 32'h8000_020c;
        @(posedge clk);
        @(negedge clk);
        issue_valid = 1'b0;
        #1ns;
        if (!result_valid || !wb_data.valid || (wb_data.phy_rd != 6'd40) ||
            (wb_data.value != 32'h8000_0204) || complete_data.valid) begin
            $fatal(1, "JAL link writeback did not wait for grant");
        end
        wb_grant = 1'b1;
        #1ns;
        if (!complete_data.valid || !complete_data.branch_taken ||
            !complete_data.rd_write ||
            (complete_data.rd_value != 32'h8000_0204) ||
            (complete_data.branch_target != 32'h8000_020c) ||
            complete_data.branch_mispredict) begin
            $fatal(1, "JAL resolution or completion was incorrect");
        end
        @(posedge clk);
        @(negedge clk);
        wb_grant = 1'b0;

        issue_valid = 1'b1;
        issue_data = '0;
        issue_data.pc = 32'h8000_0280;
        issue_data.imm = 32'd2;
        issue_data.op = OP_JAL;
        issue_data.phy_rd = 6'd41;
        issue_data.rob_tag = 4'd9;
        issue_data.pred_pc = 32'h8000_0282;
        @(posedge clk);
        @(negedge clk);
        issue_valid = 1'b0;
        #1ns;
        if (!result_valid || wb_data.valid || !complete_data.valid ||
            !complete_data.exception_valid ||
            (complete_data.exception_cause != EXC_INST_MISALIGNED) ||
            complete_data.rd_write || complete_data.branch_mispredict ||
            (complete_data.rob_tag != 4'd9)) begin
            $fatal(1, "misaligned JAL did not produce a precise exception");
        end
        @(posedge clk);
        @(negedge clk);

        issue_valid = 1'b1;
        issue_data = '0;
        issue_data.pc = 32'h8000_0300;
        issue_data.imm = 32'd3;
        issue_data.op = OP_JALR;
        issue_data.value_1 = 32'h0000_0205;
        issue_data.rob_tag = 4'd7;
        issue_data.pred_pc = 32'h8000_0304;
        @(posedge clk);
        @(negedge clk);
        issue_valid = 1'b0;
        #1ns;
        if (!complete_data.valid ||
            (complete_data.branch_target != 32'h0000_0208) ||
            !complete_data.branch_mispredict) begin
            $fatal(1, "JALR target alignment or redirect detection failed");
        end
        @(posedge clk);
        @(negedge clk);

        issue_valid = 1'b1;
        issue_data.op = OP_ADD;
        #1ns;
        if (issue_ready) begin
            $fatal(1, "branch unit accepted a non-control operation");
        end
        issue_valid = 1'b0;

        issue_data = '0;
        issue_data.op = OP_JAL;
        issue_data.rob_tag = 4'd8;
        issue_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        issue_valid = 1'b0;
        flush = 1'b1;
        #1ns;
        if (result_valid || wb_data.valid || complete_data.valid || issue_ready) begin
            $fatal(1, "flush did not suppress the branch result buffer");
        end

        $display("branch_unit_tb: PASS");
        $finish;
    end

endmodule : branch_unit_tb
