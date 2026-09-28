module decode_buffer #(
    parameter integer unsigned DEPTH = 4,
    parameter integer unsigned DECODE_WIDTH = 2,
    parameter integer unsigned COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input   logic                               clk,
    input   logic                               rst,
    input   logic                               flush,

    input   logic   [1:0]                       push_valid,
    input   rv32im_types::decoded_uop_t         push_data_0,
    input   rv32im_types::decoded_uop_t         push_data_1,
    output  logic   [1:0]                       push_ready,

    output  logic   [1:0]                       decode_valid,
    output  rv32im_types::decoded_uop_t         decode_data_0,
    output  rv32im_types::decoded_uop_t         decode_data_1,
    input   logic   [1:0]                       decode_ready,

    output  logic   [COUNT_WIDTH-1:0]           count
);

    localparam integer unsigned PTR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam integer unsigned ENTRY_BITS = $bits(decode_data_0);

    logic [ENTRY_BITS-1:0] entries_q [DEPTH];
    logic [PTR_WIDTH-1:0] head_q;
    logic [PTR_WIDTH-1:0] tail_q;
    logic [COUNT_WIDTH-1:0] count_q;
    logic [PTR_WIDTH-1:0] head_second;
    logic [1:0] pop_count;
    logic [1:0] push_count;
    logic pop_0;
    logic pop_1;
    logic push_0;
    logic push_1;
    logic [COUNT_WIDTH-1:0] free_slots_q;

    if ((DEPTH < 2) || (DECODE_WIDTH < 1) ||
        (DECODE_WIDTH > 2)) begin : gen_invalid_parameters
        initial begin
            $error("decode_buffer requires DEPTH >= 2 and width in 1..2");
        end
    end

    function automatic logic [PTR_WIDTH-1:0] ptr_add(
        input logic [PTR_WIDTH-1:0] ptr,
        input logic [1:0] delta
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
        head_second = ptr_add(head_q, 2'd1);
        count = count_q;
        decode_valid = 2'b00;
        decode_data_0 = '0;
        decode_data_1 = '0;

        if (!flush && (count_q != '0)) begin
            decode_valid[0] = 1'b1;
            decode_data_0 = entries_q[head_q];
        end
        if ((DECODE_WIDTH > 1) && !flush &&
            (count_q >= COUNT_WIDTH'(2))) begin
            decode_valid[1] = 1'b1;
            decode_data_1 = entries_q[head_second];
        end

        pop_0 = decode_valid[0] && decode_ready[0];
        pop_1 = pop_0 && decode_valid[1] && decode_ready[1];
        pop_count = 2'(pop_0) + 2'(pop_1);

        // Do not borrow slots from a same-cycle pop. This deliberately keeps
        // backend readiness out of the frontend's combinational ready path.
        free_slots_q = COUNT_WIDTH'(DEPTH) - count_q;
        push_ready = 2'b00;
        if (!flush) begin
            push_ready[0] = free_slots_q >= COUNT_WIDTH'(1);
            if (DECODE_WIDTH > 1) begin
                push_ready[1] = push_ready[0] &&
                    (free_slots_q >= COUNT_WIDTH'(2));
            end
        end

        push_0 = push_valid[0] && push_ready[0];
        push_1 = push_0 && push_valid[1] && push_ready[1];
        push_count = 2'(push_0) + 2'(push_1);
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            for (integer unsigned i = 0; i < DEPTH; i++) begin
                entries_q[i] <= '0;
            end
        end else begin
            if (push_0) begin
                entries_q[tail_q] <= push_data_0;
            end
            if (push_1) begin
                entries_q[ptr_add(tail_q, 2'd1)] <= push_data_1;
            end
            head_q <= ptr_add(head_q, pop_count);
            tail_q <= ptr_add(tail_q, push_count);
            count_q <= count_q - COUNT_WIDTH'(pop_count) +
                       COUNT_WIDTH'(push_count);
        end
    end

endmodule : decode_buffer
