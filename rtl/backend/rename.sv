module rename #(
    parameter integer unsigned NUM_PHYS_REGS = 64,
    parameter integer unsigned RENAME_WIDTH = 2,
    parameter integer unsigned COMMIT_WIDTH = 2,
    parameter integer unsigned WB_PORTS = 2
) (
    input   logic                           clk,
    input   logic                           rst,
    input   logic                           flush,

    input   logic   [1:0]                   decode_valid,
    input   rv32im_types::decoded_uop_t     decode_data_0,
    input   rv32im_types::decoded_uop_t     decode_data_1,
    output  logic   [1:0]                   decode_ready,

    output  logic   [1:0]                   rename_valid,
    output  rv32im_types::renamed_uop_t     rename_data_0,
    output  rv32im_types::renamed_uop_t     rename_data_1,
    input   logic   [1:0]                   rename_ready,

    input   logic   [1:0]                   commit_valid,
    input   rv32im_types::arch_reg_t        commit_arch_rd_0,
    input   rv32im_types::phys_reg_t        commit_new_phys_0,
    input   rv32im_types::phys_reg_t        commit_old_phys_0,
    input   rv32im_types::arch_reg_t        commit_arch_rd_1,
    input   rv32im_types::phys_reg_t        commit_new_phys_1,
    input   rv32im_types::phys_reg_t        commit_old_phys_1,

    /* verilator lint_off UNUSEDSIGNAL */
    input   rv32im_types::wb_bus_t          wb_bus_0,
    input   rv32im_types::wb_bus_t          wb_bus_1,
    /* verilator lint_on UNUSEDSIGNAL */

    output  logic [rv32im_types::PHYS_REG_BITS:0] free_count
);

    localparam integer unsigned NUM_ARCH_REGS =
        1 << rv32im_types::ARCH_REG_BITS;

    rv32im_types::phys_reg_t rat_q [NUM_ARCH_REGS];
    rv32im_types::phys_reg_t rat_d [NUM_ARCH_REGS];
    rv32im_types::phys_reg_t rrat_q [NUM_ARCH_REGS];
    rv32im_types::phys_reg_t rrat_d [NUM_ARCH_REGS];
    logic [NUM_PHYS_REGS-1:0] free_q, free_d;
    logic [NUM_PHYS_REGS-1:0] ready_q, ready_d;

    rv32im_types::phys_reg_t alloc_phys_0;
    rv32im_types::phys_reg_t alloc_phys_1;
    rv32im_types::phys_reg_t lane_1_alloc_phys;
    logic alloc_found_0;
    logic alloc_found_1;
    logic lane_0_needs_phys;
    logic lane_1_needs_phys;
    logic lane_0_resources;
    logic lane_1_resources;
    logic lane_0_fire;
    logic lane_1_fire;

    if ((NUM_PHYS_REGS <= NUM_ARCH_REGS) ||
        (NUM_PHYS_REGS > (1 << rv32im_types::PHYS_REG_BITS)) ||
        (RENAME_WIDTH < 1) || (RENAME_WIDTH > 2) ||
        (COMMIT_WIDTH < 1) || (COMMIT_WIDTH > 2) ||
        (WB_PORTS < 1) || (WB_PORTS > 2)) begin : gen_invalid_parameters
        initial begin
            $error("rename requires 32 < NUM_PHYS_REGS <= 64 and widths in 1..2");
        end
    end

    always_comb begin
        alloc_phys_0 = '0;
        alloc_phys_1 = '0;
        alloc_found_0 = 1'b0;
        alloc_found_1 = 1'b0;
        free_count = '0;

        for (integer unsigned p = 1; p < NUM_PHYS_REGS; p = p + 1) begin
            if (free_q[p]) begin
                free_count = free_count + 1'b1;
                if (!alloc_found_0) begin
                    alloc_phys_0 = rv32im_types::phys_reg_t'(p);
                    alloc_found_0 = 1'b1;
                end else if (!alloc_found_1) begin
                    alloc_phys_1 = rv32im_types::phys_reg_t'(p);
                    alloc_found_1 = 1'b1;
                end
            end
        end

        lane_0_needs_phys = decode_valid[0] &&
            decode_data_0.writes_rd && (decode_data_0.rd != '0);
        lane_1_needs_phys = (RENAME_WIDTH > 1) && decode_valid[1] &&
            decode_data_1.writes_rd && (decode_data_1.rd != '0);
        lane_1_alloc_phys = lane_0_needs_phys ? alloc_phys_1 : alloc_phys_0;

        lane_0_resources = !lane_0_needs_phys || alloc_found_0;
        lane_1_resources = !lane_1_needs_phys ||
            (lane_0_needs_phys ? alloc_found_1 : alloc_found_0);
    end

    always_comb begin
        rename_data_0 = '0;
        rename_data_1 = '0;
        rename_data_0.decoded = decode_data_0;
        rename_data_1.decoded = decode_data_1;

        if (decode_data_0.uses_rs1 && (decode_data_0.rs1 != '0)) begin
            rename_data_0.phy_rs1 = rat_q[decode_data_0.rs1];
            rename_data_0.ready_rs1 = ready_q[rat_q[decode_data_0.rs1]];
            if (wb_bus_0.valid &&
                (wb_bus_0.phy_rd == rat_q[decode_data_0.rs1])) begin
                rename_data_0.ready_rs1 = 1'b1;
            end
            if ((WB_PORTS > 1) && wb_bus_1.valid &&
                (wb_bus_1.phy_rd == rat_q[decode_data_0.rs1])) begin
                rename_data_0.ready_rs1 = 1'b1;
            end
        end else begin
            rename_data_0.ready_rs1 = 1'b1;
        end

        if (decode_data_0.uses_rs2 && (decode_data_0.rs2 != '0)) begin
            rename_data_0.phy_rs2 = rat_q[decode_data_0.rs2];
            rename_data_0.ready_rs2 = ready_q[rat_q[decode_data_0.rs2]];
            if (wb_bus_0.valid &&
                (wb_bus_0.phy_rd == rat_q[decode_data_0.rs2])) begin
                rename_data_0.ready_rs2 = 1'b1;
            end
            if ((WB_PORTS > 1) && wb_bus_1.valid &&
                (wb_bus_1.phy_rd == rat_q[decode_data_0.rs2])) begin
                rename_data_0.ready_rs2 = 1'b1;
            end
        end else begin
            rename_data_0.ready_rs2 = 1'b1;
        end

        if (lane_0_needs_phys && alloc_found_0) begin
            rename_data_0.allocates_rd = 1'b1;
            rename_data_0.phy_rd = alloc_phys_0;
            rename_data_0.stale_phy_rd = rat_q[decode_data_0.rd];
        end

        if (decode_data_1.uses_rs1 && (decode_data_1.rs1 != '0)) begin
            if (lane_0_needs_phys && alloc_found_0 &&
                (decode_data_1.rs1 == decode_data_0.rd)) begin
                rename_data_1.phy_rs1 = alloc_phys_0;
                rename_data_1.ready_rs1 = 1'b0;
            end else begin
                rename_data_1.phy_rs1 = rat_q[decode_data_1.rs1];
                rename_data_1.ready_rs1 = ready_q[rat_q[decode_data_1.rs1]];
                if (wb_bus_0.valid &&
                    (wb_bus_0.phy_rd == rat_q[decode_data_1.rs1])) begin
                    rename_data_1.ready_rs1 = 1'b1;
                end
                if ((WB_PORTS > 1) && wb_bus_1.valid &&
                    (wb_bus_1.phy_rd == rat_q[decode_data_1.rs1])) begin
                    rename_data_1.ready_rs1 = 1'b1;
                end
            end
        end else begin
            rename_data_1.ready_rs1 = 1'b1;
        end

        if (decode_data_1.uses_rs2 && (decode_data_1.rs2 != '0)) begin
            if (lane_0_needs_phys && alloc_found_0 &&
                (decode_data_1.rs2 == decode_data_0.rd)) begin
                rename_data_1.phy_rs2 = alloc_phys_0;
                rename_data_1.ready_rs2 = 1'b0;
            end else begin
                rename_data_1.phy_rs2 = rat_q[decode_data_1.rs2];
                rename_data_1.ready_rs2 = ready_q[rat_q[decode_data_1.rs2]];
                if (wb_bus_0.valid &&
                    (wb_bus_0.phy_rd == rat_q[decode_data_1.rs2])) begin
                    rename_data_1.ready_rs2 = 1'b1;
                end
                if ((WB_PORTS > 1) && wb_bus_1.valid &&
                    (wb_bus_1.phy_rd == rat_q[decode_data_1.rs2])) begin
                    rename_data_1.ready_rs2 = 1'b1;
                end
            end
        end else begin
            rename_data_1.ready_rs2 = 1'b1;
        end

        if (lane_1_needs_phys && lane_1_resources) begin
            rename_data_1.allocates_rd = 1'b1;
            rename_data_1.phy_rd = lane_1_alloc_phys;
            if (lane_0_needs_phys && alloc_found_0 &&
                (decode_data_1.rd == decode_data_0.rd)) begin
                rename_data_1.stale_phy_rd = alloc_phys_0;
            end else begin
                rename_data_1.stale_phy_rd = rat_q[decode_data_1.rd];
            end
        end
    end

    always_comb begin
        rename_valid = 2'b00;
        decode_ready = 2'b00;

        if (!flush) begin
            rename_valid[0] = decode_valid[0] && lane_0_resources;
            decode_ready[0] = lane_0_resources && rename_ready[0];

            if (RENAME_WIDTH > 1) begin
                rename_valid[1] = decode_valid[0] && decode_valid[1] &&
                    lane_0_resources && lane_1_resources;
                decode_ready[1] = decode_ready[0] && lane_1_resources &&
                    rename_ready[1];
            end
        end

        lane_0_fire = rename_valid[0] && rename_ready[0];
        lane_1_fire = lane_0_fire && rename_valid[1] && rename_ready[1];
    end

    always_comb begin
        for (integer unsigned a = 0; a < NUM_ARCH_REGS; a = a + 1) begin
            rat_d[a] = rat_q[a];
            rrat_d[a] = rrat_q[a];
        end
        free_d = free_q;
        ready_d = ready_q;

        if (flush) begin
            free_d = '1;
            ready_d = '1;
            for (integer unsigned a = 0; a < NUM_ARCH_REGS; a = a + 1) begin
                rat_d[a] = rrat_q[a];
                free_d[rrat_q[a]] = 1'b0;
            end
            free_d[0] = 1'b0;
        end else begin
            if (wb_bus_0.valid && (wb_bus_0.phy_rd != '0)) begin
                ready_d[wb_bus_0.phy_rd] = 1'b1;
            end
            if ((WB_PORTS > 1) && wb_bus_1.valid &&
                (wb_bus_1.phy_rd != '0)) begin
                ready_d[wb_bus_1.phy_rd] = 1'b1;
            end

            if (commit_valid[0] && (commit_arch_rd_0 != '0)) begin
                rrat_d[commit_arch_rd_0] = commit_new_phys_0;
                if (commit_old_phys_0 != '0) begin
                    free_d[commit_old_phys_0] = 1'b1;
                end
                free_d[commit_new_phys_0] = 1'b0;
            end
            if ((COMMIT_WIDTH > 1) && commit_valid[1] &&
                (commit_arch_rd_1 != '0)) begin
                rrat_d[commit_arch_rd_1] = commit_new_phys_1;
                if (commit_old_phys_1 != '0) begin
                    free_d[commit_old_phys_1] = 1'b1;
                end
                free_d[commit_new_phys_1] = 1'b0;
            end

            if (lane_0_fire && rename_data_0.allocates_rd) begin
                rat_d[decode_data_0.rd] = rename_data_0.phy_rd;
                free_d[rename_data_0.phy_rd] = 1'b0;
                ready_d[rename_data_0.phy_rd] = 1'b0;
            end
            if (lane_1_fire && rename_data_1.allocates_rd) begin
                rat_d[decode_data_1.rd] = rename_data_1.phy_rd;
                free_d[rename_data_1.phy_rd] = 1'b0;
                ready_d[rename_data_1.phy_rd] = 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer unsigned a = 0; a < NUM_ARCH_REGS; a = a + 1) begin
                rat_q[a] <= rv32im_types::phys_reg_t'(a);
                rrat_q[a] <= rv32im_types::phys_reg_t'(a);
            end
            for (integer unsigned p = 0; p < NUM_PHYS_REGS; p = p + 1) begin
                free_q[p] <= (p >= NUM_ARCH_REGS);
                ready_q[p] <= 1'b1;
            end
        end else begin
            for (integer unsigned a = 0; a < NUM_ARCH_REGS; a = a + 1) begin
                rat_q[a] <= rat_d[a];
                rrat_q[a] <= rrat_d[a];
            end
            free_q <= free_d;
            ready_q <= ready_d;
        end
    end

endmodule : rename
