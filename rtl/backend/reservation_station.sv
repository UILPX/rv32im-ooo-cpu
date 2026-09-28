module reservation_station #(
    parameter integer unsigned DEPTH          = 4,
    parameter integer unsigned DISPATCH_PORTS = 2,
    parameter integer unsigned WB_PORTS       = 2
) (
    input   logic                                               clk,
    input   logic                                               rst,
    input   logic                                               flush,

    input   logic   [DISPATCH_PORTS-1:0]                        select,
    input   logic   [DISPATCH_PORTS-1:0]                        port_bus1_sel,
    input   rv32im_types::res_stat_t                            dispatch_data_0,
    input   rv32im_types::res_stat_t                            dispatch_data_1,
    output  logic   [DISPATCH_PORTS-1:0]                        port_ready,

    input   rv32im_types::wb_bus_t                              wb_bus_0,
    input   rv32im_types::wb_bus_t                              wb_bus_1,

    output  logic                                               issue_valid,
    output  rv32im_types::res_stat_t                            issue_data,
    input   logic                                               issue_grant
);

    typedef rv32im_types::res_stat_t res_stat_t;
    typedef rv32im_types::wb_bus_t   wb_bus_t;

    localparam integer unsigned COUNT_WIDTH =
        (DEPTH < 2) ? 1 : $clog2(DEPTH + 1);
    localparam integer unsigned ENTRY_IDX_WIDTH =
        (DEPTH < 2) ? 1 : $clog2(DEPTH);
    localparam integer unsigned ENTRY_BITS = $bits(issue_data);

    logic [ENTRY_BITS-1:0] entries_q [DEPTH];
    logic [ENTRY_BITS-1:0] entries_d [DEPTH];
    logic [ENTRY_BITS-1:0] woken_entries [DEPTH];
    logic [ENTRY_BITS-1:0] compact_entries [DEPTH];

    logic valid_q [DEPTH];
    logic valid_d [DEPTH];
    logic woken_valid [DEPTH];
    logic compact_valid [DEPTH];

    logic [COUNT_WIDTH-1:0] count_q, count_d;
    logic [COUNT_WIDTH-1:0] issue_idx;
    logic [COUNT_WIDTH-1:0] compact_count;
    logic [COUNT_WIDTH-1:0] free_slots;
    logic                   issue_fire;

    generate
        if ((DEPTH == 0) || (DISPATCH_PORTS == 0) ||
            (DISPATCH_PORTS > 2) || (WB_PORTS == 0)) begin : gen_invalid_parameters
            initial begin
                $error("reservation_station requires DEPTH/WB_PORTS >= 1 and 1 <= DISPATCH_PORTS <= 2");
            end
        end
    endgenerate

    function automatic res_stat_t wake_entry(input res_stat_t entry);
        res_stat_t result;

        result = entry;
        if (!result.ready_1 && wb_bus_0.valid &&
            (wb_bus_0.phy_rd == result.phy_rs1)) begin
            result.ready_1 = 1'b1;
            result.value_1 = wb_bus_0.value;
        end
        if (!result.ready_2 && wb_bus_0.valid &&
            (wb_bus_0.phy_rd == result.phy_rs2)) begin
            result.ready_2 = 1'b1;
            result.value_2 = wb_bus_0.value;
        end

        if ((WB_PORTS > 1) && !result.ready_1 && wb_bus_1.valid &&
            (wb_bus_1.phy_rd == result.phy_rs1)) begin
            result.ready_1 = 1'b1;
            result.value_1 = wb_bus_1.value;
        end
        if ((WB_PORTS > 1) && !result.ready_2 && wb_bus_1.valid &&
            (wb_bus_1.phy_rd == result.phy_rs2)) begin
            result.ready_2 = 1'b1;
            result.value_2 = wb_bus_1.value;
        end

        wake_entry = result;
    endfunction

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic entry_ready(input res_stat_t entry);
        entry_ready = entry.ready_1 && entry.ready_2;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    always_comb begin
        free_slots = COUNT_WIDTH'(DEPTH) - count_q;
        port_ready = '0;

        if (!flush) begin
            port_ready[0] = (free_slots >= COUNT_WIDTH'(1));
            if (DISPATCH_PORTS > 1) begin
                port_ready[1] = (free_slots >= COUNT_WIDTH'(2));
            end
        end
    end

    always_comb begin
        for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
            woken_entries[i] = wake_entry(entries_q[i]);
            woken_valid[i] = valid_q[i];
            compact_entries[i] = '0;
            compact_valid[i] = 1'b0;
            entries_d[i] = '0;
            valid_d[i] = 1'b0;
        end

        issue_valid = 1'b0;
        issue_data = '0;
        issue_idx = '0;
        issue_fire = 1'b0;
        compact_count = '0;
        count_d = count_q;

        if (flush) begin
            count_d = '0;
        end else begin
            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                if (!issue_valid && woken_valid[i] &&
                    entry_ready(woken_entries[i])) begin
                    issue_valid = 1'b1;
                    issue_data = woken_entries[i];
                    issue_idx = COUNT_WIDTH'(i);
                end
            end

            issue_fire = issue_valid && issue_grant;

            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                if (woken_valid[i] &&
                    !(issue_fire && (issue_idx == COUNT_WIDTH'(i)))) begin
                    compact_entries[ENTRY_IDX_WIDTH'(compact_count)] = woken_entries[i];
                    compact_valid[ENTRY_IDX_WIDTH'(compact_count)] = 1'b1;
                    compact_count = compact_count + COUNT_WIDTH'(1);
                end
            end

            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                if (COUNT_WIDTH'(i) < compact_count) begin
                    entries_d[i] = compact_entries[i];
                    valid_d[i] = compact_valid[i];
                end
            end

            count_d = compact_count;

            if (select[0] && port_ready[0]) begin
                entries_d[ENTRY_IDX_WIDTH'(count_d)] =
                    (DISPATCH_PORTS > 1 && port_bus1_sel[0])
                        ? dispatch_data_1 : dispatch_data_0;
                entries_d[ENTRY_IDX_WIDTH'(count_d)] =
                    wake_entry(entries_d[ENTRY_IDX_WIDTH'(count_d)]);
                valid_d[ENTRY_IDX_WIDTH'(count_d)] = 1'b1;
                count_d = count_d + COUNT_WIDTH'(1);
            end

            if ((DISPATCH_PORTS > 1) && select[1] && port_ready[1]) begin
                entries_d[ENTRY_IDX_WIDTH'(count_d)] = port_bus1_sel[1]
                                                     ? dispatch_data_1
                                                     : dispatch_data_0;
                entries_d[ENTRY_IDX_WIDTH'(count_d)] =
                    wake_entry(entries_d[ENTRY_IDX_WIDTH'(count_d)]);
                valid_d[ENTRY_IDX_WIDTH'(count_d)] = 1'b1;
                count_d = count_d + COUNT_WIDTH'(1);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            count_q <= '0;
            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                entries_q[i] <= '0;
                valid_q[i] <= 1'b0;
            end
        end else begin
            count_q <= count_d;
            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                entries_q[i] <= entries_d[i];
                valid_q[i] <= valid_d[i];
            end
        end
    end

endmodule : reservation_station
