module muldiv_exec #(
    parameter integer unsigned MUL_STAGES = 2,
    parameter integer unsigned DIV_CYC    = 11
) (
    input   logic                           clk,
    input   logic                           rst,
    input   logic                           flush,

    input   logic                           issue_valid,
    /* verilator lint_off UNUSEDSIGNAL */
    input   rv32im_types::res_stat_t        issue_data,
    /* verilator lint_on UNUSEDSIGNAL */
    output  logic                           issue_ready,

    output  rv32im_types::wb_bus_t          mul_wb_data,
    input   logic                           mul_result_grant,
    output  logic                           mul_result_valid,
    output  rv32im_types::rob_complete_t    mul_complete_data,

    output  rv32im_types::wb_bus_t          div_wb_data,
    input   logic                           div_result_grant,
    output  logic                           div_result_valid,
    output  rv32im_types::rob_complete_t    div_complete_data
);

    // One tag is needed for every multiply accepted by the pipelined unit.
    // The extra slot avoids coupling issue readiness to same-cycle writeback.
    localparam integer unsigned MUL_TAG_DEPTH =
        ((MUL_STAGES < 1) ? 1 : MUL_STAGES) + 1;
    localparam integer unsigned MUL_TAG_PTR_WIDTH =
        (MUL_TAG_DEPTH <= 1) ? 1 : $clog2(MUL_TAG_DEPTH);
    localparam integer unsigned MUL_TAG_COUNT_WIDTH =
        $clog2(MUL_TAG_DEPTH + 1);

    rv32im_types::simple_issue_t core_issue_data;
    rv32im_types::wb_bus_t core_mul_wb;
    rv32im_types::wb_bus_t core_div_wb;
    logic core_issue_valid;
    logic core_issue_ready;
    logic core_mul_wb_grant;
    logic core_div_wb_grant;
    logic issue_fire;
    logic mul_issue_fire;
    logic div_issue_fire;
    logic mul_result_fire;
    logic div_result_fire;
    logic metadata_ready;

    rv32im_types::rob_tag_t mul_tags_q [MUL_TAG_DEPTH];
    logic [MUL_TAG_PTR_WIDTH-1:0] mul_tag_head_q;
    logic [MUL_TAG_PTR_WIDTH-1:0] mul_tag_tail_q;
    logic [MUL_TAG_COUNT_WIDTH-1:0] mul_tag_count_q;
    logic div_tag_valid_q;
    rv32im_types::rob_tag_t div_tag_q;

    function automatic logic is_mul_op(input rv32im_types::uop_t op);
        is_mul_op = (op == rv32im_types::OP_MUL) ||
                    (op == rv32im_types::OP_MULH) ||
                    (op == rv32im_types::OP_MULHSU) ||
                    (op == rv32im_types::OP_MULHU);
    endfunction

    function automatic logic is_div_op(input rv32im_types::uop_t op);
        is_div_op = (op == rv32im_types::OP_DIV) ||
                    (op == rv32im_types::OP_DIVU) ||
                    (op == rv32im_types::OP_REM) ||
                    (op == rv32im_types::OP_REMU);
    endfunction

    function automatic logic [MUL_TAG_PTR_WIDTH-1:0] next_mul_tag_ptr(
        input logic [MUL_TAG_PTR_WIDTH-1:0] ptr
    );
        if (ptr == MUL_TAG_PTR_WIDTH'(MUL_TAG_DEPTH - 1)) begin
            next_mul_tag_ptr = '0;
        end else begin
            next_mul_tag_ptr = ptr + 1'b1;
        end
    endfunction

    always_comb begin
        core_issue_data = '0;
        core_issue_data.op = issue_data.op;
        core_issue_data.phy_rd = issue_data.phy_rd;
        core_issue_data.value_1 = issue_data.value_1;
        core_issue_data.value_2 = issue_data.value_2;

        mul_result_valid = !flush && core_mul_wb.valid &&
                           (mul_tag_count_q != '0);
        div_result_valid = !flush && core_div_wb.valid && div_tag_valid_q;
        mul_result_fire = mul_result_valid && mul_result_grant;
        div_result_fire = div_result_valid && div_result_grant;

        metadata_ready = 1'b0;
        if (is_mul_op(issue_data.op)) begin
            metadata_ready = mul_tag_count_q < MUL_TAG_COUNT_WIDTH'(MUL_TAG_DEPTH);
        end else if (is_div_op(issue_data.op)) begin
            metadata_ready = !div_tag_valid_q || div_result_fire;
        end

        core_issue_valid = issue_valid && metadata_ready;
        issue_ready = !flush && metadata_ready && core_issue_ready;
        issue_fire = issue_valid && issue_ready;
        mul_issue_fire = issue_fire && is_mul_op(issue_data.op);
        div_issue_fire = issue_fire && is_div_op(issue_data.op);

        core_mul_wb_grant = mul_result_fire;
        core_div_wb_grant = div_result_fire;

        mul_wb_data = core_mul_wb;
        mul_wb_data.valid = mul_result_valid && (core_mul_wb.phy_rd != '0);
        div_wb_data = core_div_wb;
        div_wb_data.valid = div_result_valid && (core_div_wb.phy_rd != '0);

        mul_complete_data = '0;
        mul_complete_data.valid = mul_result_fire;
        mul_complete_data.rob_tag = mul_tags_q[mul_tag_head_q];
        mul_complete_data.rd_write = mul_result_fire &&
                                     (core_mul_wb.phy_rd != '0);
        mul_complete_data.rd_value = core_mul_wb.value;

        div_complete_data = '0;
        div_complete_data.valid = div_result_fire;
        div_complete_data.rob_tag = div_tag_q;
        div_complete_data.rd_write = div_result_fire &&
                                     (core_div_wb.phy_rd != '0);
        div_complete_data.rd_value = core_div_wb.value;
    end

    muldiv #(
        .MUL_STAGES (MUL_STAGES),
        .DIV_CYC    (DIV_CYC)
    ) core (
        .clk,
        .rst,
        .flush,
        .issue_valid  (core_issue_valid),
        .issue_data   (core_issue_data),
        .issue_ready  (core_issue_ready),
        .mul_wb       (core_mul_wb),
        .mul_wb_grant (core_mul_wb_grant),
        .div_wb       (core_div_wb),
        .div_wb_grant (core_div_wb_grant)
    );

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            for (integer unsigned i = 0; i < MUL_TAG_DEPTH; i++) begin
                mul_tags_q[i] <= '0;
            end
            mul_tag_head_q <= '0;
            mul_tag_tail_q <= '0;
            mul_tag_count_q <= '0;
            div_tag_valid_q <= 1'b0;
            div_tag_q <= '0;
        end else begin
            unique case ({mul_issue_fire, mul_result_fire})
                2'b10: begin
                    mul_tags_q[mul_tag_tail_q] <= issue_data.rob_tag;
                    mul_tag_tail_q <= next_mul_tag_ptr(mul_tag_tail_q);
                    mul_tag_count_q <= mul_tag_count_q + 1'b1;
                end
                2'b01: begin
                    mul_tag_head_q <= next_mul_tag_ptr(mul_tag_head_q);
                    mul_tag_count_q <= mul_tag_count_q - 1'b1;
                end
                2'b11: begin
                    mul_tags_q[mul_tag_tail_q] <= issue_data.rob_tag;
                    mul_tag_tail_q <= next_mul_tag_ptr(mul_tag_tail_q);
                    mul_tag_head_q <= next_mul_tag_ptr(mul_tag_head_q);
                end
                default: begin
                end
            endcase

            if (div_result_fire) begin
                div_tag_valid_q <= 1'b0;
            end
            if (div_issue_fire) begin
                div_tag_valid_q <= 1'b1;
                div_tag_q <= issue_data.rob_tag;
            end
        end
    end

endmodule : muldiv_exec
