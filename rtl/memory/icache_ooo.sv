// 只读 I-cache，前端有两个独立的 32-bit 取指接口。
//
// 约定：
// - 每个端口用 addr + rmask 发请求；等待 resp 期间，该端口的 addr/rmask 需要保持不变。
// - 每个端口一次只返回一个 32-bit word。
// - 两个端口之间不保序；谁先 ready 谁可以先返回。前端 fetch ROB 负责按 fetch order 出队。
//
// 实现：
// - 直接对接 OOO cache adapter，I-cache 本地维护轻量 MSHR。
// - demand miss 和 prefetch miss 都分配到具体 fill way；prefetch 返回后直接回填到 cache。
// - 同一条 line 的多个 demand 请求会在 I-cache 本地 merge，避免重复发 DRAM。
// - array 只有一套端口，因此 refill 周期会阻塞下一拍 lookup；这是当前版本保守换正确性的取舍。
module icache_ooo #(
    parameter integer ICACHE_MSHR_ENTRIES = 4,
    parameter integer PREFETCH_LINES_AHEAD = 1,
    parameter integer PREFETCH_MAX_OUTSTANDING = 1
) (
    input   logic                       clk,
    input   logic                       rst,

    // Front-end port 0
    input   logic   [31:0]              ufp_addr_0,
    input   logic   [3:0]               ufp_rmask_0,
    output  logic   [31:0]              ufp_rdata_0,
    output  logic                       ufp_resp_0,

    // Front-end port 1
    input   logic   [31:0]              ufp_addr_1,
    input   logic   [3:0]               ufp_rmask_1,
    output  logic   [31:0]              ufp_rdata_1,
    output  logic                       ufp_resp_1,

    // Shared OOO memory-side interface.
    output  logic                       mem_req_valid,
    input   logic                       mem_req_ready,
    output  rv32im_types::cache_mem_req_t mem_req,
    input   logic                       mem_resp_valid,
    output  logic                       mem_resp_ready,
    input   rv32im_types::cache_mem_resp_t mem_resp
);

    import rv32im_types::*;

    localparam integer MSHR_IDX_BITS = $clog2(ICACHE_MSHR_ENTRIES);
    localparam integer PREFETCH_CNT_W = $clog2(ICACHE_MSHR_ENTRIES + 1);
    localparam integer STREAM_LB_ENTRIES = 2;
    localparam logic [26:0] PREFETCH_LINES_AHEAD_U = PREFETCH_LINES_AHEAD;

    typedef struct packed {
        logic                               valid;
        logic                               sent;
        logic   [31:0]                      line_addr;
        logic   [CACHE_SET_BITS-1:0]        set_idx;
        logic   [CACHE_WAY_BITS-1:0]        fill_way;
        logic   [ICACHE_PORTS-1:0]          port_mask;
    } icache_mshr_t;

    typedef struct packed {
        logic                               valid;
        logic   [31:0]                      line_addr;
        logic   [ICACHE_PORTS-1:0]          port_mask;
    } lookup_ctx_t;

    icache_mshr_t                          mshr_q [ICACHE_MSHR_ENTRIES];
    icache_mshr_t                          mshr_n [ICACHE_MSHR_ENTRIES];
    lookup_ctx_t                           lookup_q, lookup_n;

    logic   [ICACHE_PORTS-1:0]             port_busy_q, port_busy_n;
    logic   [ICACHE_PORTS-1:0]             port_ready_q, port_ready_n;
    logic   [ICACHE_PORTS-1:0]             port_wait_mshr_q, port_wait_mshr_n;
    logic   [31:0]                         port_addr_q [ICACHE_PORTS];
    logic   [31:0]                         port_addr_n [ICACHE_PORTS];
    logic   [31:0]                         port_ready_data_q [ICACHE_PORTS];
    logic   [31:0]                         port_ready_data_n [ICACHE_PORTS];
    logic   [CACHE_MSHR_ID_BITS-1:0]       port_mshr_id_q [ICACHE_PORTS];
    logic   [CACHE_MSHR_ID_BITS-1:0]       port_mshr_id_n [ICACHE_PORTS];
    logic                                   port0_older_q, port0_older_n;

    logic                                   prefetch_active_q, prefetch_active_n;
    logic   [31:0]                          prefetch_cursor_q, prefetch_cursor_n;
    logic   [31:0]                          prefetch_target_q, prefetch_target_n;
    logic   [STREAM_LB_ENTRIES-1:0]         lb_valid_q;
    logic   [31:CACHE_OFFSET_BITS]          lb_tag_q [STREAM_LB_ENTRIES];
    logic   [CACHE_LINE_BITS-1:0]           lb_data_q [STREAM_LB_ENTRIES];
    logic                                   lb_replace_q;

    logic   [ICACHE_PORTS-1:0]             req_valid;
    logic   [ICACHE_PORTS-1:0]             new_req;
    logic   [ICACHE_PORTS-1:0]             active_now;
    logic   [ICACHE_PORTS-1:0]             lb_hit;
    logic   [ICACHE_PORTS-1:0]             port_need_lookup;
    logic   [ICACHE_PORTS-1:0]             port_merge_hit;
    logic   [ICACHE_PORTS-1:0]             port_event_valid;
    logic   [ICACHE_PORTS-1:0]             port_ready_all_valid;
    logic   [ICACHE_PORTS-1:0]             port_resp_fire;
    logic   [ICACHE_PORTS-1:0]             mem_fill_wait_mask;
    logic   [ICACHE_PORTS-1:0]             mshr_effective_port_mask [ICACHE_MSHR_ENTRIES];
    logic   [31:0]                         active_addr [ICACHE_PORTS];
    logic   [CACHE_LINE_BITS-1:0]          lb_hit_line_data [ICACHE_PORTS];
    logic   [31:0]                         port_event_data [ICACHE_PORTS];
    logic   [31:0]                         port_ready_all_data [ICACHE_PORTS];
    logic   [MSHR_IDX_BITS-1:0]            port_merge_idx [ICACHE_PORTS];

    logic                                   port0_older_now;

    logic                                   mshr_has_free;
    logic   [MSHR_IDX_BITS-1:0]            mshr_free_idx;
    logic   [PREFETCH_CNT_W-1:0]           active_prefetch_mshr_cnt;
    logic                                   lookup_miss_merge_hit;
    logic   [MSHR_IDX_BITS-1:0]            lookup_miss_merge_idx;
    logic                                   lb_demand_hit_valid;
    logic   [31:0]                          lb_demand_hit_line_addr;
    logic                                   prefetch_merge_hit;
    logic                                   prefetch_lb_hit;
    logic                                   prefetch_stream_valid;
    logic                                   prefetch_issue_allowed;
    logic                                   prefetch_advance_now;

    logic                                   lookup_issue_valid;
    logic   [31:0]                          lookup_issue_addr;
    logic   [ICACHE_PORTS-1:0]             lookup_issue_port_mask;

    logic                                   mem_req_pick_valid;
    logic   [MSHR_IDX_BITS-1:0]            mem_req_pick_idx;

    logic   [MSHR_IDX_BITS-1:0]            mem_resp_idx;
    logic                                   mem_fill_valid;

    logic                                   lookup_hit;
    logic   [CACHE_WAY_BITS-1:0]           lookup_hit_way;
    logic   [CACHE_WAY_BITS-1:0]           lookup_way_lru;
    logic   [CACHE_WAY_BITS-1:0]           lookup_fill_way;
    logic                                   lookup_hit_way0, lookup_hit_way1, lookup_hit_way2, lookup_hit_way3;
    logic   [CACHE_LINE_BITS-1:0]          lookup_hit_line_data;
    logic                                   lookup_is_demand;

    logic                                   demand_prefetch_valid;
    logic   [31:0]                          demand_prefetch_base_addr;
    logic   [31:0]                          demand_prefetch_cursor_addr;
    logic   [31:0]                          demand_prefetch_target_addr;

    logic                                   lru_hit_update_valid;
    logic   [CACHE_WAY_BITS-1:0]           lru_hit_update_way;

    logic                                   lb_fill_valid;
    logic   [31:CACHE_OFFSET_BITS]          lb_fill_tag;
    logic   [CACHE_LINE_BITS-1:0]           lb_fill_data;
    logic                                   lb_fill_idx;
    logic                                   lb_fill_hit_existing;

    logic   [3:0]                           csb_tag, web_tag;
    logic   [3:0]                           csb_data, web_data;
    logic   [3:0]                           csb_v, web_v;
    logic                                   csb_lru, web_lru;
    logic   [31:0]                          wmask_data;
    logic   [CACHE_SET_BITS-1:0]           set;
    logic   [22:0]                          tag_passin;
    logic   [22:0]                          tag_out [4];
    logic   [0:0]                           valid_in [4], valid_out [4];
    logic   [2:0]                           lru_in, lru_out;
    logic   [CACHE_LINE_BITS-1:0]          data_in, data_out [4];

    function automatic logic [31:0] line_word(
        input logic [CACHE_LINE_BITS-1:0] line_data,
        input logic [31:0]                addr
    );
        logic [7:0] bit_idx;
        begin
            bit_idx = {addr[4:2], 5'b0};
            line_word = line_data[bit_idx +: 32];
        end
    endfunction

    function automatic logic [2:0] plru_after_access(
        input logic [CACHE_WAY_BITS-1:0] accessed_way
    );
        begin
            unique case (accessed_way)
                2'd0: plru_after_access = 3'b011;
                2'd1: plru_after_access = 3'b001;
                2'd2: plru_after_access = 3'b100;
                default: plru_after_access = 3'b000;
            endcase
        end
    endfunction

    function automatic logic [31:0] line_addr_plus(
        input logic [31:0]  base_line_addr,
        input logic [26:0]  delta_lines
    );
        logic [26:0] line_idx;
        begin
            line_idx = base_line_addr[31:CACHE_OFFSET_BITS] + delta_lines;
            line_addr_plus = {line_idx, {CACHE_OFFSET_BITS{1'b0}}};
        end
    endfunction

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (csb_data[i]),
            .web0       (web_data[i]),
            .wmask0     (wmask_data),
            .addr0      (set),
            .din0       (data_in),
            .dout0      (data_out[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (csb_tag[i]),
            .web0       (web_tag[i]),
            .addr0      (set),
            .din0       (tag_passin),
            .dout0      (tag_out[i])
        );
        sp_ff_array #(
            .WIDTH      (1)
        ) valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (csb_v[i]),
            .web0       (web_v[i]),
            .addr0      (set),
            .din0       (valid_in[i]),
            .dout0      (valid_out[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (csb_lru),
        .web0       (web_lru),
        .addr0      (set),
        .din0       (lru_in),
        .dout0      (lru_out)
    );

    assign req_valid[0] = (ufp_rmask_0 != 4'b0000);
    assign req_valid[1] = (ufp_rmask_1 != 4'b0000);

    assign new_req[0] = req_valid[0] && !port_busy_q[0];
    assign new_req[1] = req_valid[1] && !port_busy_q[1];

    assign active_now[0] = port_busy_q[0] || new_req[0];
    assign active_now[1] = port_busy_q[1] || new_req[1];

    always_comb begin
        active_addr[0] = port_busy_q[0] ? port_addr_q[0] : ufp_addr_0;
        active_addr[1] = port_busy_q[1] ? port_addr_q[1] : ufp_addr_1;
    end

    always_comb begin
        prefetch_lb_hit = 1'b0;
        lb_demand_hit_valid = 1'b0;
        lb_demand_hit_line_addr = 32'b0;

        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            lb_hit[p] = 1'b0;
            lb_hit_line_data[p] = lb_data_q[0];

            if (active_now[p] &&
                !port_ready_q[p] &&
                !(port_busy_q[p] && port_wait_mshr_q[p])) begin
                if (lb_valid_q[0] &&
                    (lb_tag_q[0] == active_addr[p][31:CACHE_OFFSET_BITS])) begin
                    lb_hit[p] = 1'b1;
                    lb_hit_line_data[p] = lb_data_q[0];
                end else if (lb_valid_q[1] &&
                             (lb_tag_q[1] == active_addr[p][31:CACHE_OFFSET_BITS])) begin
                    lb_hit[p] = 1'b1;
                    lb_hit_line_data[p] = lb_data_q[1];
                end
            end

            if (lb_hit[p] &&
                (!lb_demand_hit_valid ||
                 (active_addr[p][31:CACHE_OFFSET_BITS] >
                  lb_demand_hit_line_addr[31:CACHE_OFFSET_BITS]))) begin
                lb_demand_hit_valid = 1'b1;
                lb_demand_hit_line_addr = {active_addr[p][31:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}};
            end
        end

        if (prefetch_stream_valid) begin
            prefetch_lb_hit =
                (lb_valid_q[0] && (lb_tag_q[0] == prefetch_cursor_q[31:CACHE_OFFSET_BITS])) ||
                (lb_valid_q[1] && (lb_tag_q[1] == prefetch_cursor_q[31:CACHE_OFFSET_BITS]));
        end
    end

    always_comb begin
        port0_older_now = 1'b1;
        if (active_now[0] && active_now[1]) begin
            if (port_busy_q[0] && port_busy_q[1]) begin
                port0_older_now = port0_older_q;
            end else if (port_busy_q[0]) begin
                port0_older_now = 1'b1;
            end else if (port_busy_q[1]) begin
                port0_older_now = 1'b0;
            end else begin
                port0_older_now = (ufp_addr_0 <= ufp_addr_1);
            end
        end
    end

    assign mem_resp_idx = mem_resp.mshr_id[MSHR_IDX_BITS-1:0];
    assign mem_fill_valid = mem_resp_valid &&
                            (mem_resp.src == cache_src_icache) &&
                            mshr_q[mem_resp_idx].valid;
    assign prefetch_stream_valid =
        (PREFETCH_LINES_AHEAD > 0) &&
        prefetch_active_q &&
        (prefetch_cursor_q[31:CACHE_OFFSET_BITS] <= prefetch_target_q[31:CACHE_OFFSET_BITS]);

    always_comb begin
        mshr_has_free = 1'b0;
        mshr_free_idx = '0;
        active_prefetch_mshr_cnt = '0;
        lookup_miss_merge_hit = 1'b0;
        lookup_miss_merge_idx = '0;
        prefetch_merge_hit = prefetch_lb_hit;

        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            port_merge_hit[p] = 1'b0;
            port_merge_idx[p] = '0;
        end

        for (integer unsigned i = 0; i < ICACHE_MSHR_ENTRIES; i = i + 1) begin
            if (!mshr_has_free && !mshr_q[i].valid) begin
                mshr_has_free = 1'b1;
                mshr_free_idx = MSHR_IDX_BITS'(i);
            end

            if (mshr_q[i].valid && (mshr_q[i].port_mask == '0)) begin
                active_prefetch_mshr_cnt = active_prefetch_mshr_cnt + PREFETCH_CNT_W'(1);
            end

            if (mshr_q[i].valid && !(mem_fill_valid && (mem_resp_idx == MSHR_IDX_BITS'(i)))) begin
                if (!lookup_miss_merge_hit &&
                    lookup_q.valid &&
                    (mshr_q[i].line_addr[31:CACHE_OFFSET_BITS] == lookup_q.line_addr[31:CACHE_OFFSET_BITS])) begin
                    lookup_miss_merge_hit = 1'b1;
                    lookup_miss_merge_idx = MSHR_IDX_BITS'(i);
                end

                if (!prefetch_merge_hit &&
                    prefetch_stream_valid &&
                    (mshr_q[i].line_addr[31:CACHE_OFFSET_BITS] == prefetch_cursor_q[31:CACHE_OFFSET_BITS])) begin
                    prefetch_merge_hit = 1'b1;
                end

                for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
                    if (!port_merge_hit[p] &&
                        active_now[p] &&
                        !port_ready_q[p] &&
                        !(port_busy_q[p] && port_wait_mshr_q[p]) &&
                        (mshr_q[i].line_addr[31:CACHE_OFFSET_BITS] == active_addr[p][31:CACHE_OFFSET_BITS])) begin
                        port_merge_hit[p] = 1'b1;
                        port_merge_idx[p] = MSHR_IDX_BITS'(i);
                    end
                end
            end
        end
    end

    assign lookup_hit_way0 = lookup_q.valid && valid_out[0][0] && (tag_out[0] == lookup_q.line_addr[31:9]);
    assign lookup_hit_way1 = lookup_q.valid && valid_out[1][0] && (tag_out[1] == lookup_q.line_addr[31:9]);
    assign lookup_hit_way2 = lookup_q.valid && valid_out[2][0] && (tag_out[2] == lookup_q.line_addr[31:9]);
    assign lookup_hit_way3 = lookup_q.valid && valid_out[3][0] && (tag_out[3] == lookup_q.line_addr[31:9]);

    assign lookup_hit = lookup_hit_way0 || lookup_hit_way1 || lookup_hit_way2 || lookup_hit_way3;
    assign lookup_is_demand = lookup_q.valid && (lookup_q.port_mask != '0);

    always_comb begin
        lookup_hit_way = 2'd0;
        if (lookup_hit_way0) begin
            lookup_hit_way = 2'd0;
        end else if (lookup_hit_way1) begin
            lookup_hit_way = 2'd1;
        end else if (lookup_hit_way2) begin
            lookup_hit_way = 2'd2;
        end else if (lookup_hit_way3) begin
            lookup_hit_way = 2'd3;
        end
    end

    always_comb begin
        lookup_hit_line_data = data_out[0];
        unique case (lookup_hit_way)
            2'd0: lookup_hit_line_data = data_out[0];
            2'd1: lookup_hit_line_data = data_out[1];
            2'd2: lookup_hit_line_data = data_out[2];
            2'd3: lookup_hit_line_data = data_out[3];
            default: lookup_hit_line_data = data_out[0];
        endcase
    end

    always_comb begin
        lookup_way_lru = 2'd0;
        unique casez (lru_out)
            3'b?00: lookup_way_lru = 2'd0;
            3'b?10: lookup_way_lru = 2'd1;
            3'b0?1: lookup_way_lru = 2'd2;
            3'b1?1: lookup_way_lru = 2'd3;
            default: lookup_way_lru = 2'd0;
        endcase
    end

    always_comb begin
        lookup_fill_way = lookup_way_lru;
        if (!valid_out[0][0]) begin
            lookup_fill_way = 2'd0;
        end else if (!valid_out[1][0]) begin
            lookup_fill_way = 2'd1;
        end else if (!valid_out[2][0]) begin
            lookup_fill_way = 2'd2;
        end else if (!valid_out[3][0]) begin
            lookup_fill_way = 2'd3;
        end
    end

    always_comb begin
        port_need_lookup = '0;
        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            if (active_now[p] &&
                !port_ready_q[p] &&
                !(port_busy_q[p] && port_wait_mshr_q[p]) &&
                !lb_hit[p] &&
                !port_merge_hit[p] &&
                !(lookup_q.valid && (lookup_q.line_addr[31:CACHE_OFFSET_BITS] == active_addr[p][31:CACHE_OFFSET_BITS]))) begin
                port_need_lookup[p] = 1'b1;
            end
        end
    end

    always_comb begin
        lookup_issue_valid = 1'b0;
        lookup_issue_addr = 32'b0;
        lookup_issue_port_mask = '0;
        prefetch_issue_allowed =
            prefetch_stream_valid &&
            (PREFETCH_MAX_OUTSTANDING > 0) &&
            (active_prefetch_mshr_cnt < PREFETCH_CNT_W'(PREFETCH_MAX_OUTSTANDING));

        if (!mem_fill_valid) begin
            if (port_need_lookup[0] && port_need_lookup[1] &&
                (active_addr[0][31:CACHE_OFFSET_BITS] == active_addr[1][31:CACHE_OFFSET_BITS])) begin
                lookup_issue_valid = 1'b1;
                lookup_issue_addr = {active_addr[0][31:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}};
                lookup_issue_port_mask = 2'b11;
            end else if (port_need_lookup[0] && port_need_lookup[1]) begin
                lookup_issue_valid = 1'b1;
                if (port0_older_now) begin
                    lookup_issue_addr = {active_addr[0][31:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}};
                    lookup_issue_port_mask = 2'b01;
                end else begin
                    lookup_issue_addr = {active_addr[1][31:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}};
                    lookup_issue_port_mask = 2'b10;
                end
            end else if (port_need_lookup[0]) begin
                lookup_issue_valid = 1'b1;
                lookup_issue_addr = {active_addr[0][31:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}};
                lookup_issue_port_mask = 2'b01;
            end else if (port_need_lookup[1]) begin
                lookup_issue_valid = 1'b1;
                lookup_issue_addr = {active_addr[1][31:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}};
                lookup_issue_port_mask = 2'b10;
            end else if (prefetch_issue_allowed &&
                         !prefetch_merge_hit &&
                         !(lookup_q.valid && (lookup_q.line_addr[31:CACHE_OFFSET_BITS] == prefetch_cursor_q[31:CACHE_OFFSET_BITS]))) begin
                lookup_issue_valid = 1'b1;
                lookup_issue_addr = {prefetch_cursor_q[31:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}};
                lookup_issue_port_mask = '0;
            end
        end
    end

    always_comb begin
        for (integer unsigned i = 0; i < ICACHE_MSHR_ENTRIES; i = i + 1) begin
            mshr_effective_port_mask[i] = mshr_q[i].port_mask;
        end

        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            if (port_merge_hit[p] &&
                active_now[p] &&
                !port_ready_q[p] &&
                !(port_busy_q[p] && port_wait_mshr_q[p])) begin
                mshr_effective_port_mask[port_merge_idx[p]][p] = 1'b1;
            end
        end

        if (lookup_q.valid && !lookup_hit && lookup_miss_merge_hit) begin
            mshr_effective_port_mask[lookup_miss_merge_idx] =
                mshr_effective_port_mask[lookup_miss_merge_idx] | lookup_q.port_mask;
        end
    end

    always_comb begin
        mem_req_pick_valid = 1'b0;
        mem_req_pick_idx = '0;

        if (!mem_fill_valid) begin
            for (integer unsigned i = 0; i < ICACHE_MSHR_ENTRIES; i = i + 1) begin
                if (!mem_req_pick_valid &&
                    mshr_q[i].valid &&
                    !mshr_q[i].sent &&
                    (mshr_effective_port_mask[i] != '0)) begin
                    mem_req_pick_valid = 1'b1;
                    mem_req_pick_idx = MSHR_IDX_BITS'(i);
                end
            end

            for (integer unsigned i = 0; i < ICACHE_MSHR_ENTRIES; i = i + 1) begin
                if (!mem_req_pick_valid &&
                    mshr_q[i].valid &&
                    !mshr_q[i].sent &&
                    (mshr_effective_port_mask[i] == '0)) begin
                    mem_req_pick_valid = 1'b1;
                    mem_req_pick_idx = MSHR_IDX_BITS'(i);
                end
            end
        end
    end

    always_comb begin
        mem_req_valid = mem_req_pick_valid;
        mem_req = '0;

        if (mem_req_pick_valid) begin
            mem_req.src = cache_src_icache;
            mem_req.kind = (mshr_effective_port_mask[mem_req_pick_idx] != '0) ?
                cache_req_demand_read : cache_req_prefetch_read;
            mem_req.line_addr = mshr_q[mem_req_pick_idx].line_addr;
            mem_req.line_wdata = '0;
            mem_req.set_idx = mshr_q[mem_req_pick_idx].set_idx;
            mem_req.fill_way = mshr_q[mem_req_pick_idx].fill_way;
            mem_req.mshr_id = CACHE_MSHR_ID_BITS'(mem_req_pick_idx);
            mem_req.icache_port_mask = mshr_effective_port_mask[mem_req_pick_idx];
            mem_req.critical = (mshr_effective_port_mask[mem_req_pick_idx] != '0);
        end
    end

    assign mem_resp_ready = 1'b1;

    always_comb begin
        port_event_valid = '0;
        mem_fill_wait_mask = '0;
        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            port_event_data[p] = 32'b0;
        end

        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            if (lb_hit[p]) begin
                port_event_valid[p] = 1'b1;
                port_event_data[p] = line_word(lb_hit_line_data[p], active_addr[p]);
            end
        end

        if (lookup_q.valid && lookup_hit) begin
            for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
                if (lookup_q.port_mask[p]) begin
                    port_event_valid[p] = 1'b1;
                    port_event_data[p] = line_word(lookup_hit_line_data, port_addr_q[p]);
                end
            end
        end

        if (mem_fill_valid) begin
            for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
                if (mshr_q[mem_resp_idx].port_mask[p]) begin
                    port_event_valid[p] = 1'b1;
                    port_event_data[p] = line_word(mem_resp.line_data, port_addr_q[p]);
                    mem_fill_wait_mask[p] = 1'b1;
                end
            end
        end
    end

    always_comb begin
        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            port_ready_all_valid[p] = port_ready_q[p] || port_event_valid[p];
            port_ready_all_data[p] = port_ready_q[p] ? port_ready_data_q[p] : port_event_data[p];
        end
    end

    always_comb begin
        port_resp_fire = '0;

        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            port_resp_fire[p] = active_now[p] && port_ready_all_valid[p];
        end
    end

    assign ufp_resp_0 = port_resp_fire[0];
    assign ufp_resp_1 = port_resp_fire[1];
    assign ufp_rdata_0 = port_resp_fire[0] ? port_ready_all_data[0] : 32'b0;
    assign ufp_rdata_1 = port_resp_fire[1] ? port_ready_all_data[1] : 32'b0;

    always_comb begin
        demand_prefetch_valid = 1'b0;
        demand_prefetch_base_addr = 32'b0;
        demand_prefetch_cursor_addr = 32'b0;
        demand_prefetch_target_addr = 32'b0;

        if ((PREFETCH_LINES_AHEAD > 0) && lb_demand_hit_valid) begin
            demand_prefetch_valid = 1'b1;
            demand_prefetch_base_addr = lb_demand_hit_line_addr;
        end

        if ((PREFETCH_LINES_AHEAD > 0) &&
            lookup_q.valid &&
            lookup_hit &&
            lookup_is_demand &&
            (!demand_prefetch_valid ||
             (lookup_q.line_addr[31:CACHE_OFFSET_BITS] >
              demand_prefetch_base_addr[31:CACHE_OFFSET_BITS]))) begin
            demand_prefetch_valid = 1'b1;
            demand_prefetch_base_addr = lookup_q.line_addr;
        end

        if ((PREFETCH_LINES_AHEAD > 0) &&
            lookup_q.valid &&
            !lookup_hit &&
            (lookup_q.port_mask != '0) &&
            (lookup_miss_merge_hit || mshr_has_free) &&
            (!demand_prefetch_valid ||
             (lookup_q.line_addr[31:CACHE_OFFSET_BITS] >
              demand_prefetch_base_addr[31:CACHE_OFFSET_BITS]))) begin
            demand_prefetch_valid = 1'b1;
            demand_prefetch_base_addr = lookup_q.line_addr;
        end

        if ((PREFETCH_LINES_AHEAD > 0) &&
            mem_fill_valid &&
            (mshr_q[mem_resp_idx].port_mask != '0) &&
            (!demand_prefetch_valid ||
             (mem_resp.line_addr[31:CACHE_OFFSET_BITS] >
              demand_prefetch_base_addr[31:CACHE_OFFSET_BITS]))) begin
            demand_prefetch_valid = 1'b1;
            demand_prefetch_base_addr = mem_resp.line_addr;
        end

        if (demand_prefetch_valid) begin
            demand_prefetch_cursor_addr = line_addr_plus(demand_prefetch_base_addr, 27'd1);
            demand_prefetch_target_addr = line_addr_plus(demand_prefetch_base_addr, PREFETCH_LINES_AHEAD_U);
        end
    end

    always_comb begin
        lb_fill_valid = 1'b0;
        lb_fill_tag = '0;
        lb_fill_data = '0;

        if (mem_fill_valid && (mshr_q[mem_resp_idx].port_mask != '0)) begin
            lb_fill_valid = 1'b1;
            lb_fill_tag = mem_resp.line_addr[31:CACHE_OFFSET_BITS];
            lb_fill_data = mem_resp.line_data;
        end else if (lookup_q.valid && lookup_hit && lookup_is_demand) begin
            lb_fill_valid = 1'b1;
            lb_fill_tag = lookup_q.line_addr[31:CACHE_OFFSET_BITS];
            lb_fill_data = lookup_hit_line_data;
        end else if (mem_fill_valid) begin
            lb_fill_valid = 1'b1;
            lb_fill_tag = mem_resp.line_addr[31:CACHE_OFFSET_BITS];
            lb_fill_data = mem_resp.line_data;
        end else if (lookup_q.valid && lookup_hit) begin
            lb_fill_valid = 1'b1;
            lb_fill_tag = lookup_q.line_addr[31:CACHE_OFFSET_BITS];
            lb_fill_data = lookup_hit_line_data;
        end
    end

    assign lb_fill_hit_existing =
        (lb_valid_q[0] && (lb_tag_q[0] == lb_fill_tag)) ||
        (lb_valid_q[1] && (lb_tag_q[1] == lb_fill_tag));

    always_comb begin
        if (lb_valid_q[0] && (lb_tag_q[0] == lb_fill_tag)) begin
            lb_fill_idx = 1'b0;
        end else if (lb_valid_q[1] && (lb_tag_q[1] == lb_fill_tag)) begin
            lb_fill_idx = 1'b1;
        end else if (!lb_valid_q[0]) begin
            lb_fill_idx = 1'b0;
        end else if (!lb_valid_q[1]) begin
            lb_fill_idx = 1'b1;
        end else begin
            lb_fill_idx = lb_replace_q;
        end
    end

    assign lru_hit_update_valid = lookup_q.valid &&
                                  lookup_hit &&
                                  lookup_is_demand &&
                                  !mem_fill_valid &&
                                  !lookup_issue_valid;
    assign lru_hit_update_way = lookup_hit_way;

    always_comb begin
        csb_tag = 4'hF;
        web_tag = 4'hF;
        csb_data = 4'hF;
        web_data = 4'hF;
        csb_v = 4'hF;
        web_v = 4'hF;
        csb_lru = 1'b1;
        web_lru = 1'b1;
        wmask_data = 32'h0;
        set = '0;
        tag_passin = '0;
        data_in = '0;
        lru_in = 3'b000;

        for (integer unsigned j = 0; j < 4; j = j + 1) begin
            valid_in[j] = 1'b0;
        end

        if (mem_fill_valid) begin
            set = mshr_q[mem_resp_idx].set_idx;
            tag_passin = mem_resp.line_addr[31:9];
            data_in = mem_resp.line_data;
            wmask_data = 32'hFFFF_FFFF;

            csb_data[mshr_q[mem_resp_idx].fill_way] = 1'b0;
            web_data[mshr_q[mem_resp_idx].fill_way] = 1'b0;
            csb_tag[mshr_q[mem_resp_idx].fill_way] = 1'b0;
            web_tag[mshr_q[mem_resp_idx].fill_way] = 1'b0;
            csb_v[mshr_q[mem_resp_idx].fill_way] = 1'b0;
            web_v[mshr_q[mem_resp_idx].fill_way] = 1'b0;
            valid_in[mshr_q[mem_resp_idx].fill_way] = 1'b1;

            csb_lru = 1'b0;
            web_lru = 1'b0;
            lru_in = plru_after_access(mshr_q[mem_resp_idx].fill_way);
        end else if (lookup_issue_valid) begin
            set = lookup_issue_addr[8:5];
            csb_tag = 4'h0;
            csb_data = 4'h0;
            csb_v = 4'h0;
            csb_lru = 1'b0;
        end else if (lru_hit_update_valid) begin
            set = lookup_q.line_addr[8:5];
            csb_lru = 1'b0;
            web_lru = 1'b0;
            lru_in = plru_after_access(lru_hit_update_way);
        end
    end

    always_comb begin
        lookup_n = lookup_q;
        prefetch_active_n = prefetch_active_q;
        prefetch_cursor_n = prefetch_cursor_q;
        prefetch_target_n = prefetch_target_q;
        port_busy_n = port_busy_q;
        port_ready_n = port_ready_q;
        port_wait_mshr_n = port_wait_mshr_q;
        port0_older_n = port0_older_q;

        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            port_addr_n[p] = port_addr_q[p];
            port_ready_data_n[p] = port_ready_data_q[p];
            port_mshr_id_n[p] = port_mshr_id_q[p];
        end

        for (integer unsigned i = 0; i < ICACHE_MSHR_ENTRIES; i = i + 1) begin
            mshr_n[i] = mshr_q[i];
        end

        prefetch_advance_now = 1'b0;

        if (new_req[0] && new_req[1]) begin
            port0_older_n = (ufp_addr_0 <= ufp_addr_1);
        end else if (new_req[0] && port_busy_q[1] && !port_resp_fire[1]) begin
            port0_older_n = 1'b0;
        end else if (new_req[1] && port_busy_q[0] && !port_resp_fire[0]) begin
            port0_older_n = 1'b1;
        end

        if (new_req[0]) begin
            port_busy_n[0] = 1'b1;
            port_ready_n[0] = 1'b0;
            port_wait_mshr_n[0] = 1'b0;
            port_addr_n[0] = ufp_addr_0;
            port_mshr_id_n[0] = '0;
        end

        if (new_req[1]) begin
            port_busy_n[1] = 1'b1;
            port_ready_n[1] = 1'b0;
            port_wait_mshr_n[1] = 1'b0;
            port_addr_n[1] = ufp_addr_1;
            port_mshr_id_n[1] = '0;
        end

        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            if (port_merge_hit[p] &&
                active_now[p] &&
                !port_ready_q[p] &&
                !(port_busy_q[p] && port_wait_mshr_q[p])) begin
                mshr_n[port_merge_idx[p]].port_mask[p] = 1'b1;
                port_wait_mshr_n[p] = 1'b1;
                port_mshr_id_n[p] = CACHE_MSHR_ID_BITS'(port_merge_idx[p]);
            end
        end

        if (lookup_q.valid && !lookup_hit) begin
            if (lookup_miss_merge_hit) begin
                mshr_n[lookup_miss_merge_idx].port_mask =
                    mshr_q[lookup_miss_merge_idx].port_mask | lookup_q.port_mask;
                for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
                    if (lookup_q.port_mask[p]) begin
                        port_wait_mshr_n[p] = 1'b1;
                        port_mshr_id_n[p] = CACHE_MSHR_ID_BITS'(lookup_miss_merge_idx);
                    end
                end
            end else if (mshr_has_free) begin
                mshr_n[mshr_free_idx] = '0;
                mshr_n[mshr_free_idx].valid = 1'b1;
                mshr_n[mshr_free_idx].sent = 1'b0;
                mshr_n[mshr_free_idx].line_addr = lookup_q.line_addr;
                mshr_n[mshr_free_idx].set_idx = lookup_q.line_addr[8:5];
                mshr_n[mshr_free_idx].fill_way = lookup_fill_way;
                mshr_n[mshr_free_idx].port_mask = lookup_q.port_mask;

                for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
                    if (lookup_q.port_mask[p]) begin
                        port_wait_mshr_n[p] = 1'b1;
                        port_mshr_id_n[p] = CACHE_MSHR_ID_BITS'(mshr_free_idx);
                    end
                end
            end else if (lookup_q.port_mask == '0) begin
                prefetch_active_n = 1'b1;
                prefetch_cursor_n = lookup_q.line_addr;
            end
        end

        if (prefetch_stream_valid && prefetch_merge_hit) begin
            prefetch_advance_now = 1'b1;
        end

        if ((lookup_q.valid && (lookup_q.port_mask == '0)) &&
            (lookup_hit || lookup_miss_merge_hit || mshr_has_free)) begin
            prefetch_advance_now = 1'b1;
        end

        if (mem_req_pick_valid && mem_req_ready) begin
            mshr_n[mem_req_pick_idx].sent = 1'b1;
        end

        if (mem_fill_valid) begin
            mshr_n[mem_resp_idx] = '0;
        end

        for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
            if (port_resp_fire[p]) begin
                port_busy_n[p] = 1'b0;
                port_ready_n[p] = 1'b0;
                port_wait_mshr_n[p] = 1'b0;
                port_mshr_id_n[p] = '0;
            end else if (port_event_valid[p]) begin
                port_ready_n[p] = 1'b1;
                port_ready_data_n[p] = port_event_data[p];
                if (mem_fill_wait_mask[p]) begin
                    port_wait_mshr_n[p] = 1'b0;
                    port_mshr_id_n[p] = '0;
                end
            end
        end

        if (prefetch_advance_now && prefetch_stream_valid) begin
            // Keep a fixed-width sliding stream window: once one prefetch line is
            // consumed/accepted, move both the next cursor and the far target
            // forward by one line so we can refill the window immediately.
            prefetch_cursor_n = line_addr_plus(prefetch_cursor_q, 27'd1);
            prefetch_target_n = line_addr_plus(prefetch_target_q, 27'd1);
        end

        if (demand_prefetch_valid) begin
            if (!prefetch_active_n ||
                (demand_prefetch_cursor_addr[31:CACHE_OFFSET_BITS] > prefetch_cursor_n[31:CACHE_OFFSET_BITS])) begin
                prefetch_cursor_n = demand_prefetch_cursor_addr;
            end

            if (!prefetch_active_n ||
                (demand_prefetch_target_addr[31:CACHE_OFFSET_BITS] > prefetch_target_n[31:CACHE_OFFSET_BITS])) begin
                prefetch_target_n = demand_prefetch_target_addr;
            end

            prefetch_active_n = 1'b1;
        end

        if (prefetch_active_n &&
            (prefetch_cursor_n[31:CACHE_OFFSET_BITS] > prefetch_target_n[31:CACHE_OFFSET_BITS])) begin
            prefetch_active_n = 1'b0;
        end

        lookup_n.valid = lookup_issue_valid;
        lookup_n.line_addr = lookup_issue_addr;
        lookup_n.port_mask = lookup_issue_port_mask;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            lookup_q <= '0;
            port_busy_q <= '0;
            port_ready_q <= '0;
            port_wait_mshr_q <= '0;
            port0_older_q <= 1'b1;
            prefetch_active_q <= 1'b0;
            prefetch_cursor_q <= 32'b0;
            prefetch_target_q <= 32'b0;
            lb_valid_q <= '0;
            lb_replace_q <= 1'b0;

            for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
                port_addr_q[p] <= 32'b0;
                port_ready_data_q[p] <= 32'b0;
                port_mshr_id_q[p] <= '0;
            end

            for (integer unsigned i = 0; i < STREAM_LB_ENTRIES; i = i + 1) begin
                lb_tag_q[i] <= '0;
                lb_data_q[i] <= '0;
            end

            for (integer unsigned i = 0; i < ICACHE_MSHR_ENTRIES; i = i + 1) begin
                mshr_q[i] <= '0;
            end
        end else begin
            lookup_q <= lookup_n;
            port_busy_q <= port_busy_n;
            port_ready_q <= port_ready_n;
            port_wait_mshr_q <= port_wait_mshr_n;
            port0_older_q <= port0_older_n;
            prefetch_active_q <= prefetch_active_n;
            prefetch_cursor_q <= prefetch_cursor_n;
            prefetch_target_q <= prefetch_target_n;

            for (integer unsigned p = 0; p < ICACHE_PORTS; p = p + 1) begin
                port_addr_q[p] <= port_addr_n[p];
                port_ready_data_q[p] <= port_ready_data_n[p];
                port_mshr_id_q[p] <= port_mshr_id_n[p];
            end

            if (lb_fill_valid) begin
                lb_valid_q[lb_fill_idx] <= 1'b1;
                lb_tag_q[lb_fill_idx] <= lb_fill_tag;
                lb_data_q[lb_fill_idx] <= lb_fill_data;

                if (!lb_fill_hit_existing) begin
                    lb_replace_q <= ~lb_fill_idx;
                end
            end

            for (integer unsigned i = 0; i < ICACHE_MSHR_ENTRIES; i = i + 1) begin
                mshr_q[i] <= mshr_n[i];
            end
        end
    end

endmodule : icache_ooo
