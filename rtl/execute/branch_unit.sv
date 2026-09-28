module branch_unit (
    input   logic                           clk,
    input   logic                           rst,
    input   logic                           flush,

    input   logic                           issue_valid,
    /* verilator lint_off UNUSEDSIGNAL */
    input   rv32im_types::branch_issue_t    issue_data,
    /* verilator lint_on UNUSEDSIGNAL */
    output  logic                           issue_ready,

    output  rv32im_types::wb_bus_t          wb_data,
    input   logic                           wb_grant,

    output  logic                           result_valid,
    output  rv32im_types::rob_complete_t    complete_data
);

    typedef struct packed {
        logic                        valid;
        rv32im_types::rob_tag_t      rob_tag;
        rv32im_types::phys_reg_t     phy_rd;
        rv32im_types::xlen_t         link_value;
        logic                        taken;
        rv32im_types::xlen_t         target;
        logic                        mispredict;
        logic                        exception_valid;
    } result_t;

    result_t result_q, result_d;
    logic issue_fire;
    logic result_fire;
    logic actual_taken;
    logic [31:0] actual_target;
    logic [31:0] actual_next_pc;
    logic op_supported;
    logic target_misaligned;
    logic signed [31:0] signed_value_1;
    logic signed [31:0] signed_value_2;

    assign signed_value_1 = signed'(issue_data.value_1);
    assign signed_value_2 = signed'(issue_data.value_2);

    always_comb begin
        actual_taken = 1'b0;
        actual_target = issue_data.pc + issue_data.imm;
        op_supported = 1'b1;

        unique case (issue_data.op)
            rv32im_types::OP_BEQ:
                actual_taken = issue_data.value_1 == issue_data.value_2;
            rv32im_types::OP_BNE:
                actual_taken = issue_data.value_1 != issue_data.value_2;
            rv32im_types::OP_BLT:
                actual_taken = signed_value_1 < signed_value_2;
            rv32im_types::OP_BGE:
                actual_taken = signed_value_1 >= signed_value_2;
            rv32im_types::OP_BLTU:
                actual_taken = issue_data.value_1 < issue_data.value_2;
            rv32im_types::OP_BGEU:
                actual_taken = issue_data.value_1 >= issue_data.value_2;
            rv32im_types::OP_JAL: actual_taken = 1'b1;
            rv32im_types::OP_JALR: begin
                actual_taken = 1'b1;
                actual_target = (issue_data.value_1 + issue_data.imm) &
                                32'hffff_fffe;
            end
            default: begin
                op_supported = 1'b0;
                actual_taken = 1'b0;
                actual_target = issue_data.pc + 32'd4;
            end
        endcase
        actual_next_pc = actual_taken ? actual_target :
                                          (issue_data.pc + 32'd4);
        target_misaligned = op_supported && actual_taken &&
                            (actual_target[1:0] != 2'b00);
    end

    always_comb begin
        issue_ready = !flush && !result_q.valid && op_supported;
        issue_fire = issue_valid && issue_ready;
        result_valid = !flush && result_q.valid;

        wb_data = '0;
        wb_data.valid = !flush && result_q.valid &&
                        !result_q.exception_valid &&
                        (result_q.phy_rd != '0);
        wb_data.phy_rd = result_q.phy_rd;
        wb_data.value = result_q.link_value;

        result_fire = !flush && result_q.valid &&
            (result_q.exception_valid || (result_q.phy_rd == '0) || wb_grant);
        complete_data = '0;
        complete_data.valid = result_fire;
        complete_data.rob_tag = result_q.rob_tag;
        complete_data.rd_write = result_fire &&
                                 !result_q.exception_valid &&
                                 (result_q.phy_rd != '0);
        complete_data.rd_value = result_q.link_value;
        complete_data.branch_valid = result_q.valid;
        complete_data.branch_taken = result_q.taken;
        complete_data.branch_target = result_q.target;
        complete_data.branch_mispredict = result_q.mispredict;
        complete_data.exception_valid = result_q.exception_valid;
        complete_data.exception_cause = result_q.exception_valid
            ? rv32im_types::EXC_INST_MISALIGNED
            : rv32im_types::EXC_NONE;
    end

    always_comb begin
        result_d = result_q;
        if (result_fire) begin
            result_d = '0;
        end
        if (issue_fire) begin
            result_d.valid = 1'b1;
            result_d.rob_tag = issue_data.rob_tag;
            result_d.phy_rd = issue_data.phy_rd;
            result_d.link_value = issue_data.pc + 32'd4;
            result_d.taken = actual_taken;
            result_d.target = actual_next_pc;
            result_d.mispredict = !target_misaligned &&
                                  (actual_next_pc != issue_data.pred_pc);
            result_d.exception_valid = target_misaligned;
        end
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            result_q <= '0;
        end else begin
            result_q <= result_d;
        end
    end

endmodule : branch_unit
