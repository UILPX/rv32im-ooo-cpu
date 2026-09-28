module commit_control_tb;
    logic clk;
    logic rst;
    logic [1:0] rob_commit_valid;
    rv32im_types::rob_commit_t rob_commit_data_0;
    rv32im_types::rob_commit_t rob_commit_data_1;
    logic [1:0] rob_commit_ready;
    logic [1:0] rename_commit_valid;
    rv32im_types::arch_reg_t rename_commit_arch_rd_0;
    rv32im_types::phys_reg_t rename_commit_new_phys_0;
    rv32im_types::phys_reg_t rename_commit_old_phys_0;
    rv32im_types::arch_reg_t rename_commit_arch_rd_1;
    rv32im_types::phys_reg_t rename_commit_new_phys_1;
    rv32im_types::phys_reg_t rename_commit_old_phys_1;
    logic [1:0] retire_valid;
    rv32im_types::rob_commit_t retire_data_0;
    rv32im_types::rob_commit_t retire_data_1;
    logic flush;
    logic redirect_valid;
    rv32im_types::xlen_t redirect_pc;
    logic bp_update_valid;
    rv32im_types::xlen_t bp_update_pc;
    logic bp_update_is_cond_branch;
    logic bp_update_is_jalr;
    logic bp_update_is_call;
    logic bp_update_is_return;
    logic bp_update_taken;
    rv32im_types::xlen_t bp_update_target;
    logic trap_valid;
    logic trap_ready;
    rv32im_types::exception_cause_t trap_cause;
    rv32im_types::xlen_t trap_pc;

    commit_control dut (.*);

    always #5 clk = ~clk;

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic clear_inputs;
        rob_commit_valid = 2'b00;
        rob_commit_data_0 = '0;
        rob_commit_data_1 = '0;
        trap_ready = 1'b0;
    endtask

    function automatic rv32im_types::rob_commit_t make_commit(
        input rv32im_types::uop_t op,
        input logic [31:0] pc,
        input logic allocates_rd,
        input logic [4:0] rd,
        input logic [5:0] new_phys,
        input logic [5:0] old_phys
    );
        rv32im_types::rob_commit_t result;
        begin
            result = '0;
            result.uop.renamed.decoded.op = op;
            result.uop.renamed.decoded.fetch.pc = pc;
            result.uop.renamed.decoded.rd = rd;
            result.uop.renamed.allocates_rd = allocates_rd;
            result.uop.renamed.phy_rd = new_phys;
            result.uop.renamed.stale_phy_rd = old_phys;
            result.result.valid = 1'b1;
            make_commit = result;
        end
    endfunction

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        clear_inputs();
        tick();
        rst = 1'b0;

        if (rob_commit_ready != 2'b11) $fatal(1, "idle controller not ready");

        rob_commit_valid = 2'b11;
        rob_commit_data_0 = make_commit(rv32im_types::OP_ADD, 32'h1000,
                                        1'b1, 5'd3, 6'd35, 6'd3);
        rob_commit_data_1 = make_commit(rv32im_types::OP_ADDI, 32'h1004,
                                        1'b1, 5'd4, 6'd36, 6'd4);
        #1;
        if (retire_valid != 2'b11 || rename_commit_valid != 2'b11)
            $fatal(1, "dual normal retirement failed");
        if (rename_commit_arch_rd_0 != 5'd3 || rename_commit_new_phys_0 != 6'd35 ||
            rename_commit_old_phys_0 != 6'd3 ||
            rename_commit_arch_rd_1 != 5'd4 || rename_commit_new_phys_1 != 6'd36 ||
            rename_commit_old_phys_1 != 6'd4 ||
            retire_data_0 !== rob_commit_data_0 ||
            retire_data_1 !== rob_commit_data_1)
            $fatal(1, "rename commit metadata mismatch");
        tick();
        clear_inputs();

        rob_commit_valid = 2'b11;
        rob_commit_data_0 = make_commit(rv32im_types::OP_BEQ, 32'h2000,
                                        1'b0, 5'd0, 6'd0, 6'd0);
        rob_commit_data_0.result.branch_valid = 1'b1;
        rob_commit_data_0.result.branch_taken = 1'b1;
        rob_commit_data_0.result.branch_target = 32'h2400;
        rob_commit_data_0.uop.renamed.decoded.imm = 32'h400;
        rob_commit_data_1 = make_commit(rv32im_types::OP_ADD, 32'h2004,
                                        1'b1, 5'd5, 6'd37, 6'd5);
        #1;
        if (retire_valid != 2'b11 || !bp_update_valid ||
            !bp_update_is_cond_branch || bp_update_is_jalr ||
            bp_update_is_call || bp_update_is_return || !bp_update_taken ||
            bp_update_pc != 32'h2000 ||
            bp_update_target != 32'h2400)
            $fatal(1, "correct branch retirement/training failed");
        tick();
        clear_inputs();

        rob_commit_valid = 2'b11;
        rob_commit_data_0 = make_commit(rv32im_types::OP_BEQ, 32'h3000,
                                        1'b0, 5'd0, 6'd0, 6'd0);
        rob_commit_data_0.result.branch_valid = 1'b1;
        rob_commit_data_1 = make_commit(rv32im_types::OP_JALR, 32'h3004,
                                        1'b1, 5'd1, 6'd38, 6'd1);
        rob_commit_data_1.result.branch_valid = 1'b1;
        #1;
        if (rob_commit_ready != 2'b01 || retire_valid != 2'b01)
            $fatal(1, "two branch commits used one predictor port");
        tick();
        clear_inputs();

        rob_commit_valid = 2'b11;
        rob_commit_data_0 = make_commit(rv32im_types::OP_JAL, 32'h4000,
                                        1'b1, 5'd1, 6'd39, 6'd1);
        rob_commit_data_0.result.branch_valid = 1'b1;
        rob_commit_data_0.result.branch_taken = 1'b1;
        rob_commit_data_0.result.branch_target = 32'h5000;
        rob_commit_data_0.result.branch_mispredict = 1'b1;
        rob_commit_data_1 = make_commit(rv32im_types::OP_ADD, 32'h4004,
                                        1'b1, 5'd6, 6'd40, 6'd6);
        #1;
        if (rob_commit_ready != 2'b01 || retire_valid != 2'b01 ||
            rename_commit_valid != 2'b01)
            $fatal(1, "lane 0 recovery did not stop younger commit");
        tick();
        clear_inputs();
        if (!flush || !redirect_valid || redirect_pc != 32'h5000 ||
            rob_commit_ready != 2'b00)
            $fatal(1, "registered branch recovery failed");
        tick();
        if (flush || redirect_valid) $fatal(1, "recovery pulse lasted too long");

        rob_commit_valid = 2'b11;
        rob_commit_data_0 = make_commit(rv32im_types::OP_ADD, 32'h6000,
                                        1'b1, 5'd7, 6'd41, 6'd7);
        rob_commit_data_1 = make_commit(rv32im_types::OP_JALR, 32'h6004,
                                        1'b0, 5'd0, 6'd0, 6'd0);
        rob_commit_data_1.uop.renamed.decoded.bp_is_call = 1'b1;
        rob_commit_data_1.uop.renamed.decoded.bp_is_return = 1'b1;
        rob_commit_data_1.result.branch_valid = 1'b1;
        rob_commit_data_1.result.branch_taken = 1'b1;
        rob_commit_data_1.result.branch_target = 32'h6400;
        rob_commit_data_1.result.branch_mispredict = 1'b1;
        #1;
        if (retire_valid != 2'b11 || rename_commit_valid != 2'b01 ||
            !bp_update_valid || bp_update_pc != 32'h6004 ||
            bp_update_is_cond_branch || !bp_update_is_jalr ||
            !bp_update_is_call || !bp_update_is_return || !bp_update_taken)
            $fatal(1, "lane 1 recovery retirement failed");
        tick();
        clear_inputs();
        if (!flush || !redirect_valid || redirect_pc != 32'h6400)
            $fatal(1, "lane 1 redirect failed");
        tick();

        rob_commit_valid = 2'b11;
        rob_commit_data_0 = make_commit(rv32im_types::OP_ECALL, 32'h7000,
                                        1'b0, 5'd0, 6'd0, 6'd0);
        rob_commit_data_0.result.exception_valid = 1'b1;
        rob_commit_data_0.result.exception_cause = rv32im_types::EXC_ECALL_MMODE;
        rob_commit_data_1 = make_commit(rv32im_types::OP_ADD, 32'h7004,
                                        1'b1, 5'd8, 6'd42, 6'd8);
        #1;
        if (retire_valid != 2'b01 || rename_commit_valid != 2'b00)
            $fatal(1, "exception retirement was not precise");
        tick();
        clear_inputs();
        if (!flush || redirect_valid || !trap_valid ||
            trap_cause != rv32im_types::EXC_ECALL_MMODE || trap_pc != 32'h7000)
            $fatal(1, "trap reporting failed");
        tick();
        if (!trap_valid || rob_commit_ready != 2'b00)
            $fatal(1, "trap was not held for ready");
        trap_ready = 1'b1;
        tick();
        trap_ready = 1'b0;
        if (trap_valid || rob_commit_ready != 2'b11)
            $fatal(1, "trap ready handshake failed");

        $display("commit_control_tb: PASS");
        $finish;
    end
endmodule : commit_control_tb
