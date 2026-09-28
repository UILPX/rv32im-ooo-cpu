module i_fetch_ooo #(
    parameter integer unsigned QUE_DEPTH = 8,
    parameter integer unsigned FETCH_ROB_DEPTH = 4,
    parameter integer unsigned FETCH_WIDTH = 2,
    parameter integer unsigned QUEUE_COUNT_WIDTH =
        (QUE_DEPTH <= 1) ? 1 : $clog2(QUE_DEPTH + 1),
    parameter logic [31:0] RESET_PC = 32'hAAAAA000,
    parameter integer unsigned BP_PHT_ENTRIES = 128,
    parameter integer unsigned BP_RAS_ENTRIES = 4
) (
    input   logic           clk,
    input   logic           rst,

    input   logic           flush,
    input   logic   [31:0]  new_pc,

    input   logic           bp_update_valid,
    input   logic   [31:0]  bp_update_pc,
    input   logic           bp_update_is_cond_branch,
    input   logic           bp_update_is_jalr,
    input   logic           bp_update_is_call,
    input   logic           bp_update_is_return,
    input   logic           bp_update_taken,
    input   logic   [31:0]  bp_update_target,

    output  logic   [31:0]  addr_0,
    output  logic   [3:0]   rmask_0,
    input   logic   [31:0]  rdata_0,
    input   logic           resp_0,

    output  logic   [31:0]  addr_1,
    output  logic   [3:0]   rmask_1,
    input   logic   [31:0]  rdata_1,
    input   logic           resp_1,

    output  logic   [1:0]   push_mask,
    output  rv32im_types::fetch_inst_t push_data_0,
    output  rv32im_types::fetch_inst_t push_data_1,
    input   logic   [QUEUE_COUNT_WIDTH-1:0] queue_left
);

    localparam integer ROB_PTR_W =
        (FETCH_ROB_DEPTH <= 1) ? 1 : $clog2(FETCH_ROB_DEPTH);
    localparam integer ROB_CNT_W = ROB_PTR_W + 1;

    if ((FETCH_WIDTH < 1) || (FETCH_WIDTH > 2) ||
        (FETCH_ROB_DEPTH < FETCH_WIDTH) || (QUE_DEPTH < 2)) begin : gen_invalid_parameters
        initial begin
            $error("i_fetch_ooo requires 1 <= FETCH_WIDTH <= 2, FETCH_ROB_DEPTH >= FETCH_WIDTH, and QUE_DEPTH >= 2");
        end
    end

    logic   [31:0]  next_pc_q, next_pc_n;
    logic   [63:0]  next_order_q, next_order_n;

    logic   [ROB_PTR_W-1:0] rob_head_q, rob_head_n;
    logic   [ROB_PTR_W-1:0] rob_tail_q, rob_tail_n;
    logic   [ROB_CNT_W-1:0] rob_count_q, rob_count_n;

    logic                   rob_valid_q [FETCH_ROB_DEPTH];
    logic                   rob_valid_n [FETCH_ROB_DEPTH];
    logic                   rob_ready_q [FETCH_ROB_DEPTH];
    logic                   rob_ready_n [FETCH_ROB_DEPTH];
    logic                   rob_port_q [FETCH_ROB_DEPTH];
    logic                   rob_port_n [FETCH_ROB_DEPTH];
    logic   [31:0]          rob_pc_q [FETCH_ROB_DEPTH];
    logic   [31:0]          rob_pc_n [FETCH_ROB_DEPTH];
    logic   [31:0]          rob_inst_q [FETCH_ROB_DEPTH];
    logic   [31:0]          rob_inst_n [FETCH_ROB_DEPTH];
    logic   [63:0]          rob_order_q [FETCH_ROB_DEPTH];
    logic   [63:0]          rob_order_n [FETCH_ROB_DEPTH];

    logic   [1:0]           port_busy_q, port_busy_n;
    logic   [1:0]           port_kill_q, port_kill_n;
    logic   [31:0]          port_addr_q [2], port_addr_n [2];
    logic   [ROB_PTR_W-1:0] port_rob_idx_q [2], port_rob_idx_n [2];

    logic   [31:0]          rdata [2];
    logic   [1:0]           resp;
    logic   [ROB_PTR_W-1:0] head_idx;
    logic   [ROB_PTR_W-1:0] second_idx;
    logic   [ROB_PTR_W-1:0] alloc_idx;
    logic   [ROB_CNT_W-1:0] rob_space;
    logic   [1:0]           pop_cnt;
    logic                   redirect;
    logic   [31:0]          redirect_pc;
    logic   [63:0]          redirect_order;
    logic   [31:0]          issue_pc_cursor;
    logic   [63:0]          issue_order_cursor;
    logic   [63:0]          queued_cnt;
    logic   [63:0]          rollback_cnt;
    logic   [63:0]          rollback_order;
    logic   [ROB_PTR_W-1:0] pred_second_idx;
    logic   [1:0]           pred_ready;
    logic   [1:0]           pred_valid;
    logic   [1:0]           pred_taken;
    logic   [31:0]          pred_inst_0;
    logic   [31:0]          pred_inst_1;
    logic   [31:0]          pred_pc_0;
    logic   [31:0]          pred_pc_1;

    function automatic logic [ROB_PTR_W-1:0] ptr_add(
        input logic [ROB_PTR_W-1:0] ptr,
        input logic [1:0]           delta
    );
        logic [ROB_CNT_W-1:0] sum;
        begin
            sum = ROB_CNT_W'(ptr) + ROB_CNT_W'(delta);
            if (sum >= ROB_CNT_W'(FETCH_ROB_DEPTH)) begin
                ptr_add = ROB_PTR_W'(sum - ROB_CNT_W'(FETCH_ROB_DEPTH));
            end else begin
                ptr_add = ROB_PTR_W'(sum);
            end
        end
    endfunction

    always_comb begin
        resp[0] = resp_0;
        resp[1] = resp_1;
        rdata[0] = rdata_0;
        rdata[1] = rdata_1;
    end

    assign pred_second_idx = ptr_add(rob_head_q, 2'd1);
    always_comb begin
        pred_ready[0] = rob_ready_q[rob_head_q];
        pred_ready[1] = rob_ready_q[pred_second_idx];
        pred_inst_0 = rob_inst_q[rob_head_q];
        pred_inst_1 = rob_inst_q[pred_second_idx];

        for (integer unsigned p = 0; p < 2; p = p + 1) begin
            if (port_busy_q[p] && resp[p] && !port_kill_q[p]) begin
                if (port_rob_idx_q[p] == rob_head_q) begin
                    pred_ready[0] = 1'b1;
                    pred_inst_0 = rdata[p];
                end

                if (port_rob_idx_q[p] == pred_second_idx) begin
                    pred_ready[1] = 1'b1;
                    pred_inst_1 = rdata[p];
                end
            end
        end
    end

    assign pred_valid[0] = !flush && (rob_count_q != '0) &&
                           rob_valid_q[rob_head_q] && pred_ready[0] &&
                           (queue_left != QUEUE_COUNT_WIDTH'(0));
    assign pred_valid[1] = (FETCH_WIDTH > 1) && !flush &&
                           (rob_count_q >= ROB_CNT_W'(2)) &&
                           rob_valid_q[pred_second_idx] && pred_ready[1] &&
                           (queue_left >= QUEUE_COUNT_WIDTH'(2));

    br_pred #(
        .PHT_ENTRIES(BP_PHT_ENTRIES),
        .RAS_ENTRIES(BP_RAS_ENTRIES)
    ) bp (
        .clk(clk),
        .rst(rst),
        .predecode_valid_0(pred_valid[0]),
        .predecode_valid_1(pred_valid[1]),
        .predecode_inst_0(pred_inst_0),
        .predecode_inst_1(pred_inst_1),
        .predecode_flush(flush || redirect),
        .pc_0(rob_pc_q[rob_head_q]),
        .pc_1(rob_pc_q[pred_second_idx]),
        .update_valid(bp_update_valid),
        .update_pc(bp_update_pc),
        .update_is_cond_branch(bp_update_is_cond_branch),
        .update_is_jalr(bp_update_is_jalr),
        .update_is_call(bp_update_is_call),
        .update_is_return(bp_update_is_return),
        .update_taken(bp_update_taken),
        .update_target(bp_update_target),
        .taken(pred_taken),
        .jump_pc_0(pred_pc_0),
        .jump_pc_1(pred_pc_1)
    );

    always_comb begin
        next_pc_n = next_pc_q;
        next_order_n = next_order_q;
        rob_head_n = rob_head_q;
        rob_tail_n = rob_tail_q;
        rob_count_n = rob_count_q;
        port_busy_n = port_busy_q;
        port_kill_n = port_kill_q;

        for (integer unsigned i = 0; i < FETCH_ROB_DEPTH; i = i + 1) begin
            rob_valid_n[i] = rob_valid_q[i];
            rob_ready_n[i] = rob_ready_q[i];
            rob_port_n[i] = rob_port_q[i];
            rob_pc_n[i] = rob_pc_q[i];
            rob_inst_n[i] = rob_inst_q[i];
            rob_order_n[i] = rob_order_q[i];
        end

        for (integer unsigned p = 0; p < 2; p = p + 1) begin
            port_addr_n[p] = port_addr_q[p];
            port_rob_idx_n[p] = port_rob_idx_q[p];
        end

        push_mask = 2'b00;
        push_data_0 = '0;
        push_data_1 = '0;
        pop_cnt = 2'd0;
        redirect = 1'b0;
        redirect_pc = 32'b0;
        redirect_order = 64'b0;
        head_idx = '0;
        second_idx = '0;
        alloc_idx = '0;
        rob_space = '0;
        issue_pc_cursor = next_pc_q;
        issue_order_cursor = next_order_q;

        queued_cnt = (64'(QUE_DEPTH) > 64'(queue_left)) ?
                     (64'(QUE_DEPTH) - 64'(queue_left)) : 64'd0;
        rollback_cnt = queued_cnt + 64'(rob_count_q);
        rollback_order = (next_order_q >= rollback_cnt) ?
                         (next_order_q - rollback_cnt) : 64'd0;

        for (integer unsigned p = 0; p < 2; p = p + 1) begin
            if (port_busy_q[p] && resp[p]) begin
                port_busy_n[p] = 1'b0;
                port_kill_n[p] = 1'b0;

                if (!port_kill_q[p]) begin
                    rob_ready_n[port_rob_idx_q[p]] = 1'b1;
                    rob_inst_n[port_rob_idx_q[p]] = rdata[p];
                end
            end
        end

        if (flush) begin
            next_pc_n = new_pc;
            next_order_n = rollback_order;

            for (integer unsigned i = 0; i < FETCH_ROB_DEPTH; i = i + 1) begin
                if (rob_valid_n[i] && !rob_ready_n[i] &&
                    port_busy_n[rob_port_n[i]]) begin
                    port_kill_n[rob_port_n[i]] = 1'b1;
                end

                rob_valid_n[i] = 1'b0;
                rob_ready_n[i] = 1'b0;
            end

            rob_head_n = '0;
            rob_tail_n = '0;
            rob_count_n = '0;
        end else begin
            head_idx = rob_head_n;
            second_idx = ptr_add(rob_head_n, 2'd1);

            if (pred_valid[0]) begin
                push_mask[0] = 1'b1;
                push_data_0.pc = rob_pc_q[head_idx];
                push_data_0.inst = pred_inst_0;
                push_data_0.rvfi_order = rob_order_q[head_idx];
                push_data_0.pred_taken = pred_taken[0];
                push_data_0.pred_pc = pred_pc_0;
                pop_cnt = 2'd1;

                if (pred_taken[0]) begin
                    redirect = 1'b1;
                    redirect_pc = pred_pc_0;
                    redirect_order = rob_order_q[head_idx] + 64'd1;
                end else if (pred_valid[1]) begin
                    push_mask[1] = 1'b1;
                    push_data_1.pc = rob_pc_q[second_idx];
                    push_data_1.inst = pred_inst_1;
                    push_data_1.rvfi_order = rob_order_q[second_idx];
                    push_data_1.pred_taken = pred_taken[1];
                    push_data_1.pred_pc = pred_pc_1;
                    pop_cnt = 2'd2;

                    if (pred_taken[1]) begin
                        redirect = 1'b1;
                        redirect_pc = pred_pc_1;
                        redirect_order = rob_order_q[second_idx] + 64'd1;
                    end
                end
            end

            if (pop_cnt != 2'd0) begin
                rob_valid_n[head_idx] = 1'b0;
                rob_ready_n[head_idx] = 1'b0;

                if (pop_cnt == 2'd2) begin
                    rob_valid_n[second_idx] = 1'b0;
                    rob_ready_n[second_idx] = 1'b0;
                end

                rob_head_n = ptr_add(rob_head_n, pop_cnt);
                rob_count_n = rob_count_n - ROB_CNT_W'(pop_cnt);
            end

            if (redirect) begin
                next_pc_n = redirect_pc;
                next_order_n = redirect_order;

                for (integer unsigned i = 0; i < FETCH_ROB_DEPTH; i = i + 1) begin
                    if (rob_valid_n[i] && !rob_ready_n[i] &&
                        port_busy_n[rob_port_n[i]]) begin
                        port_kill_n[rob_port_n[i]] = 1'b1;
                    end

                    rob_valid_n[i] = 1'b0;
                    rob_ready_n[i] = 1'b0;
                end

                rob_head_n = '0;
                rob_tail_n = '0;
                rob_count_n = '0;
            end
        end

        rob_space = ROB_CNT_W'(FETCH_ROB_DEPTH) - rob_count_n;
        issue_pc_cursor = next_pc_n;
        issue_order_cursor = next_order_n;

        for (integer unsigned p = 0; p < 2; p = p + 1) begin
            if ((p < FETCH_WIDTH) && !port_busy_q[p] && (rob_space != '0)) begin
                alloc_idx = rob_tail_n;

                rob_valid_n[alloc_idx] = 1'b1;
                rob_ready_n[alloc_idx] = 1'b0;
                rob_port_n[alloc_idx] = (p == 1);
                rob_pc_n[alloc_idx] = issue_pc_cursor;
                rob_inst_n[alloc_idx] = 32'b0;
                rob_order_n[alloc_idx] = issue_order_cursor;

                port_busy_n[p] = 1'b1;
                port_kill_n[p] = 1'b0;
                port_addr_n[p] = issue_pc_cursor;
                port_rob_idx_n[p] = alloc_idx;

                rob_tail_n = ptr_add(rob_tail_n, 2'd1);
                rob_count_n = rob_count_n + ROB_CNT_W'(1);
                rob_space = rob_space - ROB_CNT_W'(1);
                issue_pc_cursor = issue_pc_cursor + 32'd4;
                issue_order_cursor = issue_order_cursor + 64'd1;
            end
        end

        next_pc_n = issue_pc_cursor;
        next_order_n = issue_order_cursor;
    end

    always_comb begin
        addr_0 = 32'b0;
        addr_1 = 32'b0;
        rmask_0 = 4'b0000;
        rmask_1 = 4'b0000;

        if (port_busy_q[0]) begin
            addr_0 = port_addr_q[0];
            rmask_0 = 4'hf;
        end

        if ((FETCH_WIDTH > 1) && port_busy_q[1]) begin
            addr_1 = port_addr_q[1];
            rmask_1 = 4'hf;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            next_pc_q <= RESET_PC;
            next_order_q <= 64'd0;
            rob_head_q <= '0;
            rob_tail_q <= '0;
            rob_count_q <= '0;
            port_busy_q <= 2'b00;
            port_kill_q <= 2'b00;

            for (integer unsigned i = 0; i < FETCH_ROB_DEPTH; i = i + 1) begin
                rob_valid_q[i] <= 1'b0;
                rob_ready_q[i] <= 1'b0;
                rob_port_q[i] <= 1'b0;
                rob_pc_q[i] <= 32'b0;
                rob_inst_q[i] <= 32'b0;
                rob_order_q[i] <= 64'b0;
            end

            for (integer unsigned p = 0; p < 2; p = p + 1) begin
                port_addr_q[p] <= 32'b0;
                port_rob_idx_q[p] <= '0;
            end
        end else begin
            next_pc_q <= next_pc_n;
            next_order_q <= next_order_n;
            rob_head_q <= rob_head_n;
            rob_tail_q <= rob_tail_n;
            rob_count_q <= rob_count_n;
            port_busy_q <= port_busy_n;
            port_kill_q <= port_kill_n;

            for (integer unsigned i = 0; i < FETCH_ROB_DEPTH; i = i + 1) begin
                rob_valid_q[i] <= rob_valid_n[i];
                rob_ready_q[i] <= rob_ready_n[i];
                rob_port_q[i] <= rob_port_n[i];
                rob_pc_q[i] <= rob_pc_n[i];
                rob_inst_q[i] <= rob_inst_n[i];
                rob_order_q[i] <= rob_order_n[i];
            end

            for (integer unsigned p = 0; p < 2; p = p + 1) begin
                port_addr_q[p] <= port_addr_n[p];
                port_rob_idx_q[p] <= port_rob_idx_n[p];
            end
        end
    end

endmodule : i_fetch_ooo
