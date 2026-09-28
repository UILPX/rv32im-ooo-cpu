module decoder #(
    parameter bit ENABLE_RV32M = 1'b1
) (
    input   rv32im_types::fetch_inst_t  fetch,
    output  rv32im_types::decoded_uop_t uop
);

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    function automatic logic is_link_reg(input logic [4:0] reg_idx);
        is_link_reg = (reg_idx == 5'd1) || (reg_idx == 5'd5);
    endfunction

    always_comb begin
        opcode = fetch.inst[6:0];
        funct3 = fetch.inst[14:12];
        funct7 = fetch.inst[31:25];

        uop = '0;
        uop.fetch = fetch;
        uop.op = rv32im_types::OP_INVALID;
        uop.fu_class = rv32im_types::FU_INVALID;
        uop.rs1 = fetch.inst[19:15];
        uop.rs2 = fetch.inst[24:20];
        uop.rd = fetch.inst[11:7];
        uop.illegal = 1'b1;

        unique case (opcode)
            rv32im_types::op_b_lui: begin
                uop.op = rv32im_types::OP_LUI;
                uop.fu_class = rv32im_types::FU_INT;
                uop.imm = {fetch.inst[31:12], 12'b0};
                uop.writes_rd = 1'b1;
                uop.illegal = 1'b0;
            end

            rv32im_types::op_b_auipc: begin
                uop.op = rv32im_types::OP_AUIPC;
                uop.fu_class = rv32im_types::FU_INT;
                uop.imm = {fetch.inst[31:12], 12'b0};
                uop.writes_rd = 1'b1;
                uop.illegal = 1'b0;
            end

            rv32im_types::op_b_jal: begin
                uop.op = rv32im_types::OP_JAL;
                uop.fu_class = rv32im_types::FU_BRANCH;
                uop.imm = {{11{fetch.inst[31]}}, fetch.inst[31],
                           fetch.inst[19:12], fetch.inst[20],
                           fetch.inst[30:21], 1'b0};
                uop.writes_rd = 1'b1;
                uop.bp_is_call = is_link_reg(fetch.inst[11:7]);
                uop.illegal = 1'b0;
            end

            rv32im_types::op_b_jalr: begin
                if (funct3 == 3'b000) begin
                    uop.op = rv32im_types::OP_JALR;
                    uop.fu_class = rv32im_types::FU_BRANCH;
                    uop.imm = {{20{fetch.inst[31]}}, fetch.inst[31:20]};
                    uop.uses_rs1 = 1'b1;
                    uop.writes_rd = 1'b1;
                    uop.bp_is_call = is_link_reg(fetch.inst[11:7]);
                    uop.bp_is_return = is_link_reg(fetch.inst[19:15]) &&
                        (!is_link_reg(fetch.inst[11:7]) ||
                         (fetch.inst[11:7] != fetch.inst[19:15]));
                    uop.illegal = 1'b0;
                end
            end

            rv32im_types::op_b_branch: begin
                unique case (funct3)
                    3'b000: uop.op = rv32im_types::OP_BEQ;
                    3'b001: uop.op = rv32im_types::OP_BNE;
                    3'b100: uop.op = rv32im_types::OP_BLT;
                    3'b101: uop.op = rv32im_types::OP_BGE;
                    3'b110: uop.op = rv32im_types::OP_BLTU;
                    3'b111: uop.op = rv32im_types::OP_BGEU;
                    default: uop.op = rv32im_types::OP_INVALID;
                endcase
                if (uop.op != rv32im_types::OP_INVALID) begin
                    uop.fu_class = rv32im_types::FU_BRANCH;
                    uop.imm = {{19{fetch.inst[31]}}, fetch.inst[31],
                               fetch.inst[7], fetch.inst[30:25],
                               fetch.inst[11:8], 1'b0};
                    uop.uses_rs1 = 1'b1;
                    uop.uses_rs2 = 1'b1;
                    uop.illegal = 1'b0;
                end
            end

            rv32im_types::op_b_load: begin
                unique case (funct3)
                    3'b000: uop.op = rv32im_types::OP_LB;
                    3'b001: uop.op = rv32im_types::OP_LH;
                    3'b010: uop.op = rv32im_types::OP_LW;
                    3'b100: uop.op = rv32im_types::OP_LBU;
                    3'b101: uop.op = rv32im_types::OP_LHU;
                    default: uop.op = rv32im_types::OP_INVALID;
                endcase
                if (uop.op != rv32im_types::OP_INVALID) begin
                    uop.fu_class = rv32im_types::FU_LOAD;
                    uop.imm = {{20{fetch.inst[31]}}, fetch.inst[31:20]};
                    uop.uses_rs1 = 1'b1;
                    uop.writes_rd = 1'b1;
                    uop.illegal = 1'b0;
                end
            end

            rv32im_types::op_b_store: begin
                unique case (funct3)
                    3'b000: uop.op = rv32im_types::OP_SB;
                    3'b001: uop.op = rv32im_types::OP_SH;
                    3'b010: uop.op = rv32im_types::OP_SW;
                    default: uop.op = rv32im_types::OP_INVALID;
                endcase
                if (uop.op != rv32im_types::OP_INVALID) begin
                    uop.fu_class = rv32im_types::FU_STORE;
                    uop.imm = {{20{fetch.inst[31]}}, fetch.inst[31:25],
                               fetch.inst[11:7]};
                    uop.uses_rs1 = 1'b1;
                    uop.uses_rs2 = 1'b1;
                    uop.illegal = 1'b0;
                end
            end

            rv32im_types::op_b_imm: begin
                unique case (funct3)
                    3'b000: uop.op = rv32im_types::OP_ADDI;
                    3'b010: uop.op = rv32im_types::OP_SLTI;
                    3'b011: uop.op = rv32im_types::OP_SLTIU;
                    3'b100: uop.op = rv32im_types::OP_XORI;
                    3'b110: uop.op = rv32im_types::OP_ORI;
                    3'b111: uop.op = rv32im_types::OP_ANDI;
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            uop.op = rv32im_types::OP_SLLI;
                        end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            uop.op = rv32im_types::OP_SRLI;
                        end else if (funct7 == 7'b0100000) begin
                            uop.op = rv32im_types::OP_SRAI;
                        end
                    end
                    default: uop.op = rv32im_types::OP_INVALID;
                endcase
                if (uop.op != rv32im_types::OP_INVALID) begin
                    uop.fu_class = rv32im_types::FU_INT;
                    uop.imm = {{20{fetch.inst[31]}}, fetch.inst[31:20]};
                    uop.uses_rs1 = 1'b1;
                    uop.writes_rd = 1'b1;
                    uop.illegal = 1'b0;
                end
            end

            rv32im_types::op_b_reg: begin
                unique case (funct7)
                    7'b0000000: begin
                        unique case (funct3)
                            3'b000: uop.op = rv32im_types::OP_ADD;
                            3'b001: uop.op = rv32im_types::OP_SLL;
                            3'b010: uop.op = rv32im_types::OP_SLT;
                            3'b011: uop.op = rv32im_types::OP_SLTU;
                            3'b100: uop.op = rv32im_types::OP_XOR;
                            3'b101: uop.op = rv32im_types::OP_SRL;
                            3'b110: uop.op = rv32im_types::OP_OR;
                            3'b111: uop.op = rv32im_types::OP_AND;
                            default: uop.op = rv32im_types::OP_INVALID;
                        endcase
                        uop.fu_class = rv32im_types::FU_INT;
                    end
                    7'b0100000: begin
                        unique case (funct3)
                            3'b000: uop.op = rv32im_types::OP_SUB;
                            3'b101: uop.op = rv32im_types::OP_SRA;
                            default: uop.op = rv32im_types::OP_INVALID;
                        endcase
                        uop.fu_class = rv32im_types::FU_INT;
                    end
                    7'b0000001: begin
                        if (ENABLE_RV32M) begin
                            unique case (funct3)
                                3'b000: uop.op = rv32im_types::OP_MUL;
                                3'b001: uop.op = rv32im_types::OP_MULH;
                                3'b010: uop.op = rv32im_types::OP_MULHSU;
                                3'b011: uop.op = rv32im_types::OP_MULHU;
                                3'b100: uop.op = rv32im_types::OP_DIV;
                                3'b101: uop.op = rv32im_types::OP_DIVU;
                                3'b110: uop.op = rv32im_types::OP_REM;
                                3'b111: uop.op = rv32im_types::OP_REMU;
                                default: uop.op = rv32im_types::OP_INVALID;
                            endcase
                            uop.fu_class = rv32im_types::FU_MULDIV;
                        end
                    end
                    default: begin
                        uop.op = rv32im_types::OP_INVALID;
                        uop.fu_class = rv32im_types::FU_INVALID;
                    end
                endcase
                if (uop.op != rv32im_types::OP_INVALID) begin
                    uop.uses_rs1 = 1'b1;
                    uop.uses_rs2 = 1'b1;
                    uop.writes_rd = 1'b1;
                    uop.illegal = 1'b0;
                end else begin
                    uop.fu_class = rv32im_types::FU_INVALID;
                end
            end

            rv32im_types::op_b_fence: begin
                if (funct3 == 3'b000) begin
                    uop.op = rv32im_types::OP_FENCE;
                    uop.fu_class = rv32im_types::FU_SYSTEM;
                    uop.illegal = 1'b0;
                end
            end

            rv32im_types::op_b_system: begin
                if (fetch.inst == 32'h0000_0073) begin
                    uop.op = rv32im_types::OP_ECALL;
                    uop.fu_class = rv32im_types::FU_SYSTEM;
                    uop.illegal = 1'b0;
                end else if (fetch.inst == 32'h0010_0073) begin
                    uop.op = rv32im_types::OP_EBREAK;
                    uop.fu_class = rv32im_types::FU_SYSTEM;
                    uop.illegal = 1'b0;
                end
            end

            default: begin
                uop.op = rv32im_types::OP_INVALID;
                uop.fu_class = rv32im_types::FU_INVALID;
            end
        endcase
    end

endmodule : decoder
