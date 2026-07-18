module alu_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic          clk;
    logic          rst;
    logic          flush;
    logic          issue_valid;
    simple_issue_t issue_data;
    logic          issue_ready;
    wb_bus_t       wb_data;
    logic          wb_grant;

    alu dut (.*);

    always #5ns clk = ~clk;

    task automatic run_case(
        input uop_t     op,
        input xlen_t    a,
        input xlen_t    b,
        input xlen_t    expected,
        input phys_reg_t phy_rd
    );
        wb_bus_t held;

        @(negedge clk);
        issue_valid        = 1'b1;
        issue_data.op      = op;
        issue_data.phy_rd  = phy_rd;
        issue_data.value_1 = a;
        issue_data.value_2 = b;
        #1ns;

        if (!issue_ready) begin
            $fatal(1, "ALU did not accept supported op %0d", op);
        end

        @(posedge clk);
        #1ns;
        held = wb_data;
        if (!held.valid || (held.phy_rd !== phy_rd) ||
            (held.value !== expected)) begin
            $fatal(1,
                   "op %0d expected rd=%0d value=%08h, got valid=%0b rd=%0d value=%08h",
                   op, phy_rd, expected, held.valid, held.phy_rd, held.value);
        end

        @(negedge clk);
        issue_valid = 1'b0;
        @(posedge clk);
        #1ns;
        if (wb_data !== held) begin
            $fatal(1, "ALU writeback changed under backpressure for op %0d", op);
        end

        @(negedge clk);
        wb_grant = 1'b1;
        @(posedge clk);
        #1ns;
        if (wb_data.valid) begin
            $fatal(1, "ALU writeback did not clear after grant");
        end

        @(negedge clk);
        wb_grant = 1'b0;
    endtask

    task automatic test_invalid_op;
        @(negedge clk);
        issue_valid = 1'b1;
        issue_data = '0;
        issue_data.op = OP_JAL;
        #1ns;

        if (issue_ready) begin
            $fatal(1, "ALU accepted unsupported control operation");
        end

        @(posedge clk);
        #1ns;
        if (wb_data.valid) begin
            $fatal(1, "unsupported operation produced a writeback");
        end

        @(negedge clk);
        issue_valid = 1'b0;
    endtask

    task automatic test_backpressure;
        wb_bus_t held;

        @(negedge clk);
        issue_valid        = 1'b1;
        issue_data.op      = OP_ADD;
        issue_data.phy_rd  = phys_reg_t'(40);
        issue_data.value_1 = 32'd10;
        issue_data.value_2 = 32'd20;
        @(posedge clk);
        #1ns;
        held = wb_data;

        @(negedge clk);
        issue_data.op      = OP_SUB;
        issue_data.phy_rd  = phys_reg_t'(41);
        issue_data.value_1 = 32'd50;
        issue_data.value_2 = 32'd8;
        #1ns;
        if (issue_ready) begin
            $fatal(1, "ALU accepted a second request while writeback was blocked");
        end

        @(posedge clk);
        #1ns;
        if (wb_data !== held) begin
            $fatal(1, "blocked ALU result was not stable");
        end

        @(negedge clk);
        wb_grant = 1'b1;
        @(posedge clk);
        #1ns;
        if (wb_data.valid || !issue_ready) begin
            $fatal(1, "ALU did not expose its documented grant-to-accept bubble");
        end

        @(negedge clk);
        wb_grant = 1'b0;
        @(posedge clk);
        #1ns;
        if (!wb_data.valid || (wb_data.phy_rd !== phys_reg_t'(41)) ||
            (wb_data.value !== 32'd42)) begin
            $fatal(1, "held second ALU request did not complete after backpressure");
        end

        @(negedge clk);
        issue_valid = 1'b0;
        wb_grant = 1'b1;
        @(posedge clk);
        @(negedge clk);
        wb_grant = 1'b0;
    endtask

    task automatic test_flush;
        @(negedge clk);
        issue_valid        = 1'b1;
        issue_data.op      = OP_ADD;
        issue_data.phy_rd  = phys_reg_t'(50);
        issue_data.value_1 = 32'd1;
        issue_data.value_2 = 32'd2;
        @(posedge clk);
        #1ns;
        if (!wb_data.valid) begin
            $fatal(1, "flush test did not create a buffered result");
        end

        @(negedge clk);
        flush = 1'b1;
        @(posedge clk);
        #1ns;
        if (wb_data.valid || issue_ready) begin
            $fatal(1, "flush did not clear and suppress the ALU");
        end

        @(negedge clk);
        flush = 1'b0;
        issue_valid = 1'b0;
    endtask

    initial begin
        clk         = 1'b0;
        rst         = 1'b1;
        flush       = 1'b0;
        issue_valid = 1'b0;
        issue_data  = '0;
        wb_grant    = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        run_case(OP_ADD,   32'hffff_ffff, 32'd1,         32'd0,         phys_reg_t'(1));
        run_case(OP_ADDI,  32'd10,        32'd20,        32'd30,        phys_reg_t'(2));
        run_case(OP_AUIPC, 32'h1000_0000, 32'h0000_1234, 32'h1000_1234, phys_reg_t'(3));
        run_case(OP_SUB,   32'd3,         32'd7,         32'hffff_fffc, phys_reg_t'(4));
        run_case(OP_XOR,   32'hf0f0_0f0f, 32'hffff_0000, 32'h0f0f_0f0f, phys_reg_t'(5));
        run_case(OP_XORI,  32'haa55_aa55, 32'h0f0f_0f0f, 32'ha55a_a55a, phys_reg_t'(6));
        run_case(OP_OR,    32'hf000_000f, 32'h0f00_00f0, 32'hff00_00ff, phys_reg_t'(7));
        run_case(OP_ORI,   32'h0000_00f0, 32'h0000_000f, 32'h0000_00ff, phys_reg_t'(8));
        run_case(OP_AND,   32'hff00_ff00, 32'h0ff0_0ff0, 32'h0f00_0f00, phys_reg_t'(9));
        run_case(OP_ANDI,  32'hffff_1234, 32'h0000_ffff, 32'h0000_1234, phys_reg_t'(10));
        run_case(OP_SLL,   32'd1,         32'd31,        32'h8000_0000, phys_reg_t'(11));
        run_case(OP_SLLI,  32'd3,         32'd33,        32'd6,         phys_reg_t'(12));
        run_case(OP_SRL,   32'h8000_0000, 32'd31,        32'd1,         phys_reg_t'(13));
        run_case(OP_SRLI,  32'h8000_0000, 32'd33,        32'h4000_0000, phys_reg_t'(14));
        run_case(OP_SRA,   32'h8000_0000, 32'd31,        32'hffff_ffff, phys_reg_t'(15));
        run_case(OP_SRAI,  32'hffff_fff0, 32'd2,         32'hffff_fffc, phys_reg_t'(16));
        run_case(OP_SLT,   32'hffff_ffff, 32'd1,         32'd1,         phys_reg_t'(17));
        run_case(OP_SLTI,  32'd1,         32'hffff_ffff, 32'd0,         phys_reg_t'(18));
        run_case(OP_SLTU,  32'hffff_ffff, 32'd1,         32'd0,         phys_reg_t'(19));
        run_case(OP_SLTIU, 32'd1,         32'hffff_ffff, 32'd1,         phys_reg_t'(20));
        run_case(OP_LUI,   32'hdead_beef, 32'h1234_5000, 32'h1234_5000, phys_reg_t'(21));

        test_invalid_op();
        test_backpressure();
        test_flush();

        $display("PASS: alu directed tests");
        $finish;
    end
endmodule : alu_tb
