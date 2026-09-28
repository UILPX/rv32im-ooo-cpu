module mp_cache_tag_array (
    input  logic           clk0,
    input  logic           csb0,
    input  logic           web0,
    input  logic [3:0]     addr0,
    input  logic [22:0]    din0,
    output logic [22:0]    dout0
);

    sp_sram #(
        .DATA_WIDTH (23),
        .DEPTH      (16),
        .MASK_WIDTH (1)
    ) tag_sram (
        .clk0,
        .csb0,
        .web0,
        .wmask0 (1'b1),
        .addr0,
        .din0,
        .dout0
    );

endmodule : mp_cache_tag_array
