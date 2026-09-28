module lsu #(
    parameter integer unsigned DEPTH = 4,
    parameter integer unsigned COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input   logic                           clk,
    input   logic                           rst,
    input   logic                           flush,

    input   logic   [1:0]                   select,
    input   logic   [1:0]                   port_bus1_sel,
    input   rv32im_types::res_stat_t        dispatch_data_0,
    input   rv32im_types::res_stat_t        dispatch_data_1,
    output  logic   [1:0]                   port_ready,

    input   rv32im_types::wb_bus_t          wb_bus_0,
    input   rv32im_types::wb_bus_t          wb_bus_1,

    input   logic                           rob_head_valid,
    input   rv32im_types::rob_tag_t         rob_head_tag,

    output  logic                           mem_req_valid,
    input   logic                           mem_req_ready,
    output  rv32im_types::dcache_cpu_req_t  mem_req,
    input   logic                           mem_resp_valid,
    output  logic                           mem_resp_ready,
    input   rv32im_types::dcache_cpu_resp_t mem_resp,

    output  rv32im_types::wb_bus_t          wb_data,
    input   logic                           wb_grant,
    output  rv32im_types::rob_complete_t    complete_data,
    input   logic                           complete_grant,

    output  logic   [COUNT_WIDTH-1:0]       count
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_REQ,
        ST_RESP,
        ST_DRAIN
    } state_t;

    typedef struct packed {
        logic                            valid;
        rv32im_types::wb_bus_t           wb;
        rv32im_types::rob_complete_t     complete;
    } result_t;

    localparam integer unsigned PTR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam integer unsigned ENTRY_BITS = $bits(dispatch_data_0);

    logic [ENTRY_BITS-1:0] entries_q [DEPTH];
    logic [ENTRY_BITS-1:0] entries_d [DEPTH];
    logic [PTR_WIDTH-1:0] head_q, head_d;
    logic [PTR_WIDTH-1:0] tail_q, tail_d;
    logic [COUNT_WIDTH-1:0] count_q, count_d;
    state_t state_q, state_d;
    rv32im_types::res_stat_t active_q, active_d;
    rv32im_types::dcache_cpu_req_t req_q, req_d;
    result_t result_q, result_d;

    rv32im_types::res_stat_t head_entry;
    logic [PTR_WIDTH-1:0] tail_second;
    logic [COUNT_WIDTH-1:0] free_slots;
    logic push_0;
    logic push_1;
    logic [1:0] push_count;
    logic pop_head;
    logic result_fire;
    logic [31:0] effective_addr;
    logic [3:0] access_mask;
    logic head_is_load;
    logic head_is_store;
    logic head_misaligned;
    logic response_id_match;
    logic _unused_mem_resp_metadata;

    if (DEPTH < 2) begin : gen_invalid_parameters
        initial $error("lsu requires DEPTH >= 2");
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

    function automatic logic is_load(input rv32im_types::uop_t op);
        is_load = (op >= rv32im_types::OP_LB) &&
                  (op <= rv32im_types::OP_LHU);
    endfunction

    function automatic logic is_store(input rv32im_types::uop_t op);
        is_store = (op >= rv32im_types::OP_SB) &&
                   (op <= rv32im_types::OP_SW);
    endfunction

    function automatic logic [3:0] make_mask(input rv32im_types::uop_t op);
        unique case (op)
            rv32im_types::OP_LB,
            rv32im_types::OP_LBU,
            rv32im_types::OP_SB: make_mask = 4'b0001;
            rv32im_types::OP_LH,
            rv32im_types::OP_LHU,
            rv32im_types::OP_SH: make_mask = 4'b0011;
            default: make_mask = 4'b1111;
        endcase
    endfunction

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic misaligned(
        input rv32im_types::uop_t op,
        input rv32im_types::xlen_t addr
    );
        unique case (op)
            rv32im_types::OP_LH,
            rv32im_types::OP_LHU,
            rv32im_types::OP_SH: misaligned = addr[0];
            rv32im_types::OP_LW,
            rv32im_types::OP_SW: misaligned = |addr[1:0];
            default: misaligned = 1'b0;
        endcase
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic rv32im_types::xlen_t extend_load(
        input rv32im_types::uop_t op,
        input rv32im_types::xlen_t data
    );
        unique case (op)
            rv32im_types::OP_LB:
                extend_load = {{24{data[7]}}, data[7:0]};
            rv32im_types::OP_LH:
                extend_load = {{16{data[15]}}, data[15:0]};
            rv32im_types::OP_LBU:
                extend_load = {24'b0, data[7:0]};
            rv32im_types::OP_LHU:
                extend_load = {16'b0, data[15:0]};
            default: extend_load = data;
        endcase
    endfunction

    function automatic rv32im_types::res_stat_t wake_entry(
        input rv32im_types::res_stat_t entry
    );
        rv32im_types::res_stat_t result;
        begin
            result = entry;
            if (!result.ready_1 && wb_bus_0.valid &&
                (result.phy_rs1 == wb_bus_0.phy_rd)) begin
                result.ready_1 = 1'b1;
                result.value_1 = wb_bus_0.value;
            end
            if (!result.ready_2 && wb_bus_0.valid &&
                (result.phy_rs2 == wb_bus_0.phy_rd)) begin
                result.ready_2 = 1'b1;
                result.value_2 = wb_bus_0.value;
            end
            if (!result.ready_1 && wb_bus_1.valid &&
                (result.phy_rs1 == wb_bus_1.phy_rd)) begin
                result.ready_1 = 1'b1;
                result.value_1 = wb_bus_1.value;
            end
            if (!result.ready_2 && wb_bus_1.valid &&
                (result.phy_rs2 == wb_bus_1.phy_rd)) begin
                result.ready_2 = 1'b1;
                result.value_2 = wb_bus_1.value;
            end
            wake_entry = result;
        end
    endfunction

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic entry_ready(input rv32im_types::res_stat_t entry);
        entry_ready = entry.ready_1 && entry.ready_2;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    always_comb begin
        free_slots = COUNT_WIDTH'(DEPTH) - count_q;
        port_ready = 2'b00;
        if (!flush) begin
            port_ready[0] = free_slots >= COUNT_WIDTH'(1);
            port_ready[1] = free_slots >= COUNT_WIDTH'(2);
        end
    end

    always_comb begin
        response_id_match = mem_resp.id == req_q.id;
        _unused_mem_resp_metadata = &{1'b0, mem_resp.addr,
                                      mem_resp.rmask, mem_resp.wmask};
        for (integer unsigned i = 0; i < DEPTH; i++) begin
            entries_d[i] = wake_entry(entries_q[i]);
        end

        head_d = head_q;
        tail_d = tail_q;
        count_d = count_q;
        state_d = state_q;
        active_d = active_q;
        req_d = req_q;
        result_d = result_q;

        head_entry = entries_d[head_q];
        tail_second = ptr_add(tail_q, 2'd1);
        effective_addr = head_entry.value_1 + head_entry.imm;
        access_mask = make_mask(head_entry.op);
        head_is_load = is_load(head_entry.op);
        head_is_store = is_store(head_entry.op);
        head_misaligned = misaligned(head_entry.op, effective_addr);

        mem_req_valid = 1'b0;
        mem_req = req_q;
        mem_resp_ready = 1'b0;
        pop_head = 1'b0;

        complete_data = result_q.complete;
        complete_data.valid = result_q.valid;
        wb_data = result_q.wb;
        wb_data.valid = result_q.valid && result_q.wb.valid;
        result_fire = result_q.valid && complete_grant &&
                      (!result_q.wb.valid || wb_grant);
        if (result_fire) begin
            result_d = '0;
        end

        unique case (state_q)
            ST_IDLE: begin
                if (!flush && (count_q != '0) && !result_q.valid &&
                    entry_ready(head_entry)) begin
                    if (head_misaligned) begin
                        result_d = '0;
                        result_d.valid = 1'b1;
                        result_d.complete.valid = 1'b1;
                        result_d.complete.rob_tag = head_entry.rob_tag;
                        result_d.complete.mem_valid = 1'b1;
                        result_d.complete.mem_addr = effective_addr;
                        result_d.complete.mem_rmask = head_is_load
                            ? access_mask : 4'b0000;
                        result_d.complete.mem_wmask = head_is_store
                            ? access_mask : 4'b0000;
                        result_d.complete.mem_wdata = head_entry.value_2;
                        result_d.complete.exception_valid = 1'b1;
                        result_d.complete.exception_cause = head_is_load
                            ? rv32im_types::EXC_LOAD_MISALIGNED
                            : rv32im_types::EXC_STORE_MISALIGNED;
                        pop_head = 1'b1;
                    end else if (head_is_load ||
                                 (head_is_store && rob_head_valid &&
                                  (rob_head_tag == head_entry.rob_tag))) begin
                        active_d = head_entry;
                        req_d = '0;
                        req_d.id = head_entry.rob_tag;
                        req_d.addr = effective_addr;
                        req_d.rmask = head_is_load ? access_mask : 4'b0000;
                        req_d.wmask = head_is_store ? access_mask : 4'b0000;
                        req_d.wdata = head_entry.value_2;
                        state_d = ST_REQ;
                    end
                end
            end

            ST_REQ: begin
                mem_req_valid = !flush;
                mem_req = req_q;
                if (mem_req_valid && mem_req_ready) begin
                    state_d = ST_RESP;
                end
            end

            ST_RESP: begin
                mem_resp_ready = !mem_resp_valid || response_id_match;
                if (mem_resp_valid && response_id_match) begin
                    result_d = '0;
                    result_d.valid = 1'b1;
                    result_d.complete.valid = 1'b1;
                    result_d.complete.rob_tag = active_q.rob_tag;
                    result_d.complete.mem_valid = 1'b1;
                    result_d.complete.mem_addr = req_q.addr;
                    result_d.complete.mem_rmask = req_q.rmask;
                    result_d.complete.mem_wmask = req_q.wmask;
                    result_d.complete.mem_rdata = mem_resp.rdata;
                    result_d.complete.mem_wdata = req_q.wdata;
                    if (is_load(active_q.op)) begin
                        result_d.complete.rd_value =
                            extend_load(active_q.op, mem_resp.rdata);
                        result_d.complete.rd_write = active_q.phy_rd != '0;
                        result_d.wb.valid = active_q.phy_rd != '0;
                        result_d.wb.phy_rd = active_q.phy_rd;
                        result_d.wb.value =
                            extend_load(active_q.op, mem_resp.rdata);
                    end
                    state_d = ST_IDLE;
                    pop_head = 1'b1;
                end
            end

            ST_DRAIN: begin
                mem_resp_ready = 1'b1;
                if (mem_resp_valid) begin
                    state_d = ST_IDLE;
                end
            end

            default: state_d = ST_IDLE;
        endcase

        push_0 = select[0] && port_ready[0];
        push_1 = push_0 && select[1] && port_ready[1];
        push_count = 2'(push_0) + 2'(push_1);

        if (push_0) begin
            entries_d[tail_q] = wake_entry(port_bus1_sel[0]
                                           ? dispatch_data_1
                                           : dispatch_data_0);
        end
        if (push_1) begin
            entries_d[tail_second] = wake_entry(port_bus1_sel[1]
                                                ? dispatch_data_1
                                                : dispatch_data_0);
        end

        head_d = ptr_add(head_q, 2'(pop_head));
        tail_d = ptr_add(tail_q, push_count);
        count_d = count_q - COUNT_WIDTH'(pop_head) +
                  COUNT_WIDTH'(push_count);
        count = count_q;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            state_q <= ST_IDLE;
            active_q <= '0;
            req_q <= '0;
            result_q <= '0;
            for (integer unsigned i = 0; i < DEPTH; i++) begin
                entries_q[i] <= '0;
            end
        end else if (flush) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            active_q <= active_d;
            req_q <= req_d;
            result_q <= '0;
            if (((state_q == ST_RESP) || (state_q == ST_DRAIN)) &&
                !mem_resp_valid) begin
                state_q <= ST_DRAIN;
            end else begin
                state_q <= ST_IDLE;
            end
            for (integer unsigned i = 0; i < DEPTH; i++) begin
                entries_q[i] <= '0;
            end
        end else begin
            head_q <= head_d;
            tail_q <= tail_d;
            count_q <= count_d;
            state_q <= state_d;
            active_q <= active_d;
            req_q <= req_d;
            result_q <= result_d;
            for (integer unsigned i = 0; i < DEPTH; i++) begin
                entries_q[i] <= entries_d[i];
            end
        end
    end

endmodule : lsu
