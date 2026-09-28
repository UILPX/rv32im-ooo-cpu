module mp_cache_data_array (
    input  logic           clk0,
    input  logic           csb0,
    input  logic           web0,
    input  logic [31:0]    wmask0,
    input  logic [3:0]     addr0,
    input  logic [255:0]   din0,
    output logic [255:0]   dout0
);

    sp_sram #(
        .DATA_WIDTH (256),
        .DEPTH      (16),
        .MASK_WIDTH (32)
    ) data_sram (
        .clk0,
        .csb0,
        .web0,
        .wmask0,
        .addr0,
        .din0,
        .dout0
    );

endmodule : mp_cache_data_array
