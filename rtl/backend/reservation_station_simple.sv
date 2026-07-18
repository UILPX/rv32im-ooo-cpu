module reservation_station_simple
    import rv32im_types::*;
#(
    parameter integer unsigned DEPTH          = 4,
    parameter integer unsigned DISPATCH_PORTS = 2,
    parameter integer unsigned WB_PORTS       = 2
) (
    input   logic                                               clk,
    input   logic                                               rst,
    input   logic                                               flush,

    input   logic   [DISPATCH_PORTS-1:0]                        select,
    input   logic   [DISPATCH_PORTS-1:0]                        port_bus1_sel,
    input   res_stat_t                                          dispatch_bus [DISPATCH_PORTS],
    output  logic   [DISPATCH_PORTS-1:0]                        port_ready,

    input   wb_bus_t                                            wb_bus [WB_PORTS],

    output  logic                                               issue_valid,
    output  simple_issue_t                                      issue_data,
    input   logic                                               issue_grant
);

    localparam integer unsigned COUNT_WIDTH = $clog2(DEPTH + 1);

    typedef struct packed {
        uop_t                       op;
        logic   [PHYS_REG_BITS-1:0] phy_rd;
        logic   [PHYS_REG_BITS-1:0] phy_rs1;
        logic   [PHYS_REG_BITS-1:0] phy_rs2;
        logic                       ready_1;
        logic                       ready_2;
        logic   [WB_DATA_BITS-1:0]  value_1;
        logic   [WB_DATA_BITS-1:0]  value_2;
    } rs_simple_entry_t;

    rs_simple_entry_t entries_q [DEPTH];
    rs_simple_entry_t entries_d [DEPTH];
    rs_simple_entry_t wb_entries [DEPTH];
    rs_simple_entry_t compact_entries [DEPTH];
    rs_simple_entry_t issue_entry_comb;

    logic valid_q [DEPTH];
    logic valid_d [DEPTH];
    logic wb_valid [DEPTH];
    logic compact_valid [DEPTH];

    logic [COUNT_WIDTH-1:0] count_q, count_d;
    logic [COUNT_WIDTH-1:0] issue_idx_comb;
    logic [COUNT_WIDTH-1:0] compact_count_comb;
    logic [COUNT_WIDTH-1:0] free_slots_comb;
    logic                   issue_fire;

    function automatic rs_simple_entry_t pack_entry(input res_stat_t in);
        rs_simple_entry_t out;
        out.op = in.op;
        out.phy_rd = in.phy_rd;
        out.phy_rs1 = in.phy_rs1;
        out.phy_rs2 = in.phy_rs2;
        out.ready_1 = in.ready_1;
        out.ready_2 = in.ready_2;
        out.value_1 = in.value_1;
        out.value_2 = in.value_2;
        return out;
    endfunction

    function automatic simple_issue_t pack_issue(input rs_simple_entry_t in);
        simple_issue_t out;
        out.op = in.op;
        out.phy_rd = in.phy_rd;
        out.value_1 = in.value_1;
        out.value_2 = in.value_2;
        return out;
    endfunction

    always_comb begin
        for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
            wb_entries[i] = entries_q[i];
            wb_valid[i] = valid_q[i];
            compact_entries[i] = '0;
            compact_valid[i] = 1'b0;
            entries_d[i] = '0;
            valid_d[i] = 1'b0;
        end

        issue_valid = 1'b0;
        issue_fire = 1'b0;
        issue_entry_comb = '0;
        issue_idx_comb = '0;
        compact_count_comb = '0;
        issue_data = '0;
        port_ready = '0;
        count_d = count_q;

        if (flush) begin
            count_d = '0;
        end else begin
            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                if (wb_valid[i]) begin
                    if (!wb_entries[i].ready_1) begin
                        for (integer unsigned j = 0; j < WB_PORTS; j = j + 1) begin
                            if (wb_bus[j].valid && wb_bus[j].phy_rd == wb_entries[i].phy_rs1) begin
                                wb_entries[i].ready_1 = 1'b1;
                                wb_entries[i].value_1 = wb_bus[j].value;
                            end
                        end
                    end

                    if (!wb_entries[i].ready_2) begin
                        for (integer unsigned j = 0; j < WB_PORTS; j = j + 1) begin
                            if (wb_bus[j].valid && wb_bus[j].phy_rd == wb_entries[i].phy_rs2) begin
                                wb_entries[i].ready_2 = 1'b1;
                                wb_entries[i].value_2 = wb_bus[j].value;
                            end
                        end
                    end
                end
            end

            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                if (!issue_valid && valid_q[i] && entries_q[i].ready_1 && entries_q[i].ready_2) begin
                    issue_valid = 1'b1;
                    issue_entry_comb = entries_q[i];
                    issue_idx_comb = COUNT_WIDTH'(i);
                end
            end

            issue_data = pack_issue(issue_entry_comb);
            issue_fire = issue_valid && issue_grant;

            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                if (wb_valid[i] && !(issue_fire && issue_idx_comb == COUNT_WIDTH'(i))) begin
                    compact_entries[compact_count_comb] = wb_entries[i];
                    compact_valid[compact_count_comb] = 1'b1;
                    compact_count_comb = compact_count_comb + COUNT_WIDTH'(1);
                end
            end

            for (integer unsigned i = 0; i < DEPTH; i = i + 1) begin
                if (COUNT_WIDTH'(i) < compact_count_comb) begin
                    entries_d[i] = compact_entries[i];
                    valid_d[i] = compact_valid[i];
                end
            end

            count_d = compact_count_comb;
            free_slots_comb = COUNT_WIDTH'(DEPTH) - compact_count_comb;

            if (free_slots_comb >= COUNT_WIDTH'(1)) begin
                port_ready[0] = 1'b1;
            end

            if (DISPATCH_PORTS > 1 && free_slots_comb >= COUNT_WIDTH'(2)) begin
                port_ready[1] = 1'b1;
            end

            if ((DISPATCH_PORTS > 0) && select[0] && port_ready[0]) begin
                entries_d[count_d] = ((DISPATCH_PORTS > 1) && port_bus1_sel[0])
                                   ? pack_entry(dispatch_bus[1])
                                   : pack_entry(dispatch_bus[0]);
                valid_d[count_d] = 1'b1;

                if (!entries_d[count_d].ready_1) begin
                    for (integer unsigned j = 0; j < WB_PORTS; j = j + 1) begin
                        if (wb_bus[j].valid && wb_bus[j].phy_rd == entries_d[count_d].phy_rs1) begin
                            entries_d[count_d].ready_1 = 1'b1;
                            entries_d[count_d].value_1 = wb_bus[j].value;
                        end
                    end
                end

                if (!entries_d[count_d].ready_2) begin
                    for (integer unsigned j = 0; j < WB_PORTS; j = j + 1) begin
                        if (wb_bus[j].valid && wb_bus[j].phy_rd == entries_d[count_d].phy_rs2) begin
                            entries_d[count_d].ready_2 = 1'b1;
                            entries_d[count_d].value_2 = wb_bus[j].value;
                        end
                    end
                end

                count_d = count_d + COUNT_WIDTH'(1);
            end

            if ((DISPATCH_PORTS > 1) && select[1] && port_ready[1]) begin
                entries_d[count_d] = port_bus1_sel[1]
                                   ? pack_entry(dispatch_bus[1])
                                   : pack_entry(dispatch_bus[0]);
                valid_d[count_d] = 1'b1;

                if (!entries_d[count_d].ready_1) begin
                    for (integer unsigned j = 0; j < WB_PORTS; j = j + 1) begin
                        if (wb_bus[j].valid && wb_bus[j].phy_rd == entries_d[count_d].phy_rs1) begin
                            entries_d[count_d].ready_1 = 1'b1;
                            entries_d[count_d].value_1 = wb_bus[j].value;
                        end
                    end
                end

                if (!entries_d[count_d].ready_2) begin
                    for (integer unsigned j = 0; j < WB_PORTS; j = j + 1) begin
                        if (wb_bus[j].valid && wb_bus[j].phy_rd == entries_d[count_d].phy_rs2) begin
                            entries_d[count_d].ready_2 = 1'b1;
                            entries_d[count_d].value_2 = wb_bus[j].value;
                        end
                    end
                end

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

endmodule : reservation_station_simple
