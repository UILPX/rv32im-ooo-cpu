module br_pred_tb;
    timeunit 1ns;
    timeprecision 1ps;

    logic          clk;
    logic          rst;
    logic          predecode_valid_0;
    logic          predecode_valid_1;
    logic [31:0]   predecode_inst_0;
    logic [31:0]   predecode_inst_1;
    logic          predecode_flush;
    logic [31:0]   pc_0;
    logic [31:0]   pc_1;
    logic          update_valid;
    logic [31:0]   update_pc;
    logic          update_is_cond_branch;
    logic          update_is_jalr;
    logic          update_is_call;
    logic          update_is_return;
    logic          update_taken;
    logic [31:0]   update_target;
    logic [1:0]    taken;
    logic [31:0]   jump_pc_0;
    logic [31:0]   jump_pc_1;

    localparam logic [31:0] NOP          = 32'h00000013;
    localparam logic [31:0] BEQ_PLUS_8   = 32'h00000463;
    localparam logic [31:0] JAL_PLUS_12  = 32'h00c0006f;
    localparam logic [31:0] RETURN_X1    = 32'h00008067;
    localparam logic [31:0] AUIPC_X1_4K  = 32'h00001097;
    localparam logic [31:0] JALR_X1_8    = 32'h008080e7;

    br_pred #(
        .PHT_ENTRIES(8),
        .RAS_ENTRIES(4)
    ) dut (.*);

    always #5ns clk = ~clk;

    task automatic clear_predecode;
        predecode_valid_0 = 1'b0;
        predecode_valid_1 = 1'b0;
        predecode_inst_0 = NOP;
        predecode_inst_1 = NOP;
        predecode_flush = 1'b0;
        pc_0 = '0;
        pc_1 = '0;
    endtask

    task automatic clear_update;
        update_valid = 1'b0;
        update_pc = '0;
        update_is_cond_branch = 1'b0;
        update_is_jalr = 1'b0;
        update_is_call = 1'b0;
        update_is_return = 1'b0;
        update_taken = 1'b0;
        update_target = '0;
    endtask

    task automatic train_branch(
        input logic [31:0] branch_pc,
        input logic        actual_taken
    );
        @(negedge clk);
        clear_update();
        update_valid = 1'b1;
        update_pc = branch_pc;
        update_is_cond_branch = 1'b1;
        update_taken = actual_taken;
        update_target = branch_pc + 32'd8;
        @(posedge clk);
        #1ns;
        clear_update();
    endtask

    task automatic test_conditional_prediction;
        predecode_valid_0 = 1'b1;
        predecode_inst_0 = BEQ_PLUS_8;
        pc_0 = 32'h00000100;
        #1ns;

        if (!taken[0] || (jump_pc_0 !== 32'h00000108)) begin
            $fatal(1, "reset PHT did not weakly predict the branch taken");
        end

        clear_predecode();
        train_branch(32'h00000100, 1'b0);
        train_branch(32'h00000100, 1'b0);

        predecode_valid_0 = 1'b1;
        predecode_inst_0 = BEQ_PLUS_8;
        pc_0 = 32'h00000100;
        #1ns;

        if (taken[0] || (jump_pc_0 !== 32'h00000108)) begin
            $fatal(1, "PHT did not learn a repeatedly not-taken branch");
        end

        clear_predecode();
    endtask

    task automatic test_dual_lane_jal;
        predecode_valid_0 = 1'b1;
        predecode_valid_1 = 1'b1;
        predecode_inst_0 = NOP;
        predecode_inst_1 = JAL_PLUS_12;
        pc_0 = 32'h00000200;
        pc_1 = 32'h00000204;
        #1ns;

        if (taken !== 2'b10 || (jump_pc_1 !== 32'h00000210)) begin
            $fatal(1, "lane-one JAL target prediction failed");
        end

        clear_predecode();
    endtask

    task automatic test_ras;
        @(negedge clk);
        clear_update();
        update_valid = 1'b1;
        update_pc = 32'h00000500;
        update_is_jalr = 1'b1;
        update_is_call = 1'b1;
        update_taken = 1'b1;
        update_target = 32'h00000900;
        @(posedge clk);
        #1ns;
        clear_update();

        predecode_valid_0 = 1'b1;
        predecode_inst_0 = RETURN_X1;
        pc_0 = 32'h00000900;
        #1ns;

        if (!taken[0] || (jump_pc_0 !== 32'h00000504)) begin
            $fatal(1, "RAS did not predict the committed call return address");
        end

        clear_predecode();
        @(negedge clk);
        update_valid = 1'b1;
        update_pc = 32'h00000900;
        update_is_jalr = 1'b1;
        update_is_return = 1'b1;
        update_taken = 1'b1;
        update_target = 32'h00000504;
        @(posedge clk);
        #1ns;
        clear_update();

        predecode_valid_0 = 1'b1;
        predecode_inst_0 = RETURN_X1;
        pc_0 = 32'h00000904;
        #1ns;

        if (taken[0]) begin
            $fatal(1, "RAS return did not pop its entry");
        end

        clear_predecode();
    endtask

    task automatic test_auipc_jalr_pair;
        predecode_valid_0 = 1'b1;
        predecode_valid_1 = 1'b1;
        predecode_inst_0 = AUIPC_X1_4K;
        predecode_inst_1 = JALR_X1_8;
        pc_0 = 32'h00000300;
        pc_1 = 32'h00000304;
        #1ns;

        if (!taken[1] || (jump_pc_1 !== 32'h00001308)) begin
            $fatal(1, "adjacent AUIPC/JALR target prediction failed");
        end

        @(posedge clk);
        #1ns;
        clear_predecode();

        @(negedge clk);
        predecode_valid_0 = 1'b1;
        predecode_inst_0 = AUIPC_X1_4K;
        pc_0 = 32'h00000400;
        @(posedge clk);
        #1ns;
        clear_predecode();

        predecode_valid_0 = 1'b1;
        predecode_inst_0 = JALR_X1_8;
        pc_0 = 32'h00000404;
        #1ns;

        if (!taken[0] || (jump_pc_0 !== 32'h00001408)) begin
            $fatal(1, "split AUIPC/JALR target prediction failed");
        end

        clear_predecode();
    endtask

    task automatic test_predecode_flush;
        @(negedge clk);
        predecode_valid_0 = 1'b1;
        predecode_inst_0 = AUIPC_X1_4K;
        pc_0 = 32'h00000600;
        @(posedge clk);
        #1ns;
        clear_predecode();

        @(negedge clk);
        predecode_flush = 1'b1;
        @(posedge clk);
        #1ns;
        clear_predecode();

        predecode_valid_0 = 1'b1;
        predecode_inst_0 = JALR_X1_8;
        pc_0 = 32'h00000604;
        #1ns;

        if (taken[0]) begin
            $fatal(1, "flush did not clear the pending AUIPC predecode state");
        end

        clear_predecode();
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        clear_predecode();
        clear_update();

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        test_conditional_prediction();
        test_dual_lane_jal();
        test_ras();
        test_auipc_jalr_pair();
        test_predecode_flush();

        $display("br_pred_tb: PASS");
        $finish;
    end
endmodule : br_pred_tb
