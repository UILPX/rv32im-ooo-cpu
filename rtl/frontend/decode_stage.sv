module decode_stage #(
    parameter integer unsigned DECODE_WIDTH = 2,
    parameter bit ENABLE_RV32M = 1'b1
) (
    input   logic                            flush,

    input   logic   [1:0]                    fetch_valid,
    input   rv32im_types::fetch_inst_t       fetch_data_0,
    input   rv32im_types::fetch_inst_t       fetch_data_1,
    output  logic   [1:0]                    fetch_ready,

    output  logic   [1:0]                    decode_valid,
    output  rv32im_types::decoded_uop_t      decode_data_0,
    output  rv32im_types::decoded_uop_t      decode_data_1,
    input   logic   [1:0]                    decode_ready
);

    if ((DECODE_WIDTH < 1) || (DECODE_WIDTH > 2)) begin : gen_invalid_parameters
        initial begin
            $error("decode_stage requires 1 <= DECODE_WIDTH <= 2");
        end
    end

    decoder #(
        .ENABLE_RV32M (ENABLE_RV32M)
    ) decoder_0 (
        .fetch (fetch_data_0),
        .uop   (decode_data_0)
    );

    decoder #(
        .ENABLE_RV32M (ENABLE_RV32M)
    ) decoder_1 (
        .fetch (fetch_data_1),
        .uop   (decode_data_1)
    );

    always_comb begin
        decode_valid = 2'b00;
        fetch_ready = 2'b00;

        if (!flush) begin
            decode_valid[0] = fetch_valid[0];
            fetch_ready[0] = decode_ready[0];

            if (DECODE_WIDTH > 1) begin
                decode_valid[1] = fetch_valid[1];
                fetch_ready[1] = fetch_ready[0] && decode_ready[1];
            end
        end
    end

endmodule : decode_stage
