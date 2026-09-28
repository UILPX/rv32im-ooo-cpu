module commit_control (
    input   logic                           clk,
    input   logic                           rst,

    input   logic   [1:0]                   rob_commit_valid,
    input   rv32im_types::rob_commit_t      rob_commit_data_0,
    input   rv32im_types::rob_commit_t      rob_commit_data_1,
    output  logic   [1:0]                   rob_commit_ready,

    output  logic   [1:0]                   rename_commit_valid,
    output  rv32im_types::arch_reg_t        rename_commit_arch_rd_0,
    output  rv32im_types::phys_reg_t        rename_commit_new_phys_0,
    output  rv32im_types::phys_reg_t        rename_commit_old_phys_0,
    output  rv32im_types::arch_reg_t        rename_commit_arch_rd_1,
    output  rv32im_types::phys_reg_t        rename_commit_new_phys_1,
    output  rv32im_types::phys_reg_t        rename_commit_old_phys_1,

    output  logic   [1:0]                   retire_valid,
    output  rv32im_types::rob_commit_t      retire_data_0,
    output  rv32im_types::rob_commit_t      retire_data_1,

    output  logic                           flush,
    output  logic                           redirect_valid,
    output  rv32im_types::xlen_t            redirect_pc,

    output  logic                           bp_update_valid,
    output  rv32im_types::xlen_t            bp_update_pc,
    output  logic                           bp_update_is_cond_branch,
    output  logic                           bp_update_is_jalr,
    output  logic                           bp_update_is_call,
    output  logic                           bp_update_is_return,
    output  logic                           bp_update_taken,
    output  rv32im_types::xlen_t            bp_update_target,

    output  logic                           trap_valid,
    input   logic                           trap_ready,
    output  rv32im_types::exception_cause_t trap_cause,
    output  rv32im_types::xlen_t            trap_pc
);

    logic flush_q, flush_d;
    logic redirect_valid_q, redirect_valid_d;
    rv32im_types::xlen_t redirect_pc_q, redirect_pc_d;
    logic trap_valid_q, trap_valid_d;
    rv32im_types::exception_cause_t trap_cause_q, trap_cause_d;
    rv32im_types::xlen_t trap_pc_q, trap_pc_d;

    logic retire_0;
    logic retire_1;
    logic lane_0_stops;
    logic lane_0_is_branch;
    logic lane_1_is_branch;

    function automatic logic is_cond_branch(input rv32im_types::uop_t op);
        is_cond_branch = (op >= rv32im_types::OP_BEQ) &&
                         (op <= rv32im_types::OP_BGEU);
    endfunction

    function automatic rv32im_types::xlen_t branch_training_target(
        input rv32im_types::rob_commit_t commit_data
    );
        if (commit_data.uop.renamed.decoded.op == rv32im_types::OP_JALR) begin
            branch_training_target = commit_data.result.branch_target;
        end else begin
            branch_training_target =
                commit_data.uop.renamed.decoded.fetch.pc +
                commit_data.uop.renamed.decoded.imm;
        end
    endfunction

    always_comb begin
        lane_0_is_branch = rob_commit_data_0.result.branch_valid;
        lane_1_is_branch = rob_commit_data_1.result.branch_valid;
        lane_0_stops = rob_commit_data_0.result.exception_valid ||
                       rob_commit_data_0.result.branch_mispredict;

        rob_commit_ready = 2'b00;
        if (!flush_q && !trap_valid_q) begin
            rob_commit_ready[0] = 1'b1;
            rob_commit_ready[1] = !lane_0_stops &&
                                  !(lane_0_is_branch && lane_1_is_branch);
        end

        retire_0 = rob_commit_valid[0] && rob_commit_ready[0];
        retire_1 = retire_0 && rob_commit_valid[1] && rob_commit_ready[1];
        retire_valid = {retire_1, retire_0};
        retire_data_0 = rob_commit_data_0;
        retire_data_1 = rob_commit_data_1;

        rename_commit_valid = 2'b00;
        rename_commit_arch_rd_0 = rob_commit_data_0.uop.renamed.decoded.rd;
        rename_commit_new_phys_0 = rob_commit_data_0.uop.renamed.phy_rd;
        rename_commit_old_phys_0 = rob_commit_data_0.uop.renamed.stale_phy_rd;
        rename_commit_arch_rd_1 = rob_commit_data_1.uop.renamed.decoded.rd;
        rename_commit_new_phys_1 = rob_commit_data_1.uop.renamed.phy_rd;
        rename_commit_old_phys_1 = rob_commit_data_1.uop.renamed.stale_phy_rd;

        if (retire_0 && rob_commit_data_0.uop.renamed.allocates_rd &&
            !rob_commit_data_0.result.exception_valid) begin
            rename_commit_valid[0] = 1'b1;
        end
        if (retire_1 && rob_commit_data_1.uop.renamed.allocates_rd &&
            !rob_commit_data_1.result.exception_valid) begin
            rename_commit_valid[1] = 1'b1;
        end

        bp_update_valid = 1'b0;
        bp_update_pc = '0;
        bp_update_is_cond_branch = 1'b0;
        bp_update_is_jalr = 1'b0;
        bp_update_is_call = 1'b0;
        bp_update_is_return = 1'b0;
        bp_update_taken = 1'b0;
        bp_update_target = '0;

        if (retire_0 && lane_0_is_branch) begin
            bp_update_valid = 1'b1;
            bp_update_pc = rob_commit_data_0.uop.renamed.decoded.fetch.pc;
            bp_update_is_cond_branch =
                is_cond_branch(rob_commit_data_0.uop.renamed.decoded.op);
            bp_update_is_jalr =
                rob_commit_data_0.uop.renamed.decoded.op == rv32im_types::OP_JALR;
            bp_update_is_call = rob_commit_data_0.uop.renamed.decoded.bp_is_call;
            bp_update_is_return = rob_commit_data_0.uop.renamed.decoded.bp_is_return;
            bp_update_taken = rob_commit_data_0.result.branch_taken;
            bp_update_target = branch_training_target(rob_commit_data_0);
        end else if (retire_1 && lane_1_is_branch) begin
            bp_update_valid = 1'b1;
            bp_update_pc = rob_commit_data_1.uop.renamed.decoded.fetch.pc;
            bp_update_is_cond_branch =
                is_cond_branch(rob_commit_data_1.uop.renamed.decoded.op);
            bp_update_is_jalr =
                rob_commit_data_1.uop.renamed.decoded.op == rv32im_types::OP_JALR;
            bp_update_is_call = rob_commit_data_1.uop.renamed.decoded.bp_is_call;
            bp_update_is_return = rob_commit_data_1.uop.renamed.decoded.bp_is_return;
            bp_update_taken = rob_commit_data_1.result.branch_taken;
            bp_update_target = branch_training_target(rob_commit_data_1);
        end

        flush_d = 1'b0;
        redirect_valid_d = 1'b0;
        redirect_pc_d = redirect_pc_q;
        trap_valid_d = trap_valid_q;
        trap_cause_d = trap_cause_q;
        trap_pc_d = trap_pc_q;

        if (trap_valid_q && trap_ready) begin
            trap_valid_d = 1'b0;
        end

        if (retire_0 && rob_commit_data_0.result.exception_valid) begin
            flush_d = 1'b1;
            trap_valid_d = 1'b1;
            trap_cause_d = rob_commit_data_0.result.exception_cause;
            trap_pc_d = rob_commit_data_0.uop.renamed.decoded.fetch.pc;
        end else if (retire_0 && rob_commit_data_0.result.branch_mispredict) begin
            flush_d = 1'b1;
            redirect_valid_d = 1'b1;
            redirect_pc_d = rob_commit_data_0.result.branch_target;
        end else if (retire_1 && rob_commit_data_1.result.exception_valid) begin
            flush_d = 1'b1;
            trap_valid_d = 1'b1;
            trap_cause_d = rob_commit_data_1.result.exception_cause;
            trap_pc_d = rob_commit_data_1.uop.renamed.decoded.fetch.pc;
        end else if (retire_1 && rob_commit_data_1.result.branch_mispredict) begin
            flush_d = 1'b1;
            redirect_valid_d = 1'b1;
            redirect_pc_d = rob_commit_data_1.result.branch_target;
        end
    end

    assign flush = flush_q;
    assign redirect_valid = redirect_valid_q;
    assign redirect_pc = redirect_pc_q;
    assign trap_valid = trap_valid_q;
    assign trap_cause = trap_cause_q;
    assign trap_pc = trap_pc_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            flush_q <= 1'b0;
            redirect_valid_q <= 1'b0;
            redirect_pc_q <= '0;
            trap_valid_q <= 1'b0;
            trap_cause_q <= rv32im_types::EXC_NONE;
            trap_pc_q <= '0;
        end else begin
            flush_q <= flush_d;
            redirect_valid_q <= redirect_valid_d;
            redirect_pc_q <= redirect_pc_d;
            trap_valid_q <= trap_valid_d;
            trap_cause_q <= trap_cause_d;
            trap_pc_q <= trap_pc_d;
        end
    end

endmodule : commit_control
