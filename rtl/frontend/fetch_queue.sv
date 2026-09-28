module fetch_queue #(
    parameter integer unsigned DEPTH = 8,
    parameter integer unsigned DISPATCH_WIDTH = 2,
    parameter integer unsigned COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input   logic                       clk,
    input   logic                       rst,
    input   logic                       flush,

    input   logic   [1:0]               push_mask,
    input   rv32im_types::fetch_inst_t  push_data_0,
    input   rv32im_types::fetch_inst_t  push_data_1,
    output  logic   [COUNT_WIDTH-1:0]   slots_available,

    output  logic   [1:0]               dispatch_valid,
    output  rv32im_types::fetch_inst_t  dispatch_data_0,
    output  rv32im_types::fetch_inst_t  dispatch_data_1,
    input   logic   [1:0]               dispatch_ready
);

    localparam integer unsigned PTR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    rv32im_types::fetch_inst_t entries_q [DEPTH];
    logic [PTR_WIDTH-1:0] head_q;
    logic [PTR_WIDTH-1:0] tail_q;
    logic [COUNT_WIDTH-1:0] count_q;

    logic [1:0] push_count;
    logic [1:0] pop_count;
    logic       pop_lane_0;
    logic       pop_lane_1;
    logic [PTR_WIDTH-1:0] second_idx;

    if ((DEPTH < 2) || (DISPATCH_WIDTH < 1) || (DISPATCH_WIDTH > 2)) begin : gen_invalid_parameters
        initial begin
            $error("fetch_queue requires DEPTH >= 2 and 1 <= DISPATCH_WIDTH <= 2");
        end
    end

    function automatic logic [PTR_WIDTH-1:0] ptr_add(
        input logic [PTR_WIDTH-1:0] ptr,
        input logic [1:0]           delta
    );
        logic [COUNT_WIDTH-1:0] sum;
        begin
            sum = COUNT_WIDTH'(ptr) + COUNT_WIDTH'(delta);
            if (sum >= COUNT_WIDTH'(DEPTH)) begin
                ptr_add = PTR_WIDTH'(sum - COUNT_WIDTH'(DEPTH));
            end else begin
                ptr_add = PTR_WIDTH'(sum);
            end
        end
    endfunction

    always_comb begin
        second_idx = ptr_add(head_q, 2'd1);

        dispatch_valid = 2'b00;
        dispatch_data_0 = '0;
        dispatch_data_1 = '0;

        if (!flush && (count_q != '0)) begin
            dispatch_valid[0] = 1'b1;
            dispatch_data_0 = entries_q[head_q];
        end

        if ((DISPATCH_WIDTH > 1) && !flush &&
            (count_q >= COUNT_WIDTH'(2))) begin
            dispatch_valid[1] = 1'b1;
            dispatch_data_1 = entries_q[second_idx];
        end

        pop_lane_0 = dispatch_valid[0] && dispatch_ready[0];
        pop_lane_1 = (DISPATCH_WIDTH > 1) && pop_lane_0 &&
                     dispatch_valid[1] && dispatch_ready[1];
        pop_count = 2'(pop_lane_0) + 2'(pop_lane_1);

        push_count = 2'(push_mask[0]) + 2'(push_mask[1]);
        slots_available = COUNT_WIDTH'(DEPTH) - count_q +
                          COUNT_WIDTH'(pop_count);
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
        end else begin
            if (push_mask[0]) begin
                entries_q[tail_q] <= push_data_0;
            end

            if (push_mask[1]) begin
                entries_q[ptr_add(tail_q, 2'd1)] <= push_data_1;
            end

            head_q <= ptr_add(head_q, pop_count);
            tail_q <= ptr_add(tail_q, push_count);
            count_q <= count_q - COUNT_WIDTH'(pop_count) +
                       COUNT_WIDTH'(push_count);
        end
    end

endmodule : fetch_queue
