module sp_sram #(
    parameter integer unsigned DATA_WIDTH = 32,
    parameter integer unsigned DEPTH      = 16,
    parameter integer unsigned MASK_WIDTH = 1,
    parameter integer unsigned ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                      clk0,
    input  logic                      csb0,
    input  logic                      web0,
    input  logic [MASK_WIDTH-1:0]     wmask0,
    input  logic [ADDR_WIDTH-1:0]     addr0,
    input  logic [DATA_WIDTH-1:0]     din0,
    output logic [DATA_WIDTH-1:0]     dout0
);

    localparam integer unsigned MASK_GRANULARITY =
        (MASK_WIDTH == 0) ? 1 : DATA_WIDTH / MASK_WIDTH;
    localparam integer unsigned REQUIRED_ADDR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam logic MASK_DIVISIBLE =
        (MASK_WIDTH == 0) ? 1'b0 : ((DATA_WIDTH % MASK_WIDTH) == 0);

    logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    if ((DATA_WIDTH == 0) || (DEPTH == 0) || (MASK_WIDTH == 0) ||
        !MASK_DIVISIBLE || (ADDR_WIDTH < REQUIRED_ADDR_WIDTH)) begin : gen_invalid_parameters
        initial begin
            $error("sp_sram parameters are inconsistent");
        end
    end

    always_ff @(posedge clk0) begin
        if (!csb0) begin
            if (!web0) begin
                for (integer unsigned i = 0; i < MASK_WIDTH; i = i + 1) begin
                    if (wmask0[i]) begin
                        memory[addr0][i*MASK_GRANULARITY +: MASK_GRANULARITY]
                            <= din0[i*MASK_GRANULARITY +: MASK_GRANULARITY];
                    end
                end
            end else begin
                dout0 <= memory[addr0];
            end
        end
    end

endmodule : sp_sram
