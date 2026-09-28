module dispatch_router #(
    parameter integer unsigned DISPATCH_WIDTH = 2
) (
    input   logic                           flush,

    input   logic   [1:0]                   dispatch_valid,
    input   rv32im_types::rob_uop_t         dispatch_data_0,
    input   rv32im_types::rob_uop_t         dispatch_data_1,
    output  logic   [1:0]                   dispatch_ready,

    output  logic [3:0][rv32im_types::PHYS_REG_BITS-1:0] rf_raddr,
    input   logic [3:0][rv32im_types::XLEN-1:0]          rf_rdata,

    output  rv32im_types::res_stat_t        rs_data_0,
    output  rv32im_types::res_stat_t        rs_data_1,

    input   logic   [1:0]                   int_port_ready,
    output  logic   [1:0]                   int_select,
    output  logic   [1:0]                   int_port_bus1_sel,

    input   logic   [1:0]                   branch_port_ready,
    output  logic   [1:0]                   branch_select,
    output  logic   [1:0]                   branch_port_bus1_sel,

    input   logic   [1:0]                   muldiv_port_ready,
    output  logic   [1:0]                   muldiv_select,
    output  logic   [1:0]                   muldiv_port_bus1_sel,

    input   logic   [1:0]                   memory_port_ready,
    output  logic   [1:0]                   memory_select,
    output  logic   [1:0]                   memory_port_bus1_sel,

    input   logic                           system_ready,
    output  rv32im_types::rob_complete_t    system_complete_data_0,
    output  rv32im_types::rob_complete_t    system_complete_data_1
);

    logic lane_0_class_ready;
    logic lane_1_class_ready;
    logic lane_0_fire;
    logic lane_1_fire;
    logic lanes_same_class;

    if ((DISPATCH_WIDTH < 1) || (DISPATCH_WIDTH > 2)) begin : gen_invalid_parameters
        initial begin
            $error("dispatch_router requires width in 1..2");
        end
    end

    function automatic logic is_imm_alu(input rv32im_types::uop_t op);
        is_imm_alu = (op == rv32im_types::OP_LUI) ||
            (op == rv32im_types::OP_AUIPC) ||
            ((op >= rv32im_types::OP_ADDI) &&
             (op <= rv32im_types::OP_SRAI));
    endfunction

    function automatic rv32im_types::res_stat_t make_rs_entry(
        input rv32im_types::rob_uop_t in,
        input rv32im_types::xlen_t value_1,
        input rv32im_types::xlen_t value_2
    );
        rv32im_types::res_stat_t result;
        begin
            result = '0;
            result.op = in.renamed.decoded.op;
            result.phy_rd = in.renamed.phy_rd;
            result.phy_rs1 = in.renamed.phy_rs1;
            result.phy_rs2 = in.renamed.phy_rs2;
            result.ready_1 = in.renamed.ready_rs1;
            result.ready_2 = in.renamed.ready_rs2;
            result.value_1 = value_1;
            result.value_2 = value_2;
            result.pc = in.renamed.decoded.fetch.pc;
            result.imm = in.renamed.decoded.imm;
            result.rob_tag = in.rob_tag;
            result.pred_taken = in.renamed.decoded.fetch.pred_taken;
            result.pred_pc = in.renamed.decoded.fetch.pred_pc;
            result.bp_is_call = in.renamed.decoded.bp_is_call;
            result.bp_is_return = in.renamed.decoded.bp_is_return;

            if (!in.renamed.decoded.uses_rs1) begin
                result.phy_rs1 = '0;
                result.ready_1 = 1'b1;
                result.value_1 = '0;
            end
            if (!in.renamed.decoded.uses_rs2) begin
                result.phy_rs2 = '0;
                result.ready_2 = 1'b1;
                result.value_2 = '0;
            end
            if (is_imm_alu(in.renamed.decoded.op)) begin
                result.ready_2 = 1'b1;
                result.value_2 = in.renamed.decoded.imm;
            end
            if (in.renamed.decoded.op == rv32im_types::OP_AUIPC) begin
                result.ready_1 = 1'b1;
                result.value_1 = in.renamed.decoded.fetch.pc;
            end
            make_rs_entry = result;
        end
    endfunction

    always_comb begin
        rf_raddr[0] = dispatch_data_0.renamed.phy_rs1;
        rf_raddr[1] = dispatch_data_0.renamed.phy_rs2;
        rf_raddr[2] = dispatch_data_1.renamed.phy_rs1;
        rf_raddr[3] = dispatch_data_1.renamed.phy_rs2;
        rs_data_0 = make_rs_entry(dispatch_data_0, rf_rdata[0], rf_rdata[1]);
        rs_data_1 = make_rs_entry(dispatch_data_1, rf_rdata[2], rf_rdata[3]);

        unique case (dispatch_data_0.renamed.decoded.fu_class)
            rv32im_types::FU_INT:     lane_0_class_ready = int_port_ready[0];
            rv32im_types::FU_BRANCH:  lane_0_class_ready = branch_port_ready[0];
            rv32im_types::FU_MULDIV:  lane_0_class_ready = muldiv_port_ready[0];
            rv32im_types::FU_LOAD,
            rv32im_types::FU_STORE:   lane_0_class_ready = memory_port_ready[0];
            rv32im_types::FU_SYSTEM:  lane_0_class_ready = system_ready;
            default:                  lane_0_class_ready = system_ready;
        endcase

        lanes_same_class = dispatch_data_0.renamed.decoded.fu_class ==
                           dispatch_data_1.renamed.decoded.fu_class;
        unique case (dispatch_data_1.renamed.decoded.fu_class)
            rv32im_types::FU_INT: begin
                lane_1_class_ready = lanes_same_class
                    ? int_port_ready[1] : int_port_ready[0];
            end
            rv32im_types::FU_BRANCH: begin
                lane_1_class_ready = lanes_same_class
                    ? branch_port_ready[1] : branch_port_ready[0];
            end
            rv32im_types::FU_MULDIV: begin
                lane_1_class_ready = lanes_same_class
                    ? muldiv_port_ready[1] : muldiv_port_ready[0];
            end
            rv32im_types::FU_LOAD,
            rv32im_types::FU_STORE: begin
                lane_1_class_ready = lanes_same_class
                    ? memory_port_ready[1] : memory_port_ready[0];
            end
            // System and invalid operations are deliberately single-issued.
            // Their scalar readiness is evaluated for lane 0 at the ROB head.
            rv32im_types::FU_SYSTEM: lane_1_class_ready = 1'b0;
            default: lane_1_class_ready = 1'b0;
        endcase

        dispatch_ready = 2'b00;
        if (!flush) begin
            dispatch_ready[0] = lane_0_class_ready;
            if (DISPATCH_WIDTH > 1) begin
                dispatch_ready[1] = dispatch_ready[0] && lane_1_class_ready;
            end
        end
        lane_0_fire = dispatch_valid[0] && dispatch_ready[0];
        lane_1_fire = lane_0_fire && dispatch_valid[1] && dispatch_ready[1];

        int_select = 2'b00;
        int_port_bus1_sel = 2'b00;
        branch_select = 2'b00;
        branch_port_bus1_sel = 2'b00;
        muldiv_select = 2'b00;
        muldiv_port_bus1_sel = 2'b00;
        memory_select = 2'b00;
        memory_port_bus1_sel = 2'b00;
        system_complete_data_0 = '0;
        system_complete_data_1 = '0;
        system_complete_data_0.rob_tag = dispatch_data_0.rob_tag;
        system_complete_data_1.rob_tag = dispatch_data_1.rob_tag;

        if (lane_0_fire) begin
            unique case (dispatch_data_0.renamed.decoded.fu_class)
                rv32im_types::FU_INT:    int_select[0] = 1'b1;
                rv32im_types::FU_BRANCH: branch_select[0] = 1'b1;
                rv32im_types::FU_MULDIV: muldiv_select[0] = 1'b1;
                rv32im_types::FU_LOAD,
                rv32im_types::FU_STORE:  memory_select[0] = 1'b1;
                rv32im_types::FU_SYSTEM: begin
                    system_complete_data_0.valid = 1'b1;
                    if (dispatch_data_0.renamed.decoded.op == rv32im_types::OP_ECALL) begin
                        system_complete_data_0.exception_valid = 1'b1;
                        system_complete_data_0.exception_cause = rv32im_types::EXC_ECALL_MMODE;
                    end else if (dispatch_data_0.renamed.decoded.op == rv32im_types::OP_EBREAK) begin
                        system_complete_data_0.exception_valid = 1'b1;
                        system_complete_data_0.exception_cause = rv32im_types::EXC_BREAKPOINT;
                    end
                end
                default: begin
                    system_complete_data_0.valid = 1'b1;
                    system_complete_data_0.exception_valid = 1'b1;
                    system_complete_data_0.exception_cause =
                        rv32im_types::EXC_ILLEGAL;
                end
            endcase
        end

        if (lane_1_fire) begin
            unique case (dispatch_data_1.renamed.decoded.fu_class)
                rv32im_types::FU_INT: begin
                    if (int_select[0]) begin
                        int_select[1] = 1'b1;
                        int_port_bus1_sel[1] = 1'b1;
                    end else begin
                        int_select[0] = 1'b1;
                        int_port_bus1_sel[0] = 1'b1;
                    end
                end
                rv32im_types::FU_BRANCH: begin
                    if (branch_select[0]) begin
                        branch_select[1] = 1'b1;
                        branch_port_bus1_sel[1] = 1'b1;
                    end else begin
                        branch_select[0] = 1'b1;
                        branch_port_bus1_sel[0] = 1'b1;
                    end
                end
                rv32im_types::FU_MULDIV: begin
                    if (muldiv_select[0]) begin
                        muldiv_select[1] = 1'b1;
                        muldiv_port_bus1_sel[1] = 1'b1;
                    end else begin
                        muldiv_select[0] = 1'b1;
                        muldiv_port_bus1_sel[0] = 1'b1;
                    end
                end
                rv32im_types::FU_LOAD,
                rv32im_types::FU_STORE: begin
                    if (memory_select[0]) begin
                        memory_select[1] = 1'b1;
                        memory_port_bus1_sel[1] = 1'b1;
                    end else begin
                        memory_select[0] = 1'b1;
                        memory_port_bus1_sel[0] = 1'b1;
                    end
                end
                rv32im_types::FU_SYSTEM: begin
                    system_complete_data_1.valid = 1'b1;
                    if (dispatch_data_1.renamed.decoded.op == rv32im_types::OP_ECALL) begin
                        system_complete_data_1.exception_valid = 1'b1;
                        system_complete_data_1.exception_cause = rv32im_types::EXC_ECALL_MMODE;
                    end else if (dispatch_data_1.renamed.decoded.op == rv32im_types::OP_EBREAK) begin
                        system_complete_data_1.exception_valid = 1'b1;
                        system_complete_data_1.exception_cause = rv32im_types::EXC_BREAKPOINT;
                    end
                end
                default: begin
                    system_complete_data_1.valid = 1'b1;
                    system_complete_data_1.exception_valid = 1'b1;
                    system_complete_data_1.exception_cause =
                        rv32im_types::EXC_ILLEGAL;
                end
            endcase
        end
    end

endmodule : dispatch_router
