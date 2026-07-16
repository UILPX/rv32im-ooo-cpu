module i_fetch_ooo import rv32im_types::*; #(
    parameter       QUE_DEPTH = 8,
    parameter       FETCH_ROB_DEPTH = 4
) (
    input   logic           clk,
    input   logic           rst,

    input   logic           flush,
    input   logic   [31:0]  new_pc,

    output  logic   [31:0]  addr_0,
    output  logic   [3:0]   rmask_0,
    input   logic   [31:0]  rdata_0,
    input   logic           resp_0,

    output  logic   [31:0]  addr_1,
    output  logic   [3:0]   rmask_1,
    input   logic   [31:0]  rdata_1,
    input   logic           resp_1,

    output  logic   [1:0]   push_mask,
    output  fetch_inst_t    push_data_0,
    output  fetch_inst_t    push_data_1,
    input   logic   [3:0]   queue_left
);

    localparam logic [31:0] RESET_PC = 32'hAAAAA000;
    localparam integer ROB_PTR_W = $clog2(FETCH_ROB_DEPTH);
    localparam integer ROB_CNT_W = ROB_PTR_W + 1;

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
    logic   [1:0]           issue;
    logic   [31:0]          issue_addr [2];

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

    function automatic logic is_jal(input logic [31:0] inst);
        is_jal = (inst[6:0] == op_b_jal);
    endfunction

    function automatic logic [31:0] jal_target(
        input logic [31:0] pc,
        input logic [31:0] inst
    );
        logic [31:0] imm;
        begin
            imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            jal_target = pc + imm;
        end
    endfunction

    always_comb begin
        resp[0] = resp_0;
        resp[1] = resp_1;
        rdata[0] = rdata_0;
        rdata[1] = rdata_1;
    end

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
            issue[p] = 1'b0;
            issue_addr[p] = 32'b0;
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

            if ((rob_count_n != '0) &&
                rob_valid_n[head_idx] &&
                rob_ready_n[head_idx] &&
                (queue_left != 4'd0)) begin
                push_mask[0] = 1'b1;
                push_data_0.pc = rob_pc_n[head_idx];
                push_data_0.inst = rob_inst_n[head_idx];
                push_data_0.rvfi_order = rob_order_n[head_idx];
                pop_cnt = 2'd1;

                if (is_jal(rob_inst_n[head_idx])) begin
                    redirect = 1'b1;
                    redirect_pc = jal_target(rob_pc_n[head_idx], rob_inst_n[head_idx]);
                    redirect_order = rob_order_n[head_idx] + 64'd1;
                end else if ((rob_count_n >= ROB_CNT_W'(2)) &&
                             rob_valid_n[second_idx] &&
                             rob_ready_n[second_idx] &&
                             (queue_left >= 4'd2)) begin
                    push_mask[1] = 1'b1;
                    push_data_1.pc = rob_pc_n[second_idx];
                    push_data_1.inst = rob_inst_n[second_idx];
                    push_data_1.rvfi_order = rob_order_n[second_idx];
                    pop_cnt = 2'd2;

                    if (is_jal(rob_inst_n[second_idx])) begin
                        redirect = 1'b1;
                        redirect_pc = jal_target(rob_pc_n[second_idx],
                                                 rob_inst_n[second_idx]);
                        redirect_order = rob_order_n[second_idx] + 64'd1;
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
            if (!port_busy_q[p] && (rob_space != '0)) begin
                alloc_idx = rob_tail_n;
                issue[p] = 1'b1;
                issue_addr[p] = issue_pc_cursor;

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

        if (port_busy_q[1]) begin
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
