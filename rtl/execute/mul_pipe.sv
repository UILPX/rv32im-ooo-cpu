module mul_pipe #(
    parameter integer unsigned WIDTH      = 32,
    parameter integer unsigned NUM_STAGES = 2
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input   logic                   clk,
    input   logic                   rst,
    /* verilator lint_on UNUSEDSIGNAL */
    input   logic                   flush,

    input   logic                   input_valid,
    output  logic                   input_ready,
    input   logic   [WIDTH-1:0]     input_a,
    input   logic   [WIDTH-1:0]     input_b,

    output  logic                   output_valid,
    input   logic                   output_ready,
    output  logic   [2*WIDTH-1:0]   output_product
);

    generate
        if ((WIDTH == 0) || (NUM_STAGES == 0)) begin : gen_invalid_parameters
            initial begin
                $error("mul_pipe requires WIDTH >= 1 and NUM_STAGES >= 1");
            end

            always_comb begin
                input_ready    = 1'b0;
                output_valid   = 1'b0;
                output_product = '0;
            end
        end else if (NUM_STAGES == 1) begin : gen_combinational
            always_comb begin
                input_ready    = output_ready && !flush;
                output_valid   = input_valid && !flush;
                output_product = input_a * input_b;
            end
        end else begin : gen_pipeline
            localparam integer unsigned PIPE_REGS = NUM_STAGES - 1;

            logic                    advance;
            logic [PIPE_REGS-1:0]    valid_q;
            logic [2*WIDTH-1:0]      product_q [PIPE_REGS];

            assign advance        = !valid_q[PIPE_REGS-1] || output_ready;
            assign input_ready    = advance && !flush;
            assign output_valid   = valid_q[PIPE_REGS-1] && !flush;
            assign output_product = product_q[PIPE_REGS-1];

            always_ff @(posedge clk) begin
                integer unsigned i;

                if (rst || flush) begin
                    valid_q <= '0;
                    for (i = 0; i < PIPE_REGS; i = i + 1) begin
                        product_q[i] <= '0;
                    end
                end else if (advance) begin
                    for (i = PIPE_REGS-1; i > 0; i = i - 1) begin
                        valid_q[i]   <= valid_q[i-1];
                        product_q[i] <= product_q[i-1];
                    end

                    valid_q[0]   <= input_valid && input_ready;
                    product_q[0] <= input_a * input_b;
                end
            end
        end
    endgenerate

endmodule : mul_pipe
