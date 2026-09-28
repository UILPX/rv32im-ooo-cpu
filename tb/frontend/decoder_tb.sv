module decoder_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    fetch_inst_t fetch;
    decoded_uop_t uop;
    decoded_uop_t rv32i_uop;

    decoder dut (.*);
    decoder #(
        .ENABLE_RV32M (1'b0)
    ) rv32i_dut (
        .fetch,
        .uop (rv32i_uop)
    );

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [31:0] r_type(
        input logic [6:0] funct7,
        input logic [2:0] funct3
    );
        r_type = {funct7, 5'd4, 5'd3, funct3, 5'd5, op_b_reg};
    endfunction

    function automatic logic [31:0] i_type(
        input logic [11:0] imm,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        i_type = {imm, 5'd3, funct3, 5'd5, opcode};
    endfunction

    function automatic logic [31:0] s_type(
        input logic [11:0] imm,
        input logic [2:0]  funct3
    );
        s_type = {imm[11:5], 5'd4, 5'd3, funct3, imm[4:0], op_b_store};
    endfunction

    function automatic logic [31:0] b_type(
        input logic [12:0] imm,
        input logic [2:0]  funct3
    );
        b_type = {imm[12], imm[10:5], 5'd4, 5'd3, funct3,
                  imm[4:1], imm[11], op_b_branch};
    endfunction

    function automatic logic [31:0] u_type(
        input logic [31:0] imm,
        input logic [6:0]  opcode
    );
        u_type = {imm[31:12], 5'd5, opcode};
    endfunction

    function automatic logic [31:0] j_type(input logic [20:0] imm);
        j_type = {imm[20], imm[10:1], imm[11], imm[19:12], 5'd5, op_b_jal};
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    task automatic check_decode(
        input logic [31:0] inst,
        input uop_t expected_op,
        input fu_class_t expected_fu,
        input logic expected_rs1,
        input logic expected_rs2,
        input logic expected_rd,
        input logic [31:0] expected_imm
    );
        fetch.inst = inst;
        #1ns;
        if ((uop.op !== expected_op) ||
            (uop.fu_class !== expected_fu) ||
            (uop.uses_rs1 !== expected_rs1) ||
            (uop.uses_rs2 !== expected_rs2) ||
            (uop.writes_rd !== expected_rd) ||
            (uop.imm !== expected_imm) || uop.illegal) begin
            $fatal(1, "decode mismatch inst=%08x op=%0d fu=%0d imm=%08x",
                   inst, uop.op, uop.fu_class, uop.imm);
        end
        if ((uop.rs1 !== inst[19:15]) || (uop.rs2 !== inst[24:20]) ||
            (uop.rd !== inst[11:7])) begin
            $fatal(1, "architectural register fields were not preserved");
        end
    endtask

    task automatic check_illegal(input logic [31:0] inst);
        fetch.inst = inst;
        #1ns;
        if (!uop.illegal || (uop.op != OP_INVALID) ||
            (uop.fu_class != FU_INVALID) || uop.uses_rs1 ||
            uop.uses_rs2 || uop.writes_rd) begin
            $fatal(1, "illegal encoding was accepted: %08x", inst);
        end
    endtask

    initial begin
        fetch = '0;
        fetch.pc = 32'h8000_0100;
        fetch.rvfi_order = 64'd19;
        fetch.pred_taken = 1'b1;
        fetch.pred_pc = 32'h8000_0200;

        check_decode(u_type(32'h1234_5000, op_b_lui), OP_LUI, FU_INT,
                     1'b0, 1'b0, 1'b1, 32'h1234_5000);
        if ((uop.fetch.pc != fetch.pc) ||
            (uop.fetch.rvfi_order != fetch.rvfi_order) ||
            !uop.fetch.pred_taken || (uop.fetch.pred_pc != fetch.pred_pc)) begin
            $fatal(1, "fetch metadata was not preserved by decode");
        end
        check_decode(u_type(32'habcde000, op_b_auipc), OP_AUIPC, FU_INT,
                     1'b0, 1'b0, 1'b1, 32'habcde000);

        check_decode(j_type(21'h1fff00), OP_JAL, FU_BRANCH,
                     1'b0, 1'b0, 1'b1, 32'hffff_ff00);
        if (!uop.bp_is_call || uop.bp_is_return) begin
            $fatal(1, "JAL link-register call hint was not decoded");
        end
        check_decode(i_type(12'hff0, 3'b000, op_b_jalr), OP_JALR, FU_BRANCH,
                     1'b1, 1'b0, 1'b1, 32'hffff_fff0);
        fetch.inst = i_type(12'd0, 3'b000, op_b_jalr);
        fetch.inst[19:15] = 5'd1;
        fetch.inst[11:7] = 5'd0;
        #1ns;
        if (!uop.bp_is_return || uop.bp_is_call) begin
            $fatal(1, "JALR return hint was not decoded");
        end

        check_decode(b_type(13'h1ff0, 3'b000), OP_BEQ,  FU_BRANCH, 1'b1, 1'b1, 1'b0, 32'hffff_fff0);
        check_decode(b_type(13'd16,   3'b001), OP_BNE,  FU_BRANCH, 1'b1, 1'b1, 1'b0, 32'd16);
        check_decode(b_type(13'd16,   3'b100), OP_BLT,  FU_BRANCH, 1'b1, 1'b1, 1'b0, 32'd16);
        check_decode(b_type(13'd16,   3'b101), OP_BGE,  FU_BRANCH, 1'b1, 1'b1, 1'b0, 32'd16);
        check_decode(b_type(13'd16,   3'b110), OP_BLTU, FU_BRANCH, 1'b1, 1'b1, 1'b0, 32'd16);
        check_decode(b_type(13'd16,   3'b111), OP_BGEU, FU_BRANCH, 1'b1, 1'b1, 1'b0, 32'd16);

        check_decode(i_type(12'hff0, 3'b000, op_b_load), OP_LB,  FU_LOAD, 1'b1, 1'b0, 1'b1, 32'hffff_fff0);
        check_decode(i_type(12'd12,  3'b001, op_b_load), OP_LH,  FU_LOAD, 1'b1, 1'b0, 1'b1, 32'd12);
        check_decode(i_type(12'd12,  3'b010, op_b_load), OP_LW,  FU_LOAD, 1'b1, 1'b0, 1'b1, 32'd12);
        check_decode(i_type(12'd12,  3'b100, op_b_load), OP_LBU, FU_LOAD, 1'b1, 1'b0, 1'b1, 32'd12);
        check_decode(i_type(12'd12,  3'b101, op_b_load), OP_LHU, FU_LOAD, 1'b1, 1'b0, 1'b1, 32'd12);
        check_decode(s_type(12'hff0, 3'b000), OP_SB, FU_STORE, 1'b1, 1'b1, 1'b0, 32'hffff_fff0);
        check_decode(s_type(12'd12,  3'b001), OP_SH, FU_STORE, 1'b1, 1'b1, 1'b0, 32'd12);
        check_decode(s_type(12'd12,  3'b010), OP_SW, FU_STORE, 1'b1, 1'b1, 1'b0, 32'd12);

        check_decode(i_type(12'hff0, 3'b000, op_b_imm), OP_ADDI,  FU_INT, 1'b1, 1'b0, 1'b1, 32'hffff_fff0);
        check_decode(i_type(12'hff0, 3'b010, op_b_imm), OP_SLTI,  FU_INT, 1'b1, 1'b0, 1'b1, 32'hffff_fff0);
        check_decode(i_type(12'hff0, 3'b011, op_b_imm), OP_SLTIU, FU_INT, 1'b1, 1'b0, 1'b1, 32'hffff_fff0);
        check_decode(i_type(12'hff0, 3'b100, op_b_imm), OP_XORI,  FU_INT, 1'b1, 1'b0, 1'b1, 32'hffff_fff0);
        check_decode(i_type(12'hff0, 3'b110, op_b_imm), OP_ORI,   FU_INT, 1'b1, 1'b0, 1'b1, 32'hffff_fff0);
        check_decode(i_type(12'hff0, 3'b111, op_b_imm), OP_ANDI,  FU_INT, 1'b1, 1'b0, 1'b1, 32'hffff_fff0);
        check_decode(i_type(12'h007, 3'b001, op_b_imm), OP_SLLI,  FU_INT, 1'b1, 1'b0, 1'b1, 32'd7);
        check_decode(i_type(12'h007, 3'b101, op_b_imm), OP_SRLI,  FU_INT, 1'b1, 1'b0, 1'b1, 32'd7);
        check_decode(i_type(12'h407, 3'b101, op_b_imm), OP_SRAI,  FU_INT, 1'b1, 1'b0, 1'b1, 32'h0000_0407);

        check_decode(r_type(7'b0000000, 3'b000), OP_ADD,  FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0100000, 3'b000), OP_SUB,  FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000000, 3'b001), OP_SLL,  FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000000, 3'b010), OP_SLT,  FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000000, 3'b011), OP_SLTU, FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000000, 3'b100), OP_XOR,  FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000000, 3'b101), OP_SRL,  FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0100000, 3'b101), OP_SRA,  FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000000, 3'b110), OP_OR,   FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000000, 3'b111), OP_AND,  FU_INT, 1'b1, 1'b1, 1'b1, 32'd0);

        check_decode(r_type(7'b0000001, 3'b000), OP_MUL,    FU_MULDIV, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000001, 3'b001), OP_MULH,   FU_MULDIV, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000001, 3'b010), OP_MULHSU, FU_MULDIV, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000001, 3'b011), OP_MULHU,  FU_MULDIV, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000001, 3'b100), OP_DIV,    FU_MULDIV, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000001, 3'b101), OP_DIVU,   FU_MULDIV, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000001, 3'b110), OP_REM,    FU_MULDIV, 1'b1, 1'b1, 1'b1, 32'd0);
        check_decode(r_type(7'b0000001, 3'b111), OP_REMU,   FU_MULDIV, 1'b1, 1'b1, 1'b1, 32'd0);
        if (!rv32i_uop.illegal || (rv32i_uop.op != OP_INVALID) ||
            (rv32i_uop.fu_class != FU_INVALID) || rv32i_uop.uses_rs1 ||
            rv32i_uop.uses_rs2 || rv32i_uop.writes_rd) begin
            $fatal(1, "RV32I-only decoder accepted an M-extension encoding");
        end

        check_decode(32'h0000_000f, OP_FENCE,  FU_SYSTEM, 1'b0, 1'b0, 1'b0, 32'd0);
        check_decode(32'h0000_0073, OP_ECALL,  FU_SYSTEM, 1'b0, 1'b0, 1'b0, 32'd0);
        check_decode(32'h0010_0073, OP_EBREAK, FU_SYSTEM, 1'b0, 1'b0, 1'b0, 32'd0);

        check_illegal(32'hffff_ffff);
        check_illegal(i_type(12'h207, 3'b001, op_b_imm));
        check_illegal(r_type(7'b0100000, 3'b001));
        check_illegal(i_type(12'd0, 3'b001, op_b_jalr));
        check_illegal(i_type(12'd0, 3'b011, op_b_load));
        check_illegal(s_type(12'd0, 3'b011));
        check_illegal(b_type(13'd0, 3'b010));
        check_illegal(32'h0000_1073);

        $display("decoder_tb: PASS");
        $finish;
    end

endmodule : decoder_tb
