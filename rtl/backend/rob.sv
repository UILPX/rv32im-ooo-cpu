module rob #(
    parameter integer unsigned DEPTH = 16,
    parameter integer unsigned ALLOC_WIDTH = 2,
    parameter integer unsigned COMMIT_WIDTH = 2,
    parameter integer unsigned COMPLETE_PORTS = 2,
    parameter integer unsigned COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input   logic                           clk,
    input   logic                           rst,
    input   logic                           flush,

    input   logic   [1:0]                   alloc_valid,
    input   rv32im_types::renamed_uop_t     alloc_data_0,
    input   rv32im_types::renamed_uop_t     alloc_data_1,
    output  logic   [1:0]                   alloc_ready,

    output  logic   [1:0]                   dispatch_valid,
    output  rv32im_types::rob_uop_t         dispatch_data_0,
    output  rv32im_types::rob_uop_t         dispatch_data_1,
    input   logic   [1:0]                   dispatch_ready,

    input   rv32im_types::rob_complete_t    complete_data_0,
    input   rv32im_types::rob_complete_t    complete_data_1,

    output  logic   [1:0]                   commit_valid,
    output  rv32im_types::rob_commit_t      commit_data_0,
    output  rv32im_types::rob_commit_t      commit_data_1,
    input   logic   [1:0]                   commit_ready,

    output  logic                           head_valid,
    output  rv32im_types::rob_tag_t         head_tag,

    output  logic   [COUNT_WIDTH-1:0]       count
);

    localparam integer unsigned PTR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam integer unsigned TAG_COMPARE_WIDTH =
        rv32im_types::ROB_TAG_BITS + 1;
    localparam integer unsigned ENTRY_BITS = $bits(dispatch_data_0);
    localparam integer unsigned RESULT_BITS = $bits(complete_data_0);

    logic [ENTRY_BITS-1:0] entries_q [DEPTH];
    logic [ENTRY_BITS-1:0] entries_d [DEPTH];
    logic [RESULT_BITS-1:0] results_q [DEPTH];
    logic [RESULT_BITS-1:0] results_d [DEPTH];
    logic [DEPTH-1:0] valid_q, valid_d;
    logic [DEPTH-1:0] complete_q, complete_d;
    logic [PTR_WIDTH-1:0] head_q, head_d;
    logic [PTR_WIDTH-1:0] tail_q, tail_d;
    logic [COUNT_WIDTH-1:0] count_q, count_d;

    logic [PTR_WIDTH-1:0] head_second;
    logic [PTR_WIDTH-1:0] tail_second;
    logic [1:0] pop_count;
    logic [1:0] push_count;
    logic commit_fire_0;
    logic commit_fire_1;
    logic dispatch_fire_0;
    logic dispatch_fire_1;
    logic [COUNT_WIDTH-1:0] slots_available;

    if ((DEPTH < 2) || (DEPTH > (1 << rv32im_types::ROB_TAG_BITS)) ||
        (ALLOC_WIDTH < 1) || (ALLOC_WIDTH > 2) ||
        (COMMIT_WIDTH < 1) || (COMMIT_WIDTH > 2) ||
        (COMPLETE_PORTS < 1) || (COMPLETE_PORTS > 2)) begin : gen_invalid_parameters
        initial begin
            $error("rob requires 2 <= DEPTH <= 16 and widths in 1..2");
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

    function automatic rv32im_types::rob_complete_t illegal_result(
        input rv32im_types::rob_tag_t tag
    );
        rv32im_types::rob_complete_t result;
        begin
            result = '0;
            result.valid = 1'b1;
            result.rob_tag = tag;
            result.exception_valid = 1'b1;
            result.exception_cause = rv32im_types::EXC_ILLEGAL;
            illegal_result = result;
        end
    endfunction

    always_comb begin
        head_second = ptr_add(head_q, 2'd1);
        tail_second = ptr_add(tail_q, 2'd1);
        count = count_q;
        head_valid = !flush && (count_q != '0) && valid_q[head_q];
        head_tag = rv32im_types::rob_tag_t'(head_q);

        commit_valid = 2'b00;
        commit_data_0 = '0;
        commit_data_1 = '0;

        if (!flush && (count_q != '0) && valid_q[head_q] &&
            complete_q[head_q]) begin
            commit_valid[0] = 1'b1;
            commit_data_0.uop = entries_q[head_q];
            commit_data_0.result = results_q[head_q];
        end
        if ((COMMIT_WIDTH > 1) && !flush &&
            (count_q >= COUNT_WIDTH'(2)) && commit_valid[0] &&
            valid_q[head_second] && complete_q[head_second]) begin
            commit_valid[1] = 1'b1;
            commit_data_1.uop = entries_q[head_second];
            commit_data_1.result = results_q[head_second];
        end

        commit_fire_0 = commit_valid[0] && commit_ready[0];
        commit_fire_1 = commit_fire_0 && commit_valid[1] && commit_ready[1];
        pop_count = 2'(commit_fire_0) + 2'(commit_fire_1);
        slots_available = COUNT_WIDTH'(DEPTH) - count_q +
                          COUNT_WIDTH'(pop_count);

        dispatch_data_0 = '0;
        dispatch_data_1 = '0;
        dispatch_data_0.renamed = alloc_data_0;
        dispatch_data_0.rob_tag = rv32im_types::rob_tag_t'(tail_q);
        dispatch_data_1.renamed = alloc_data_1;
        dispatch_data_1.rob_tag = rv32im_types::rob_tag_t'(tail_second);
        dispatch_valid = 2'b00;
        alloc_ready = 2'b00;

        if (!flush) begin
            dispatch_valid[0] = alloc_valid[0] &&
                (slots_available >= COUNT_WIDTH'(1));
            alloc_ready[0] = (slots_available >= COUNT_WIDTH'(1)) &&
                dispatch_ready[0];

            if (ALLOC_WIDTH > 1) begin
                dispatch_valid[1] = alloc_valid[0] && alloc_valid[1] &&
                    (slots_available >= COUNT_WIDTH'(2));
                alloc_ready[1] = alloc_ready[0] &&
                    (slots_available >= COUNT_WIDTH'(2)) &&
                    dispatch_ready[1];
            end
        end

        dispatch_fire_0 = dispatch_valid[0] && dispatch_ready[0];
        dispatch_fire_1 = dispatch_fire_0 && dispatch_valid[1] &&
                          dispatch_ready[1];
        push_count = 2'(dispatch_fire_0) + 2'(dispatch_fire_1);
    end

    always_comb begin
        for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
            entries_d[i] = entries_q[i];
            results_d[i] = results_q[i];
        end
        valid_d = valid_q;
        complete_d = complete_q;
        head_d = head_q;
        tail_d = tail_q;
        count_d = count_q;

        if (flush) begin
            valid_d = '0;
            complete_d = '0;
            head_d = '0;
            tail_d = '0;
            count_d = '0;
        end else begin
            if (complete_data_0.valid &&
                (TAG_COMPARE_WIDTH'(complete_data_0.rob_tag) <
                 TAG_COMPARE_WIDTH'(DEPTH)) &&
                valid_q[PTR_WIDTH'(complete_data_0.rob_tag)]) begin
                complete_d[PTR_WIDTH'(complete_data_0.rob_tag)] = 1'b1;
                results_d[PTR_WIDTH'(complete_data_0.rob_tag)] = complete_data_0;
            end
            if ((COMPLETE_PORTS > 1) && complete_data_1.valid &&
                (TAG_COMPARE_WIDTH'(complete_data_1.rob_tag) <
                 TAG_COMPARE_WIDTH'(DEPTH)) &&
                valid_q[PTR_WIDTH'(complete_data_1.rob_tag)]) begin
                complete_d[PTR_WIDTH'(complete_data_1.rob_tag)] = 1'b1;
                results_d[PTR_WIDTH'(complete_data_1.rob_tag)] = complete_data_1;
            end

            if (commit_fire_0) begin
                valid_d[head_q] = 1'b0;
                complete_d[head_q] = 1'b0;
            end
            if (commit_fire_1) begin
                valid_d[head_second] = 1'b0;
                complete_d[head_second] = 1'b0;
            end

            if (dispatch_fire_0) begin
                entries_d[tail_q] = dispatch_data_0;
                results_d[tail_q] = '0;
                valid_d[tail_q] = 1'b1;
                complete_d[tail_q] = alloc_data_0.decoded.illegal;
                if (alloc_data_0.decoded.illegal) begin
                    results_d[tail_q] = illegal_result(dispatch_data_0.rob_tag);
                end
            end
            if (dispatch_fire_1) begin
                entries_d[tail_second] = dispatch_data_1;
                results_d[tail_second] = '0;
                valid_d[tail_second] = 1'b1;
                complete_d[tail_second] = alloc_data_1.decoded.illegal;
                if (alloc_data_1.decoded.illegal) begin
                    results_d[tail_second] = illegal_result(dispatch_data_1.rob_tag);
                end
            end

            head_d = ptr_add(head_q, pop_count);
            tail_d = ptr_add(tail_q, push_count);
            count_d = count_q - COUNT_WIDTH'(pop_count) +
                      COUNT_WIDTH'(push_count);
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_q <= '0;
            complete_q <= '0;
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                entries_q[i] <= '0;
                results_q[i] <= '0;
            end
        end else begin
            valid_q <= valid_d;
            complete_q <= complete_d;
            head_q <= head_d;
            tail_q <= tail_d;
            count_q <= count_d;
            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                entries_q[i] <= entries_d[i];
                results_q[i] <= results_d[i];
            end
        end
    end

endmodule : rob
