module br_pred #(
    parameter integer unsigned PHT_ENTRIES = 128,
    parameter integer unsigned RAS_ENTRIES = 32
) (
    input   logic           clk,
    input   logic           rst,

    input   logic           predecode_valid_0,
    input   logic           predecode_valid_1,
    input   logic   [31:0]  predecode_inst_0,
    input   logic   [31:0]  predecode_inst_1,
    input   logic           predecode_flush,
    input   logic   [31:0]  pc_0,
    input   logic   [31:0]  pc_1,

    input   logic           update_valid,
    input   logic   [31:0]  update_pc,
    input   logic           update_is_cond_branch,
    input   logic           update_is_jalr,
    input   logic           update_is_call,
    input   logic           update_is_return,
    input   logic           update_taken,
    input   logic   [31:0]  update_target,

    output  logic   [1:0]   taken,
    output  logic   [31:0]  jump_pc_0,
    output  logic   [31:0]  jump_pc_1
);

    localparam integer unsigned PHT_IDX_BITS =
        (PHT_ENTRIES <= 1) ? 1 : $clog2(PHT_ENTRIES);
    localparam integer unsigned RAS_PTR_BITS =
        (RAS_ENTRIES <= 1) ? 1 : $clog2(RAS_ENTRIES);

    logic [1:0]              pht_q [PHT_ENTRIES];
    logic [PHT_IDX_BITS-1:0] ghr_q;
    logic [31:0]             ras_stack_q [RAS_ENTRIES];
    logic [RAS_PTR_BITS-1:0] ras_sp_q;
    logic [RAS_PTR_BITS:0]   ras_count_q;

    logic                    pending_auipc_valid_q;
    logic [31:0]             pending_auipc_pc_q;
    logic [31:0]             pending_auipc_inst_q;

    logic [PHT_IDX_BITS-1:0] pred_idx_0;
    logic [PHT_IDX_BITS-1:0] pred_idx_1;
    logic [PHT_IDX_BITS-1:0] update_idx;
    logic [RAS_PTR_BITS-1:0] ras_top_idx;
    logic [31:0]             ras_top_pc;

    logic                    is_cond_0;
    logic                    is_cond_1;
    logic                    is_jal_0;
    logic                    is_jal_1;
    logic                    is_jalr_0;
    logic                    is_jalr_1;
    logic                    is_return_0;
    logic                    is_return_1;
    logic                    is_auipc_jalr_0;
    logic                    is_auipc_jalr_1;
    logic                    target_valid_0;
    logic                    target_valid_1;
    logic [31:0]             target_pc_0;
    logic [31:0]             target_pc_1;
    logic [31:0]             auipc_jalr_target_0;
    logic [31:0]             auipc_jalr_target_1;
    logic                    _unused_update_inputs;

    generate
        if ((PHT_ENTRIES < 2) ||
            ((PHT_ENTRIES & (PHT_ENTRIES - 1)) != 0) ||
            (RAS_ENTRIES < 2) ||
            ((RAS_ENTRIES & (RAS_ENTRIES - 1)) != 0)) begin : gen_invalid_parameters
            initial begin
                $error("br_pred requires power-of-two PHT_ENTRIES and RAS_ENTRIES >= 2");
            end
        end
    endgenerate

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [PHT_IDX_BITS-1:0] gshare_index(
        input logic [31:0]             pc,
        input logic [PHT_IDX_BITS-1:0] history
    );
        gshare_index = pc[PHT_IDX_BITS+1:2] ^ history;
    endfunction

    function automatic logic [31:0] branch_imm(input logic [31:0] inst);
        branch_imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    endfunction

    function automatic logic [31:0] jal_imm(input logic [31:0] inst);
        jal_imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
    endfunction

    function automatic logic [31:0] auipc_imm(input logic [31:0] inst);
        auipc_imm = {inst[31:12], 12'b0};
    endfunction

    function automatic logic [31:0] jalr_imm(input logic [31:0] inst);
        jalr_imm = {{20{inst[31]}}, inst[31:20]};
    endfunction

    function automatic logic is_link_reg(input logic [4:0] reg_idx);
        is_link_reg = (reg_idx == 5'd1) || (reg_idx == 5'd5);
    endfunction

    function automatic logic is_return(input logic [31:0] inst);
        is_return = (inst[6:0] == 7'b1100111)
                 && is_link_reg(inst[19:15])
                 && (!is_link_reg(inst[11:7]) || (inst[11:7] != inst[19:15]));
    endfunction

    function automatic logic is_link_auipc(input logic [31:0] inst);
        is_link_auipc = (inst[6:0] == 7'b0010111) && is_link_reg(inst[11:7]);
    endfunction

    function automatic logic is_auipc_jalr_call(
        input logic [31:0] auipc_inst,
        input logic [31:0] jalr_inst
    );
        is_auipc_jalr_call =
            (auipc_inst[6:0] == 7'b0010111) &&
            (jalr_inst[6:0] == 7'b1100111) &&
            is_link_reg(auipc_inst[11:7]) &&
            is_link_reg(jalr_inst[11:7]) &&
            (jalr_inst[19:15] == auipc_inst[11:7]);
    endfunction

    function automatic logic [31:0] auipc_jalr_target(
        input logic [31:0] auipc_pc,
        input logic [31:0] auipc_inst,
        input logic [31:0] jalr_inst
    );
        auipc_jalr_target =
            (auipc_pc + auipc_imm(auipc_inst) + jalr_imm(jalr_inst)) & 32'hffff_fffe;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [1:0] update_counter(
        input logic [1:0] counter,
        input logic       actual_taken
    );
        if (actual_taken && (counter != 2'b11)) begin
            update_counter = counter + 2'b01;
        end else if (!actual_taken && (counter != 2'b00)) begin
            update_counter = counter - 2'b01;
        end else begin
            update_counter = counter;
        end
    endfunction

    assign pred_idx_0 = gshare_index(pc_0, ghr_q);
    assign pred_idx_1 = gshare_index(pc_1, ghr_q);
    assign update_idx = gshare_index(update_pc, ghr_q);

    assign ras_top_idx = (ras_sp_q == '0)
                       ? RAS_PTR_BITS'(RAS_ENTRIES - 1)
                       : (ras_sp_q - RAS_PTR_BITS'(1));
    assign ras_top_pc = ras_stack_q[ras_top_idx];

    assign is_cond_0 = predecode_valid_0 && (predecode_inst_0[6:0] == 7'b1100011);
    assign is_cond_1 = predecode_valid_1 && (predecode_inst_1[6:0] == 7'b1100011);
    assign is_jal_0 = predecode_valid_0 && (predecode_inst_0[6:0] == 7'b1101111);
    assign is_jal_1 = predecode_valid_1 && (predecode_inst_1[6:0] == 7'b1101111);
    assign is_jalr_0 = predecode_valid_0 && (predecode_inst_0[6:0] == 7'b1100111);
    assign is_jalr_1 = predecode_valid_1 && (predecode_inst_1[6:0] == 7'b1100111);
    assign is_return_0 = is_jalr_0 && is_return(predecode_inst_0);
    assign is_return_1 = is_jalr_1 && is_return(predecode_inst_1);

    assign is_auipc_jalr_0 = is_jalr_0 && pending_auipc_valid_q
                           && (pc_0 == (pending_auipc_pc_q + 32'd4))
                           && is_auipc_jalr_call(pending_auipc_inst_q, predecode_inst_0);
    assign auipc_jalr_target_0 = auipc_jalr_target(
        pending_auipc_pc_q, pending_auipc_inst_q, predecode_inst_0);

    assign is_auipc_jalr_1 = is_jalr_1 &&
        ((predecode_valid_0 && (pc_1 == (pc_0 + 32'd4)) &&
          is_auipc_jalr_call(predecode_inst_0, predecode_inst_1)) ||
         (pending_auipc_valid_q && (pc_1 == (pending_auipc_pc_q + 32'd4)) &&
          is_auipc_jalr_call(pending_auipc_inst_q, predecode_inst_1)));
    assign auipc_jalr_target_1 =
        (predecode_valid_0 && (pc_1 == (pc_0 + 32'd4)) &&
         is_auipc_jalr_call(predecode_inst_0, predecode_inst_1))
            ? auipc_jalr_target(pc_0, predecode_inst_0, predecode_inst_1)
            : auipc_jalr_target(pending_auipc_pc_q,
                                pending_auipc_inst_q,
                                predecode_inst_1);

    assign _unused_update_inputs = &{1'b0, update_is_jalr, update_target};

    always_comb begin
        target_valid_0 = 1'b0;
        target_valid_1 = 1'b0;
        target_pc_0 = '0;
        target_pc_1 = '0;

        if (is_cond_0) begin
            target_valid_0 = 1'b1;
            target_pc_0 = pc_0 + branch_imm(predecode_inst_0);
        end else if (is_jal_0) begin
            target_valid_0 = 1'b1;
            target_pc_0 = pc_0 + jal_imm(predecode_inst_0);
        end else if (is_auipc_jalr_0) begin
            target_valid_0 = 1'b1;
            target_pc_0 = auipc_jalr_target_0;
        end

        if (is_cond_1) begin
            target_valid_1 = 1'b1;
            target_pc_1 = pc_1 + branch_imm(predecode_inst_1);
        end else if (is_jal_1) begin
            target_valid_1 = 1'b1;
            target_pc_1 = pc_1 + jal_imm(predecode_inst_1);
        end else if (is_auipc_jalr_1) begin
            target_valid_1 = 1'b1;
            target_pc_1 = auipc_jalr_target_1;
        end
    end

    always_comb begin
        taken = 2'b00;
        jump_pc_0 = '0;
        jump_pc_1 = '0;

        if (is_return_0 && (ras_count_q != '0)) begin
            taken[0] = 1'b1;
            jump_pc_0 = ras_top_pc;
        end else if (target_valid_0) begin
            taken[0] = is_cond_0 ? pht_q[pred_idx_0][1] : 1'b1;
            jump_pc_0 = target_pc_0;
        end

        if (is_return_1 && (ras_count_q != '0)) begin
            taken[1] = 1'b1;
            jump_pc_1 = ras_top_pc;
        end else if (target_valid_1) begin
            taken[1] = is_cond_1 ? pht_q[pred_idx_1][1] : 1'b1;
            jump_pc_1 = target_pc_1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            ghr_q <= '0;
            ras_sp_q <= '0;
            ras_count_q <= '0;
            pending_auipc_valid_q <= 1'b0;
            pending_auipc_pc_q <= '0;
            pending_auipc_inst_q <= '0;

            for (integer unsigned i = 0; i < PHT_ENTRIES; i = i + 1) begin
                pht_q[i] <= 2'b10;
            end

            for (integer unsigned i = 0; i < RAS_ENTRIES; i = i + 1) begin
                ras_stack_q[i] <= '0;
            end
        end else begin
            if (predecode_flush) begin
                pending_auipc_valid_q <= 1'b0;
            end else begin
                pending_auipc_valid_q <= 1'b0;

                if (predecode_valid_0 && is_link_auipc(predecode_inst_0)) begin
                    pending_auipc_valid_q <= 1'b1;
                    pending_auipc_pc_q <= pc_0;
                    pending_auipc_inst_q <= predecode_inst_0;
                end

                if (predecode_valid_1 && is_link_auipc(predecode_inst_1)) begin
                    pending_auipc_valid_q <= 1'b1;
                    pending_auipc_pc_q <= pc_1;
                    pending_auipc_inst_q <= predecode_inst_1;
                end
            end

            if (update_valid) begin
                if (update_is_return && update_is_call) begin
                    if (ras_count_q == '0) begin
                        ras_stack_q[ras_sp_q] <= update_pc + 32'd4;
                        ras_sp_q <= (ras_sp_q == RAS_PTR_BITS'(RAS_ENTRIES - 1))
                                  ? '0 : (ras_sp_q + RAS_PTR_BITS'(1));
                        ras_count_q <= (RAS_PTR_BITS+1)'(1);
                    end else begin
                        ras_stack_q[ras_top_idx] <= update_pc + 32'd4;
                    end
                end else if (update_is_return && (ras_count_q != '0)) begin
                    ras_sp_q <= ras_top_idx;
                    ras_count_q <= ras_count_q - (RAS_PTR_BITS+1)'(1);
                end else if (update_is_call) begin
                    ras_stack_q[ras_sp_q] <= update_pc + 32'd4;
                    ras_sp_q <= (ras_sp_q == RAS_PTR_BITS'(RAS_ENTRIES - 1))
                              ? '0 : (ras_sp_q + RAS_PTR_BITS'(1));
                    if (ras_count_q != (RAS_PTR_BITS+1)'(RAS_ENTRIES)) begin
                        ras_count_q <= ras_count_q + (RAS_PTR_BITS+1)'(1);
                    end
                end

                if (update_is_cond_branch) begin
                    pht_q[update_idx] <= update_counter(pht_q[update_idx], update_taken);
                    ghr_q <= (ghr_q << 1) | PHT_IDX_BITS'(update_taken);
                end
            end
        end
    end

endmodule : br_pred
