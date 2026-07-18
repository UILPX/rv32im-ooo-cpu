module div_iterative #(
    parameter integer unsigned WIDTH   = 32,
    parameter integer unsigned DIV_CYC = 32
) (
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   flush,

    input   logic                   input_valid,
    output  logic                   input_ready,
    input   logic   [WIDTH-1:0]     input_dividend,
    input   logic   [WIDTH-1:0]     input_divisor,

    output  logic                   output_valid,
    input   logic                   output_ready,
    output  logic   [WIDTH-1:0]     output_quotient,
    output  logic   [WIDTH-1:0]     output_remainder,
    output  logic                   output_divide_by_zero
);

    localparam integer unsigned SAFE_DIV_CYC = (DIV_CYC == 0) ? 1 : DIV_CYC;
    localparam integer unsigned BASE_STEPS   = WIDTH / SAFE_DIV_CYC;
    localparam integer unsigned EXTRA_STEPS  = WIDTH % SAFE_DIV_CYC;
    localparam integer unsigned MAX_STEPS    = (WIDTH + SAFE_DIV_CYC - 1) / SAFE_DIV_CYC;
    localparam integer unsigned CYCLE_BITS   = (SAFE_DIV_CYC <= 1) ? 1 : $clog2(SAFE_DIV_CYC);

    logic                   busy_q;
    logic [CYCLE_BITS-1:0]  cycle_q;
    logic [WIDTH-1:0]       divisor_q;
    logic [WIDTH-1:0]       dividend_shift_q;
    logic [WIDTH-1:0]       quotient_q;
    logic [WIDTH:0]         remainder_q;

    logic                   result_valid_q;
    logic [WIDTH-1:0]       result_quotient_q;
    logic [WIDTH-1:0]       result_remainder_q;
    logic                   result_divide_by_zero_q;

    logic [WIDTH-1:0]       dividend_shift_next;
    logic [WIDTH-1:0]       quotient_next;
    logic [WIDTH:0]         remainder_next;
    logic [WIDTH:0]         shifted_remainder;
    integer unsigned        steps_this_cycle;

    generate
        if ((WIDTH < 2) || (DIV_CYC == 0) || (DIV_CYC > WIDTH)) begin : gen_invalid_parameters
            initial begin
                $error("div_iterative requires WIDTH >= 2 and 1 <= DIV_CYC <= WIDTH");
            end
        end

        if (EXTRA_STEPS == 0) begin : gen_even_cycle_steps
            always_comb begin
                steps_this_cycle = BASE_STEPS;
            end
        end else begin : gen_uneven_cycle_steps
            always_comb begin
                steps_this_cycle = BASE_STEPS;
                if (cycle_q < CYCLE_BITS'(EXTRA_STEPS)) begin
                    steps_this_cycle = BASE_STEPS + 1;
                end
            end
        end
    endgenerate

    assign input_ready                 = !busy_q && !result_valid_q && !flush;
    assign output_valid                = result_valid_q && !flush;
    assign output_quotient             = result_quotient_q;
    assign output_remainder            = result_remainder_q;
    assign output_divide_by_zero       = result_divide_by_zero_q;

    always_comb begin
        dividend_shift_next = dividend_shift_q;
        quotient_next       = quotient_q;
        remainder_next      = remainder_q;
        shifted_remainder   = '0;

        for (integer unsigned i = 0; i < MAX_STEPS; i = i + 1) begin
            if (i < steps_this_cycle) begin
                shifted_remainder = {
                    remainder_next[WIDTH-1:0],
                    dividend_shift_next[WIDTH-1]
                };
                dividend_shift_next = {dividend_shift_next[WIDTH-2:0], 1'b0};

                if (shifted_remainder >= {1'b0, divisor_q}) begin
                    remainder_next = shifted_remainder - {1'b0, divisor_q};
                    quotient_next = {quotient_next[WIDTH-2:0], 1'b1};
                end else begin
                    remainder_next = shifted_remainder;
                    quotient_next = {quotient_next[WIDTH-2:0], 1'b0};
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            busy_q                  <= 1'b0;
            cycle_q                 <= '0;
            divisor_q               <= '0;
            dividend_shift_q        <= '0;
            quotient_q              <= '0;
            remainder_q             <= '0;
            result_valid_q          <= 1'b0;
            result_quotient_q       <= '0;
            result_remainder_q      <= '0;
            result_divide_by_zero_q <= 1'b0;
        end else begin
            if (result_valid_q && output_ready) begin
                result_valid_q <= 1'b0;
            end

            if (input_valid && input_ready) begin
                cycle_q          <= '0;
                divisor_q        <= input_divisor;
                dividend_shift_q <= input_dividend;
                quotient_q       <= '0;
                remainder_q      <= '0;

                if (input_divisor == '0) begin
                    busy_q                  <= 1'b0;
                    result_valid_q          <= 1'b1;
                    result_quotient_q       <= '1;
                    result_remainder_q      <= input_dividend;
                    result_divide_by_zero_q <= 1'b1;
                end else begin
                    busy_q                  <= 1'b1;
                    result_divide_by_zero_q <= 1'b0;
                end
            end else if (busy_q) begin
                dividend_shift_q <= dividend_shift_next;
                quotient_q       <= quotient_next;
                remainder_q      <= remainder_next;

                if (cycle_q == CYCLE_BITS'(DIV_CYC-1)) begin
                    busy_q             <= 1'b0;
                    cycle_q            <= '0;
                    result_valid_q     <= 1'b1;
                    result_quotient_q  <= quotient_next;
                    result_remainder_q <= remainder_next[WIDTH-1:0];
                end else begin
                    cycle_q <= cycle_q + 1'b1;
                end
            end
        end
    end

endmodule : div_iterative
