module issue_buffer (
    input   logic                       clk,
    input   logic                       rst,
    input   logic                       flush,

    input   logic                       input_valid,
    input   rv32im_types::res_stat_t    input_data,
    output  logic                       input_ready,

    output  logic                       output_valid,
    output  rv32im_types::res_stat_t    output_data,
    input   logic                       output_ready
);

    logic valid_q;
    rv32im_types::res_stat_t data_q;
    logic input_fire;
    logic output_fire;

    always_comb begin
        output_valid = !flush && valid_q;
        output_data = data_q;
        input_ready = !flush && (!valid_q || output_ready);
        input_fire = input_valid && input_ready;
        output_fire = output_valid && output_ready;
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_q <= 1'b0;
            data_q <= '0;
        end else begin
            if (input_fire) begin
                valid_q <= 1'b1;
                data_q <= input_data;
            end else if (output_fire) begin
                valid_q <= 1'b0;
            end
        end
    end

endmodule : issue_buffer
