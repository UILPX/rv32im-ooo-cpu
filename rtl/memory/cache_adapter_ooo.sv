module cache_adapter_ooo #(
    parameter integer unsigned ICACHE_DEMAND_ENTRIES   = 2,
    parameter integer unsigned ICACHE_PREFETCH_ENTRIES = 2,
    parameter integer unsigned DCACHE_ENTRIES          = 4,
    parameter integer unsigned OUTSTANDING_ENTRIES     = 8
) (
    input   logic               clk,
    input   logic               rst,

    input   logic               ic_req_valid,
    output  logic               ic_req_ready,
    input   rv32im_types::cache_mem_req_t  ic_req,
    output  logic               ic_resp_valid,
    input   logic               ic_resp_ready,
    output  rv32im_types::cache_mem_resp_t ic_resp,

    input   logic               dc_req_valid,
    output  logic               dc_req_ready,
    input   rv32im_types::cache_mem_req_t  dc_req,
    output  logic               dc_resp_valid,
    input   logic               dc_resp_ready,
    output  rv32im_types::cache_mem_resp_t dc_resp,

    output  logic   [31:0]      dram_addr,
    output  logic               dram_read,
    output  logic               dram_write,
    output  logic   [63:0]      dram_wdata,
    input   logic               dram_ready,
    input   logic   [31:0]      dram_raddr,
    input   logic   [63:0]      dram_rdata,
    input   logic               dram_rvalid
);

    localparam integer unsigned CACHE_LINE_BITS = rv32im_types::CACHE_LINE_BITS;
    localparam integer unsigned CACHE_OFFSET_BITS = rv32im_types::CACHE_OFFSET_BITS;
    localparam integer unsigned CACHE_SET_BITS = rv32im_types::CACHE_SET_BITS;
    localparam integer unsigned CACHE_WAY_BITS = rv32im_types::CACHE_WAY_BITS;
    localparam integer unsigned CACHE_MSHR_ID_BITS = rv32im_types::CACHE_MSHR_ID_BITS;
    localparam integer unsigned ICACHE_PORTS = rv32im_types::ICACHE_PORTS;

    localparam rv32im_types::cache_src_t cache_src_icache =
        rv32im_types::cache_src_icache;
    localparam rv32im_types::cache_src_t cache_src_dcache =
        rv32im_types::cache_src_dcache;
    localparam rv32im_types::cache_req_kind_t cache_req_demand_read =
        rv32im_types::cache_req_demand_read;
    localparam rv32im_types::cache_req_kind_t cache_req_prefetch_read =
        rv32im_types::cache_req_prefetch_read;
    localparam rv32im_types::cache_req_kind_t cache_req_writeback =
        rv32im_types::cache_req_writeback;

    localparam integer unsigned ENTRY_IDX_W =
        (OUTSTANDING_ENTRIES < 2) ? 1 : $clog2(OUTSTANDING_ENTRIES);
    localparam integer unsigned ENTRY_COUNT_W =
        (OUTSTANDING_ENTRIES < 2) ? 1 : $clog2(OUTSTANDING_ENTRIES + 1);

    localparam logic [ENTRY_COUNT_W-1:0] ICACHE_DEMAND_LIMIT =
        ENTRY_COUNT_W'(ICACHE_DEMAND_ENTRIES);
    localparam logic [ENTRY_COUNT_W-1:0] ICACHE_PREFETCH_LIMIT =
        ENTRY_COUNT_W'(ICACHE_PREFETCH_ENTRIES);
    localparam logic [ENTRY_COUNT_W-1:0] DCACHE_LIMIT =
        ENTRY_COUNT_W'(DCACHE_ENTRIES);

    typedef enum logic [1:0] {
        SEL_NONE,
        SEL_ICACHE,
        SEL_DCACHE
    } sched_sel_t;

    rv32im_types::cache_adapter_entry_t outstanding_q [OUTSTANDING_ENTRIES];
    rv32im_types::cache_adapter_entry_t outstanding_n [OUTSTANDING_ENTRIES];

    sched_sel_t        sched_sel;
    rv32im_types::cache_mem_req_t selected_req;
    logic              has_free_slot;
    logic              has_merge_hit;
    logic              selected_class_full;
    logic              can_accept_selected;
    logic              accept_selected_req;
    logic              has_ic_complete;
    logic              has_dc_complete;
    logic              issue_valid;
    logic              issue_is_write;
    logic              issue_accept;
    logic              bypass_issue_valid;
    logic              bypass_issue_is_write;
    logic              pop_ic_complete;
    logic              pop_dc_complete;
    logic              write_active_q, write_active_n;
    logic [31:0]       write_addr_q, write_addr_n;
    logic [1:0]        write_beat_q, write_beat_n;
    logic [2:0]        issue_priority;
    logic [63:0]       write_beat_data;
    logic              outstanding_update_en;
    logic              write_state_update_en;

    logic [ENTRY_COUNT_W-1:0] active_ic_demand_count;
    logic [ENTRY_COUNT_W-1:0] active_ic_prefetch_count;
    logic [ENTRY_COUNT_W-1:0] active_dcache_count;
    logic [ENTRY_IDX_W-1:0]   free_idx;
    logic [ENTRY_IDX_W-1:0]   merge_idx;
    logic [ENTRY_IDX_W-1:0]   ic_complete_idx;
    logic [ENTRY_IDX_W-1:0]   dc_complete_idx;
    logic [ENTRY_IDX_W-1:0]   issue_idx;
    logic [ENTRY_IDX_W-1:0]   bypass_issue_idx;
    logic [ENTRY_IDX_W-1:0]   write_slot_q, write_slot_n;
    logic                     _unused_dram_raddr;

    generate
        if ((OUTSTANDING_ENTRIES == 0) || (ICACHE_DEMAND_ENTRIES == 0) ||
            (ICACHE_PREFETCH_ENTRIES == 0) || (DCACHE_ENTRIES == 0) ||
            (ICACHE_DEMAND_ENTRIES > OUTSTANDING_ENTRIES) ||
            (ICACHE_PREFETCH_ENTRIES > OUTSTANDING_ENTRIES) ||
            (DCACHE_ENTRIES > OUTSTANDING_ENTRIES)) begin : gen_invalid_parameters
            initial begin
                $error("cache_adapter_ooo requires nonzero class limits no larger than OUTSTANDING_ENTRIES");
            end
        end
    endgenerate

    assign _unused_dram_raddr = &{1'b0, dram_raddr[4:0]};

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [2:0] source_priority(
        input rv32im_types::cache_src_t      src,
        input rv32im_types::cache_req_kind_t kind,
        input logic            critical
    );
        logic [2:0] prio;

        prio = 3'd0;
        unique case (kind)
            cache_req_writeback:
                prio = (src == cache_src_dcache) ? 3'd6 : 3'd4;
            cache_req_demand_read:
                prio = (src == cache_src_dcache) ? 3'd5 : 3'd3;
            cache_req_prefetch_read:
                prio = 3'd1;
            default:
                prio = 3'd0;
        endcase

        if (critical && (prio < 3'd7)) begin
            prio = prio + 3'd1;
        end

        source_priority = prio;
    endfunction

    function automatic logic [2:0] request_priority(
        input rv32im_types::cache_mem_req_t req
    );
        request_priority = source_priority(req.src, req.kind, req.critical);
    endfunction

    function automatic logic [2:0] entry_priority(
        input rv32im_types::cache_adapter_entry_t entry
    );
        logic [2:0] prio;
        logic [2:0] candidate;

        prio = 3'd0;
        if (entry.ic_wait_valid) begin
            prio = source_priority(cache_src_icache,
                                   entry.ic_kind,
                                   entry.ic_critical);
        end

        if (entry.dc_wait_valid) begin
            candidate = source_priority(
                cache_src_dcache,
                entry.mem_write ? cache_req_writeback : entry.dc_kind,
                entry.dc_critical
            );
            if (candidate > prio) begin
                prio = candidate;
            end
        end

        entry_priority = prio;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [63:0] line_beat(
        input logic [CACHE_LINE_BITS-1:0] line_data,
        input logic [1:0]                 beat_idx
    );
        unique case (beat_idx)
            2'd0: line_beat = line_data[63:0];
            2'd1: line_beat = line_data[127:64];
            2'd2: line_beat = line_data[191:128];
            default: line_beat = line_data[255:192];
        endcase
    endfunction

    always_comb begin
        sched_sel = SEL_NONE;
        selected_req = '0;

        if (dc_req_valid && ic_req_valid) begin
            if (request_priority(dc_req) >= request_priority(ic_req)) begin
                sched_sel = SEL_DCACHE;
                selected_req = dc_req;
            end else begin
                sched_sel = SEL_ICACHE;
                selected_req = ic_req;
            end
        end else if (dc_req_valid) begin
            sched_sel = SEL_DCACHE;
            selected_req = dc_req;
        end else if (ic_req_valid) begin
            sched_sel = SEL_ICACHE;
            selected_req = ic_req;
        end
    end

    always_comb begin
        has_free_slot = 1'b0;
        has_merge_hit = 1'b0;
        selected_class_full = 1'b0;
        free_idx = '0;
        merge_idx = '0;
        active_ic_demand_count = '0;
        active_ic_prefetch_count = '0;
        active_dcache_count = '0;

        for (integer unsigned i = 0; i < OUTSTANDING_ENTRIES; i = i + 1) begin
            if (!has_free_slot && !outstanding_q[i].valid) begin
                has_free_slot = 1'b1;
                free_idx = ENTRY_IDX_W'(i);
            end

            if (outstanding_q[i].valid && outstanding_q[i].ic_wait_valid) begin
                if (outstanding_q[i].ic_kind == cache_req_prefetch_read) begin
                    active_ic_prefetch_count =
                        active_ic_prefetch_count + ENTRY_COUNT_W'(1);
                end else begin
                    active_ic_demand_count =
                        active_ic_demand_count + ENTRY_COUNT_W'(1);
                end
            end

            if (outstanding_q[i].valid && outstanding_q[i].dc_wait_valid) begin
                active_dcache_count = active_dcache_count + ENTRY_COUNT_W'(1);
            end

            if (!has_merge_hit && (sched_sel != SEL_NONE) &&
                (selected_req.kind != cache_req_writeback) &&
                outstanding_q[i].valid && !outstanding_q[i].complete &&
                !outstanding_q[i].mem_write &&
                (outstanding_q[i].line_addr[31:CACHE_OFFSET_BITS] ==
                 selected_req.line_addr[31:CACHE_OFFSET_BITS])) begin
                has_merge_hit = 1'b1;
                merge_idx = ENTRY_IDX_W'(i);
            end
        end

        if (sched_sel == SEL_ICACHE) begin
            selected_class_full = (selected_req.kind == cache_req_prefetch_read)
                                ? (active_ic_prefetch_count >= ICACHE_PREFETCH_LIMIT)
                                : (active_ic_demand_count >= ICACHE_DEMAND_LIMIT);
        end else if (sched_sel == SEL_DCACHE) begin
            selected_class_full = (active_dcache_count >= DCACHE_LIMIT);
        end

        can_accept_selected = (sched_sel != SEL_NONE) &&
                              (has_merge_hit ||
                               (has_free_slot && !selected_class_full));
    end

    always_comb begin
        accept_selected_req = 1'b0;
        ic_req_ready = 1'b0;
        dc_req_ready = 1'b0;

        if (can_accept_selected) begin
            if (sched_sel == SEL_ICACHE) begin
                ic_req_ready = 1'b1;
                accept_selected_req = ic_req_valid;
            end else if (sched_sel == SEL_DCACHE) begin
                dc_req_ready = 1'b1;
                accept_selected_req = dc_req_valid;
            end
        end
    end

    always_comb begin
        has_ic_complete = 1'b0;
        has_dc_complete = 1'b0;
        ic_complete_idx = '0;
        dc_complete_idx = '0;

        for (integer unsigned i = 0; i < OUTSTANDING_ENTRIES; i = i + 1) begin
            if (!has_ic_complete && outstanding_q[i].valid &&
                outstanding_q[i].complete && outstanding_q[i].ic_wait_valid) begin
                has_ic_complete = 1'b1;
                ic_complete_idx = ENTRY_IDX_W'(i);
            end

            if (!has_dc_complete && outstanding_q[i].valid &&
                outstanding_q[i].complete && outstanding_q[i].dc_wait_valid) begin
                has_dc_complete = 1'b1;
                dc_complete_idx = ENTRY_IDX_W'(i);
            end
        end
    end

    always_comb begin
        issue_valid = 1'b0;
        issue_is_write = 1'b0;
        issue_idx = '0;
        issue_priority = '0;

        if (!write_active_q) begin
            for (integer unsigned i = 0; i < OUTSTANDING_ENTRIES; i = i + 1) begin
                if (outstanding_q[i].valid && !outstanding_q[i].issued &&
                    !outstanding_q[i].complete &&
                    (!issue_valid ||
                     (entry_priority(outstanding_q[i]) > issue_priority))) begin
                    issue_valid = 1'b1;
                    issue_idx = ENTRY_IDX_W'(i);
                    issue_priority = entry_priority(outstanding_q[i]);
                    issue_is_write = outstanding_q[i].mem_write;
                end
            end
        end
    end

    always_comb begin
        bypass_issue_valid = !write_active_q && accept_selected_req &&
                             !has_merge_hit &&
                             (!issue_valid ||
                              (request_priority(selected_req) > issue_priority));
        bypass_issue_is_write =
            bypass_issue_valid && (selected_req.kind == cache_req_writeback);
        bypass_issue_idx = free_idx;
    end

    always_comb begin
        ic_resp_valid = has_ic_complete;
        dc_resp_valid = has_dc_complete;
        ic_resp = '0;
        dc_resp = '0;

        if (has_ic_complete) begin
            ic_resp.src = cache_src_icache;
            ic_resp.mshr_id = outstanding_q[ic_complete_idx].ic_mshr_id;
            ic_resp.line_addr = outstanding_q[ic_complete_idx].line_addr;
            ic_resp.line_data = outstanding_q[ic_complete_idx].line_data;
        end

        if (has_dc_complete) begin
            dc_resp.src = cache_src_dcache;
            dc_resp.mshr_id = outstanding_q[dc_complete_idx].dc_mshr_id;
            dc_resp.line_addr = outstanding_q[dc_complete_idx].line_addr;
            dc_resp.line_data = outstanding_q[dc_complete_idx].line_data;
        end

        dram_addr = '0;
        dram_read = 1'b0;
        dram_write = 1'b0;
        dram_wdata = '0;
        write_beat_data = '0;
        issue_accept = 1'b0;

        if (write_active_q) begin
            write_beat_data = line_beat(
                outstanding_q[write_slot_q].line_data, write_beat_q);
            dram_addr = write_addr_q;
            dram_write = (write_beat_q == 2'd0) ? dram_ready : 1'b1;
            dram_wdata = write_beat_data;
            issue_accept = (write_beat_q == 2'd0) ? dram_ready : 1'b1;
        end else if (bypass_issue_valid) begin
            if (bypass_issue_is_write) begin
                issue_accept = 1'b1;
            end else begin
                dram_addr = selected_req.line_addr;
                dram_read = dram_ready;
                issue_accept = dram_ready;
            end
        end else if (issue_valid) begin
            if (issue_is_write) begin
                issue_accept = 1'b1;
            end else begin
                dram_addr = outstanding_q[issue_idx].line_addr;
                dram_read = dram_ready;
                issue_accept = dram_ready;
            end
        end

        pop_ic_complete = has_ic_complete && ic_resp_ready;
        pop_dc_complete = has_dc_complete && dc_resp_ready;
    end

    always_comb begin
        write_active_n = write_active_q;
        write_slot_n = write_slot_q;
        write_beat_n = write_beat_q;
        write_addr_n = write_addr_q;

        for (integer unsigned i = 0; i < OUTSTANDING_ENTRIES; i = i + 1) begin
            outstanding_n[i] = outstanding_q[i];
        end

        if (pop_ic_complete) begin
            outstanding_n[ic_complete_idx].ic_wait_valid = 1'b0;
            outstanding_n[ic_complete_idx].ic_port_mask = '0;
            outstanding_n[ic_complete_idx].ic_critical = 1'b0;
        end

        if (pop_dc_complete) begin
            outstanding_n[dc_complete_idx].dc_wait_valid = 1'b0;
            outstanding_n[dc_complete_idx].dc_critical = 1'b0;
        end

        if (accept_selected_req) begin
            if (has_merge_hit) begin
                if (selected_req.src == cache_src_icache) begin
                    outstanding_n[merge_idx].ic_wait_valid = 1'b1;
                    outstanding_n[merge_idx].ic_port_mask =
                        outstanding_q[merge_idx].ic_port_mask |
                        selected_req.icache_port_mask;
                    outstanding_n[merge_idx].ic_critical =
                        outstanding_q[merge_idx].ic_critical |
                        selected_req.critical;

                    if (!outstanding_q[merge_idx].ic_wait_valid ||
                        ((outstanding_q[merge_idx].ic_kind == cache_req_prefetch_read) &&
                         (selected_req.kind != cache_req_prefetch_read))) begin
                        outstanding_n[merge_idx].ic_kind = selected_req.kind;
                        outstanding_n[merge_idx].ic_set_idx = selected_req.set_idx;
                        outstanding_n[merge_idx].ic_fill_way = selected_req.fill_way;
                        outstanding_n[merge_idx].ic_mshr_id = selected_req.mshr_id;
                    end
                end else begin
                    outstanding_n[merge_idx].dc_wait_valid = 1'b1;
                    outstanding_n[merge_idx].dc_critical =
                        outstanding_q[merge_idx].dc_critical |
                        selected_req.critical;

                    if (!outstanding_q[merge_idx].dc_wait_valid ||
                        ((outstanding_q[merge_idx].dc_kind == cache_req_prefetch_read) &&
                         (selected_req.kind != cache_req_prefetch_read))) begin
                        outstanding_n[merge_idx].dc_kind = selected_req.kind;
                        outstanding_n[merge_idx].dc_set_idx = selected_req.set_idx;
                        outstanding_n[merge_idx].dc_fill_way = selected_req.fill_way;
                        outstanding_n[merge_idx].dc_mshr_id = selected_req.mshr_id;
                    end
                end
            end else begin
                outstanding_n[free_idx] = '0;
                outstanding_n[free_idx].valid = 1'b1;
                outstanding_n[free_idx].mem_write =
                    (selected_req.kind == cache_req_writeback);
                outstanding_n[free_idx].line_addr = selected_req.line_addr;
                outstanding_n[free_idx].line_data =
                    (selected_req.kind == cache_req_writeback)
                        ? selected_req.line_wdata : '0;

                if (selected_req.src == cache_src_icache) begin
                    outstanding_n[free_idx].ic_wait_valid = 1'b1;
                    outstanding_n[free_idx].ic_kind = selected_req.kind;
                    outstanding_n[free_idx].ic_set_idx = selected_req.set_idx;
                    outstanding_n[free_idx].ic_fill_way = selected_req.fill_way;
                    outstanding_n[free_idx].ic_mshr_id = selected_req.mshr_id;
                    outstanding_n[free_idx].ic_port_mask =
                        selected_req.icache_port_mask;
                    outstanding_n[free_idx].ic_critical = selected_req.critical;
                end else begin
                    outstanding_n[free_idx].dc_wait_valid = 1'b1;
                    outstanding_n[free_idx].dc_kind = selected_req.kind;
                    outstanding_n[free_idx].dc_set_idx = selected_req.set_idx;
                    outstanding_n[free_idx].dc_fill_way = selected_req.fill_way;
                    outstanding_n[free_idx].dc_mshr_id = selected_req.mshr_id;
                    outstanding_n[free_idx].dc_critical = selected_req.critical;
                end
            end
        end

        if (!write_active_q && bypass_issue_valid && issue_accept) begin
            outstanding_n[bypass_issue_idx].issued = 1'b1;
            if (bypass_issue_is_write) begin
                write_active_n = 1'b1;
                write_slot_n = bypass_issue_idx;
                write_beat_n = '0;
                write_addr_n = selected_req.line_addr;
            end
        end else if (!write_active_q && issue_valid && issue_accept) begin
            outstanding_n[issue_idx].issued = 1'b1;
            if (issue_is_write) begin
                write_active_n = 1'b1;
                write_slot_n = issue_idx;
                write_beat_n = '0;
                write_addr_n = outstanding_q[issue_idx].line_addr;
            end
        end else if (write_active_q && issue_accept) begin
            if (write_beat_q == 2'd3) begin
                write_active_n = 1'b0;
                write_beat_n = '0;
                outstanding_n[write_slot_q].issued = 1'b0;
                outstanding_n[write_slot_q].complete = 1'b1;
            end else begin
                write_beat_n = write_beat_q + 2'd1;
            end
        end

        if (dram_rvalid) begin
            for (integer unsigned i = 0; i < OUTSTANDING_ENTRIES; i = i + 1) begin
                if (outstanding_q[i].valid && outstanding_q[i].issued &&
                    !outstanding_q[i].complete && !outstanding_q[i].mem_write &&
                    (outstanding_q[i].line_addr[31:CACHE_OFFSET_BITS] ==
                     dram_raddr[31:CACHE_OFFSET_BITS])) begin
                    unique case (outstanding_q[i].burst_count)
                        2'd0: outstanding_n[i].line_data[63:0] = dram_rdata;
                        2'd1: outstanding_n[i].line_data[127:64] = dram_rdata;
                        2'd2: outstanding_n[i].line_data[191:128] = dram_rdata;
                        default: outstanding_n[i].line_data[255:192] = dram_rdata;
                    endcase

                    if (outstanding_q[i].burst_count == 2'd3) begin
                        outstanding_n[i].burst_count = '0;
                        outstanding_n[i].issued = 1'b0;
                        outstanding_n[i].complete = 1'b1;
                    end else begin
                        outstanding_n[i].burst_count =
                            outstanding_q[i].burst_count + 2'd1;
                    end
                end
            end
        end

        for (integer unsigned i = 0; i < OUTSTANDING_ENTRIES; i = i + 1) begin
            if (outstanding_n[i].valid && outstanding_n[i].complete &&
                !outstanding_n[i].ic_wait_valid &&
                !outstanding_n[i].dc_wait_valid) begin
                outstanding_n[i] = '0;
            end
        end
    end

    assign outstanding_update_en = pop_ic_complete || pop_dc_complete ||
                                   accept_selected_req ||
                                   (!write_active_q && bypass_issue_valid && issue_accept) ||
                                   (!write_active_q && issue_valid && issue_accept) ||
                                   (write_active_q && issue_accept) || dram_rvalid;
    assign write_state_update_en = write_active_q ||
                                   (!write_active_q && bypass_issue_valid &&
                                    issue_accept && bypass_issue_is_write) ||
                                   (!write_active_q && issue_valid &&
                                    issue_accept && issue_is_write);

    always_ff @(posedge clk) begin
        if (rst) begin
            write_active_q <= 1'b0;
            write_slot_q <= '0;
            write_beat_q <= '0;
            write_addr_q <= '0;
            for (integer unsigned i = 0; i < OUTSTANDING_ENTRIES; i = i + 1) begin
                outstanding_q[i] <= '0;
            end
        end else begin
            if (write_state_update_en) begin
                write_active_q <= write_active_n;
                write_slot_q <= write_slot_n;
                write_beat_q <= write_beat_n;
                write_addr_q <= write_addr_n;
            end

            if (outstanding_update_en) begin
                for (integer unsigned i = 0; i < OUTSTANDING_ENTRIES; i = i + 1) begin
                    outstanding_q[i] <= outstanding_n[i];
                end
            end
        end
    end

endmodule : cache_adapter_ooo
