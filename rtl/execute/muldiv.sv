/*
这个模块是 CP2 使用的 mul/div 执行单元，后面通过 bus_controller 写回。

设计思路：
1. 前端接口和普通 ALU 保持一致，直接吃 RS 给出的 issue_valid / issue_data。
2. 乘法和除法各自维护一个写回 buffer，后面由 bus_controller 决定这拍是否接收。
3. mul 使用可调流水线的 mul_pipe，div 使用可调周期的 div_iterative。
4. mul 和 div 可以并行在飞，因此后面分别输出 mul_wb / div_wb。
5. 如果写回 buffer 还没被 bus_controller 取走，对应单元就不再接受新的同类指令。

接口语义：
1. issue_valid + issue_data：来自 mul/div RS 的一条候选指令。
2. issue_ready：当前 muldiv 单元能不能接收这条候选指令。
3. mul_wb / div_wb：当前准备写回的乘法结果和除法结果。
4. mul_wb_grant / div_wb_grant：bus_controller 这一拍是否真的取走了对应结果。

当前支持的运算：
1. OP_MUL / OP_MULH / OP_MULHSU / OP_MULHU
2. OP_DIV / OP_DIVU / OP_REM / OP_REMU

实现假设：
1. issue_data.op 使用 rv32im_types::uop_t 的 RV32M 编码。
2. RS 只有在两个源操作数都 ready 时才会把指令送到这里。
3. flush 到来时，乘除法内部状态和待写回结果都直接丢弃。
*/
module muldiv #(
    parameter integer unsigned MUL_STAGES = 2,
    parameter integer unsigned DIV_CYC    = 11
) (
    input   logic       clk,
    input   logic       rst,
    input   logic       flush,

    input   logic           issue_valid,
    input   rv32im_types::simple_issue_t issue_data,
    output  logic           issue_ready,

    output  rv32im_types::wb_bus_t mul_wb,
    input   logic       mul_wb_grant,

    output  rv32im_types::wb_bus_t div_wb,
    input   logic       div_wb_grant
);

    localparam integer unsigned MUL_LATENCY = (MUL_STAGES > 0) ? MUL_STAGES - 1 : 0;

    typedef struct packed {
        rv32im_types::uop_t     op;
        rv32im_types::phys_reg_t phy_rd;
        logic                       neg;
    } mul_meta_t;

    typedef struct packed {
        logic                       valid;
        rv32im_types::uop_t      op;
        rv32im_types::phys_reg_t phy_rd;
        logic                       neg_q;
        logic                       neg_r;
    } div_meta_t;

    mul_meta_t  mul_meta_out;
    div_meta_t  div_meta_q;

    rv32im_types::wb_bus_t mul_wb_q, div_wb_q;

    logic           div_issue_fire;
    logic           mul_issue_ready_int;
    logic           div_issue_ready_int;

    logic           mul_done;
    logic           mul_buffer_can_take;
    logic           mul_ip_output_valid;
    logic   [63:0]  mul_product_raw;
    logic   [63:0]  mul_product_fixed;
    logic   [31:0]  mul_a_mag;
    logic   [31:0]  mul_b_mag;
    logic           mul_signed_a;
    logic           mul_signed_b;
    logic           mul_neg;

    logic           div_start;
    logic           div_buffer_can_take;
    logic           div_finish;
    logic           div_ip_input_ready;
    logic           div_ip_output_valid;
    logic           div_is_signed;
    logic           div_special_zero;
    logic           div_special_overflow;
    logic   [31:0]  div_a_mag;
    logic   [31:0]  div_b_mag;
    logic           div_neg_q;
    logic           div_neg_r;
    logic           div_ip_divide_by_zero;
    logic   [31:0]  div_quotient_u;
    logic   [31:0]  div_remainder_u;

    function automatic logic is_mul_op(input rv32im_types::uop_t op);
        is_mul_op = (op == rv32im_types::OP_MUL)  ||
                    (op == rv32im_types::OP_MULH) ||
                    (op == rv32im_types::OP_MULHSU) ||
                    (op == rv32im_types::OP_MULHU);
    endfunction

    function automatic logic is_div_op(input rv32im_types::uop_t op);
        is_div_op = (op == rv32im_types::OP_DIV)  ||
                    (op == rv32im_types::OP_DIVU) ||
                    (op == rv32im_types::OP_REM)  ||
                    (op == rv32im_types::OP_REMU);
    endfunction

    function automatic logic [31:0] abs32(input logic [31:0] x);
        if (x[31]) begin
            abs32 = ~x + 32'd1;
        end else begin
            abs32 = x;
        end
    endfunction

    function automatic logic [31:0] neg32(input logic [31:0] x);
        neg32 = ~x + 32'd1;
    endfunction

    function automatic logic [63:0] neg64(input logic [63:0] x);
        neg64 = ~x + 64'd1;
    endfunction

    function automatic logic [31:0] mul_result_select(
        input rv32im_types::uop_t op,
        input logic [63:0] product
    );
        unique case (op)
            rv32im_types::OP_MUL:    mul_result_select = product[31:0];
            rv32im_types::OP_MULH:   mul_result_select = product[63:32];
            rv32im_types::OP_MULHSU: mul_result_select = product[63:32];
            rv32im_types::OP_MULHU:  mul_result_select = product[63:32];
            default:                 mul_result_select = 32'd0;
        endcase
    endfunction

    function automatic rv32im_types::wb_bus_t make_wb(
        input rv32im_types::phys_reg_t phy_rd,
        input logic [31:0]             value
    );
        rv32im_types::wb_bus_t tmp;
        tmp = '0;
        tmp.valid = 1'b1;
        tmp.phy_rd = phy_rd;
        tmp.value = value;
        make_wb = tmp;
    endfunction

    function automatic logic [31:0] div_special_result(
        input rv32im_types::uop_t op,
        input logic [31:0] a
    );
        unique case (op)
            rv32im_types::OP_DIV,
            rv32im_types::OP_DIVU: div_special_result = 32'hffff_ffff;

            rv32im_types::OP_REM,
            rv32im_types::OP_REMU: div_special_result = a;

            default: div_special_result = 32'd0;
        endcase
    endfunction

    function automatic logic [31:0] div_overflow_result(
        input rv32im_types::uop_t op
    );
        unique case (op)
            rv32im_types::OP_DIV: div_overflow_result = 32'h8000_0000;
            rv32im_types::OP_REM: div_overflow_result = 32'd0;
            default:              div_overflow_result = 32'd0;
        endcase
    endfunction

    assign mul_signed_a = (issue_data.op == rv32im_types::OP_MUL) ||
                          (issue_data.op == rv32im_types::OP_MULH) ||
                          (issue_data.op == rv32im_types::OP_MULHSU);
    assign mul_signed_b = (issue_data.op == rv32im_types::OP_MUL) ||
                          (issue_data.op == rv32im_types::OP_MULH);
    assign mul_a_mag = (mul_signed_a && issue_data.value_1[31]) ? abs32(issue_data.value_1) : issue_data.value_1;
    assign mul_b_mag = (mul_signed_b && issue_data.value_2[31]) ? abs32(issue_data.value_2) : issue_data.value_2;
    assign mul_neg   = (mul_signed_a && issue_data.value_1[31]) ^
                       (mul_signed_b && issue_data.value_2[31]);

    assign mul_buffer_can_take = !mul_wb_q.valid || mul_wb_grant;
    assign mul_done = mul_ip_output_valid;
    assign mul_product_fixed = mul_meta_out.neg ? neg64(mul_product_raw) : mul_product_raw;

    assign div_is_signed = (issue_data.op == rv32im_types::OP_DIV) ||
                           (issue_data.op == rv32im_types::OP_REM);
    assign div_special_zero = (issue_data.value_2 == 32'd0);
    assign div_special_overflow = div_is_signed &&
                                  (issue_data.value_1 == 32'h8000_0000) &&
                                  (issue_data.value_2 == 32'hffff_ffff);
    assign div_a_mag = (div_is_signed && issue_data.value_1[31]) ? abs32(issue_data.value_1) : issue_data.value_1;
    assign div_b_mag = (div_is_signed && issue_data.value_2[31]) ? abs32(issue_data.value_2) : issue_data.value_2;
    assign div_neg_q = div_is_signed && (issue_data.value_1[31] ^ issue_data.value_2[31]);
    assign div_neg_r = div_is_signed && issue_data.value_1[31];

    assign div_buffer_can_take = !div_wb_q.valid || div_wb_grant;
    assign div_finish = div_ip_output_valid && div_buffer_can_take;

    always_comb begin
        issue_ready = 1'b0;

        if (!flush) begin
            if (is_mul_op(issue_data.op)) begin
                issue_ready = mul_issue_ready_int;
            end else if (is_div_op(issue_data.op)) begin
                issue_ready = div_issue_ready_int;
            end
        end
    end

    assign div_issue_fire = issue_valid && issue_ready && is_div_op(issue_data.op);
    assign div_issue_ready_int = div_buffer_can_take && div_ip_input_ready;

    assign div_start = div_issue_fire && !div_special_zero && !div_special_overflow;

    // 乘法器这里用 unsigned 模式，把 mixed-sign / signed 的差异都放到 wrapper 里修正。
    mul_pipe #(
        .WIDTH      (32),
        .NUM_STAGES (MUL_STAGES)
    ) u_mul (
        .clk            (clk),
        .rst            (rst),
        .flush          (flush),
        .input_valid    (issue_valid && is_mul_op(issue_data.op)),
        .input_ready    (mul_issue_ready_int),
        .input_a        (mul_a_mag),
        .input_b        (mul_b_mag),
        .output_valid   (mul_ip_output_valid),
        .output_ready   (mul_buffer_can_take),
        .output_product (mul_product_raw)
    );

    // 除法器固定用 unsigned 模式，signed 的输入输出都在 wrapper 里处理。
    div_iterative #(
        .WIDTH   (32),
        .DIV_CYC (DIV_CYC)
    ) u_div (
        .clk                   (clk),
        .rst                   (rst),
        .flush                 (flush),
        .input_valid           (div_start),
        .input_ready           (div_ip_input_ready),
        .input_dividend        (div_a_mag),
        .input_divisor         (div_b_mag),
        .output_valid          (div_ip_output_valid),
        .output_ready          (div_buffer_can_take),
        .output_quotient       (div_quotient_u),
        .output_remainder      (div_remainder_u),
        .output_divide_by_zero (div_ip_divide_by_zero)
    );

    generate
        if (MUL_LATENCY == 0) begin : gen_mul_meta_combinational
            always_comb begin
                mul_meta_out.op     = issue_data.op;
                mul_meta_out.phy_rd = issue_data.phy_rd;
                mul_meta_out.neg    = mul_neg;
            end
        end else begin : gen_mul_meta_pipeline
            rv32im_types::uop_t mul_op_q [MUL_LATENCY];
            rv32im_types::phys_reg_t mul_phy_rd_q [MUL_LATENCY];
            logic mul_neg_q [MUL_LATENCY];

            always_comb begin
                mul_meta_out.op = mul_op_q[MUL_LATENCY-1];
                mul_meta_out.phy_rd = mul_phy_rd_q[MUL_LATENCY-1];
                mul_meta_out.neg = mul_neg_q[MUL_LATENCY-1];
            end

            always_ff @(posedge clk) begin
                integer unsigned i;

                if (rst || flush) begin
                    for (i = 0; i < MUL_LATENCY; i = i + 1) begin
                        mul_op_q[i] <= rv32im_types::OP_INVALID;
                        mul_phy_rd_q[i] <= '0;
                        mul_neg_q[i] <= 1'b0;
                    end
                end else if (mul_issue_ready_int) begin
                    for (i = MUL_LATENCY-1; i > 0; i = i - 1) begin
                        mul_op_q[i] <= mul_op_q[i-1];
                        mul_phy_rd_q[i] <= mul_phy_rd_q[i-1];
                        mul_neg_q[i] <= mul_neg_q[i-1];
                    end

                    mul_op_q[0] <= issue_data.op;
                    mul_phy_rd_q[0] <= issue_data.phy_rd;
                    mul_neg_q[0] <= mul_neg;
                end
            end
        end
    endgenerate

    assign mul_wb = mul_wb_q;
    assign div_wb = div_wb_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            mul_wb_q <= '0;
            div_wb_q <= '0;
            div_meta_q <= '0;
        end else begin
            // 先处理写回 buffer；flush 时直接把当前准备写回的结果丢掉。
            if (flush) begin
                mul_wb_q <= '0;
                div_wb_q <= '0;
            end else begin
                if (mul_wb_q.valid && mul_wb_grant) begin
                    mul_wb_q <= '0;
                end
                if (div_wb_q.valid && div_wb_grant) begin
                    div_wb_q <= '0;
                end

                if (mul_done && mul_buffer_can_take) begin
                    mul_wb_q <= make_wb(
                        mul_meta_out.phy_rd,
                        mul_result_select(mul_meta_out.op, mul_product_fixed)
                    );
                end

                if (div_issue_fire && div_special_zero) begin
                    div_wb_q <= make_wb(
                        issue_data.phy_rd,
                        div_special_result(issue_data.op, issue_data.value_1)
                    );
                end else if (div_issue_fire && div_special_overflow) begin
                    div_wb_q <= make_wb(
                        issue_data.phy_rd,
                        div_overflow_result(issue_data.op)
                    );
                end else if (div_finish && div_meta_q.valid && !div_ip_divide_by_zero) begin
                    if ((div_meta_q.op == rv32im_types::OP_DIV) ||
                        (div_meta_q.op == rv32im_types::OP_DIVU)) begin
                        div_wb_q <= make_wb(
                            div_meta_q.phy_rd,
                            div_meta_q.neg_q ? neg32(div_quotient_u) : div_quotient_u
                        );
                    end else begin
                        div_wb_q <= make_wb(
                            div_meta_q.phy_rd,
                            div_meta_q.neg_r ? neg32(div_remainder_u) : div_remainder_u
                        );
                    end
                end
            end

            if (flush) begin
                div_meta_q <= '0;
            end else begin
                if (div_issue_fire && !div_special_zero && !div_special_overflow) begin
                    div_meta_q.valid  <= 1'b1;
                    div_meta_q.op     <= issue_data.op;
                    div_meta_q.phy_rd <= issue_data.phy_rd;
                    div_meta_q.neg_q  <= div_neg_q;
                    div_meta_q.neg_r  <= div_neg_r;
                end else if (div_finish) begin
                    div_meta_q <= '0;
                end
            end
        end
    end

endmodule : muldiv
