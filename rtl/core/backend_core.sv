module backend_core #(
    parameter integer unsigned NUM_PHYS_REGS        = 64,
    parameter integer unsigned ROB_DEPTH            = 16,
    parameter integer unsigned DISPATCH_BUFFER_DEPTH = 4,
    parameter integer unsigned INT_RS_DEPTH         = 4,
    parameter integer unsigned BRANCH_RS_DEPTH      = 4,
    parameter bit ENABLE_RV32M                      = 1'b1,
    parameter integer unsigned MULDIV_RS_DEPTH      = 4,
    parameter integer unsigned MEMORY_QUEUE_DEPTH   = 4,
    parameter integer unsigned MUL_STAGES           = 2,
    parameter integer unsigned DIV_CYC              = 11
) (
    input   logic                           clk,
    input   logic                           rst,

    input   logic   [1:0]                   decode_valid,
    input   rv32im_types::decoded_uop_t     decode_data_0,
    input   rv32im_types::decoded_uop_t     decode_data_1,
    output  logic   [1:0]                   decode_ready,
    input   logic                           frontend_stall,

    output  logic                           mem_req_valid,
    input   logic                           mem_req_ready,
    output  rv32im_types::dcache_cpu_req_t  mem_req,
    input   logic                           mem_resp_valid,
    output  logic                           mem_resp_ready,
    input   rv32im_types::dcache_cpu_resp_t mem_resp,

    output  logic                           flush,
    output  logic                           redirect_valid,
    output  rv32im_types::xlen_t            redirect_pc,

    output  logic                           bp_update_valid,
    output  rv32im_types::xlen_t            bp_update_pc,
    output  logic                           bp_update_is_cond_branch,
    output  logic                           bp_update_is_jalr,
    output  logic                           bp_update_is_call,
    output  logic                           bp_update_is_return,
    output  logic                           bp_update_taken,
    output  rv32im_types::xlen_t            bp_update_target,

    output  logic                           trap_valid,
    input   logic                           trap_ready,
    output  rv32im_types::exception_cause_t trap_cause,
    output  rv32im_types::xlen_t            trap_pc,

    output  logic   [1:0]                   retire_valid,
    output  rv32im_types::rob_commit_t      retire_data_0,
    output  rv32im_types::rob_commit_t      retire_data_1,

    output  logic   [63:0]                  perf_cycle_count,
    output  logic   [63:0]                  perf_instret_count,
    output  logic   [63:0]                  perf_branch_count,
    output  logic   [63:0]                  perf_branch_mispredict_count,
    output  logic   [63:0]                  perf_frontend_stall_count,
    output  logic   [63:0]                  perf_rob_full_count,
    output  logic   [63:0]                  perf_rs_full_count
);

    localparam integer unsigned ROB_COUNT_WIDTH =
        (ROB_DEPTH <= 1) ? 1 : $clog2(ROB_DEPTH + 1);

    logic [1:0] rename_decode_valid;
    logic [1:0] rename_decode_ready;
    logic [1:0] rename_valid;
    logic [1:0] rename_ready;
    rv32im_types::renamed_uop_t rename_data_0;
    rv32im_types::renamed_uop_t rename_data_1;
    logic [1:0] rename_commit_valid;
    rv32im_types::arch_reg_t rename_commit_arch_rd_0;
    rv32im_types::phys_reg_t rename_commit_new_phys_0;
    rv32im_types::phys_reg_t rename_commit_old_phys_0;
    rv32im_types::arch_reg_t rename_commit_arch_rd_1;
    rv32im_types::phys_reg_t rename_commit_new_phys_1;
    rv32im_types::phys_reg_t rename_commit_old_phys_1;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [rv32im_types::PHYS_REG_BITS:0] free_count;

    logic [1:0] rob_dispatch_valid;
    logic [1:0] rob_dispatch_ready;
    rv32im_types::rob_uop_t rob_dispatch_data_0;
    rv32im_types::rob_uop_t rob_dispatch_data_1;
    rv32im_types::rob_complete_t rob_complete_data_0;
    rv32im_types::rob_complete_t rob_complete_data_1;
    logic [1:0] rob_commit_valid;
    logic [1:0] rob_commit_ready;
    rv32im_types::rob_commit_t rob_commit_data_0;
    rv32im_types::rob_commit_t rob_commit_data_1;
    logic [ROB_COUNT_WIDTH-1:0] rob_count;
    logic rob_head_valid;
    rv32im_types::rob_tag_t rob_head_tag;

    logic [1:0] buffered_dispatch_valid;
    logic [1:0] buffered_dispatch_ready;
    rv32im_types::rob_uop_t buffered_dispatch_data_0;
    rv32im_types::rob_uop_t buffered_dispatch_data_1;
    logic [$clog2(DISPATCH_BUFFER_DEPTH + 1)-1:0] dispatch_buffer_count;
    /* verilator lint_on UNUSEDSIGNAL */

    logic [3:0][rv32im_types::PHYS_REG_BITS-1:0] rf_raddr;
    logic [3:0][rv32im_types::XLEN-1:0] rf_rdata;
    logic [1:0] rf_wen;
    logic [1:0][rv32im_types::PHYS_REG_BITS-1:0] rf_waddr;
    logic [1:0][rv32im_types::XLEN-1:0] rf_wdata;

    rv32im_types::res_stat_t rs_dispatch_data_0;
    rv32im_types::res_stat_t rs_dispatch_data_1;
    logic [1:0] int_port_ready;
    logic [1:0] int_select;
    logic [1:0] int_port_bus1_sel;
    logic [1:0] branch_port_ready;
    logic [1:0] branch_select;
    logic [1:0] branch_port_bus1_sel;
    logic [1:0] muldiv_port_ready;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [1:0] muldiv_select;
    logic [1:0] muldiv_port_bus1_sel;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0] memory_port_ready;
    logic [1:0] memory_select;
    logic [1:0] memory_port_bus1_sel;

    logic int_issue_valid;
    logic int_issue_ready;
    rv32im_types::res_stat_t int_issue_data;
    logic int_rs_issue_valid;
    logic int_rs_issue_grant;
    rv32im_types::res_stat_t int_rs_issue_data;
    logic branch_rs_issue_valid;
    logic branch_rs_issue_grant;
    /* verilator lint_off UNUSEDSIGNAL */
    rv32im_types::res_stat_t branch_rs_issue_data;
    rv32im_types::res_stat_t branch_issue_buffer_data;
    /* verilator lint_on UNUSEDSIGNAL */
    logic branch_issue_valid;
    logic branch_issue_ready;
    rv32im_types::branch_issue_t branch_issue_data;
    rv32im_types::wb_bus_t alu_wb_data;
    rv32im_types::wb_bus_t branch_wb_data;
    rv32im_types::wb_bus_t mul_wb_data;
    rv32im_types::wb_bus_t div_wb_data;
    rv32im_types::wb_bus_t memory_wb_data;
    rv32im_types::wb_bus_t wb_bus_0;
    rv32im_types::wb_bus_t wb_bus_1;
    logic alu_wb_grant;
    logic branch_wb_grant;
    logic alu_result_valid;
    logic branch_result_valid;
    logic mul_result_valid;
    logic div_result_valid;
    rv32im_types::rob_complete_t alu_complete_data;
    rv32im_types::rob_complete_t branch_complete_data;
    rv32im_types::rob_complete_t mul_complete_data;
    rv32im_types::rob_complete_t div_complete_data;
    rv32im_types::rob_complete_t memory_complete_data;
    rv32im_types::rob_complete_t system_complete_data_0;
    rv32im_types::rob_complete_t system_complete_data_1;
    logic system_ready;
    logic memory_wb_grant;
    logic memory_complete_grant;
    /* verilator lint_off UNUSEDSIGNAL */
    logic mul_result_grant;
    logic div_result_grant;
    /* verilator lint_on UNUSEDSIGNAL */
    logic alu_candidate;
    logic branch_candidate;
    logic mul_candidate;
    logic div_candidate;
    logic memory_candidate;
    logic branch_selected;
    logic div_selected;
    logic mul_selected;
    logic alu_selected;
    logic [$clog2(MEMORY_QUEUE_DEPTH + 1)-1:0] memory_queue_count;

    logic branch_retire_0;
    logic branch_retire_1;
    logic mispredict_retire_0;
    logic mispredict_retire_1;
    logic rob_full_event;
    logic rs_full_event;

    assign rename_decode_valid = trap_valid ? 2'b00 : decode_valid;
    assign decode_ready = trap_valid ? 2'b00 : rename_decode_ready;

    rename #(
        .NUM_PHYS_REGS (NUM_PHYS_REGS)
    ) rename_state (
        .clk,
        .rst,
        .flush,
        .decode_valid       (rename_decode_valid),
        .decode_data_0,
        .decode_data_1,
        .decode_ready       (rename_decode_ready),
        .rename_valid,
        .rename_data_0,
        .rename_data_1,
        .rename_ready,
        .commit_valid       (rename_commit_valid),
        .commit_arch_rd_0   (rename_commit_arch_rd_0),
        .commit_new_phys_0  (rename_commit_new_phys_0),
        .commit_old_phys_0  (rename_commit_old_phys_0),
        .commit_arch_rd_1   (rename_commit_arch_rd_1),
        .commit_new_phys_1  (rename_commit_new_phys_1),
        .commit_old_phys_1  (rename_commit_old_phys_1),
        .wb_bus_0,
        .wb_bus_1,
        .free_count
    );

    rob #(
        .DEPTH (ROB_DEPTH)
    ) reorder_buffer (
        .clk,
        .rst,
        .flush,
        .alloc_valid        (rename_valid),
        .alloc_data_0       (rename_data_0),
        .alloc_data_1       (rename_data_1),
        .alloc_ready        (rename_ready),
        .dispatch_valid     (rob_dispatch_valid),
        .dispatch_data_0    (rob_dispatch_data_0),
        .dispatch_data_1    (rob_dispatch_data_1),
        .dispatch_ready     (rob_dispatch_ready),
        .complete_data_0    (rob_complete_data_0),
        .complete_data_1    (rob_complete_data_1),
        .commit_valid       (rob_commit_valid),
        .commit_data_0      (rob_commit_data_0),
        .commit_data_1      (rob_commit_data_1),
        .commit_ready       (rob_commit_ready),
        .head_valid         (rob_head_valid),
        .head_tag           (rob_head_tag),
        .count              (rob_count)
    );

    dispatch_buffer #(
        .DEPTH (DISPATCH_BUFFER_DEPTH)
    ) dispatch_queue (
        .clk,
        .rst,
        .flush,
        .push_valid         (rob_dispatch_valid),
        .push_data_0        (rob_dispatch_data_0),
        .push_data_1        (rob_dispatch_data_1),
        .push_ready         (rob_dispatch_ready),
        .wb_bus_0,
        .wb_bus_1,
        .dispatch_valid     (buffered_dispatch_valid),
        .dispatch_data_0    (buffered_dispatch_data_0),
        .dispatch_data_1    (buffered_dispatch_data_1),
        .dispatch_ready     (buffered_dispatch_ready),
        .count              (dispatch_buffer_count)
    );

    dispatch_router router (
        .flush,
        .dispatch_valid     (buffered_dispatch_valid),
        .dispatch_data_0    (buffered_dispatch_data_0),
        .dispatch_data_1    (buffered_dispatch_data_1),
        .dispatch_ready     (buffered_dispatch_ready),
        .rf_raddr,
        .rf_rdata,
        .rs_data_0          (rs_dispatch_data_0),
        .rs_data_1          (rs_dispatch_data_1),
        .int_port_ready,
        .int_select,
        .int_port_bus1_sel,
        .branch_port_ready,
        .branch_select,
        .branch_port_bus1_sel,
        .muldiv_port_ready,
        .muldiv_select,
        .muldiv_port_bus1_sel,
        .memory_port_ready,
        .memory_select,
        .memory_port_bus1_sel,
        .system_ready,
        .system_complete_data_0,
        .system_complete_data_1
    );

    reservation_station #(
        .DEPTH (INT_RS_DEPTH)
    ) int_station (
        .clk,
        .rst,
        .flush,
        .select             (int_select),
        .port_bus1_sel      (int_port_bus1_sel),
        .dispatch_data_0    (rs_dispatch_data_0),
        .dispatch_data_1    (rs_dispatch_data_1),
        .port_ready         (int_port_ready),
        .wb_bus_0,
        .wb_bus_1,
        .issue_valid        (int_rs_issue_valid),
        .issue_data         (int_rs_issue_data),
        .issue_grant        (int_rs_issue_grant)
    );

    lsu #(
        .DEPTH (MEMORY_QUEUE_DEPTH)
    ) memory_execute (
        .clk,
        .rst,
        .flush,
        .select             (memory_select),
        .port_bus1_sel      (memory_port_bus1_sel),
        .dispatch_data_0    (rs_dispatch_data_0),
        .dispatch_data_1    (rs_dispatch_data_1),
        .port_ready         (memory_port_ready),
        .wb_bus_0,
        .wb_bus_1,
        .rob_head_valid,
        .rob_head_tag,
        .mem_req_valid,
        .mem_req_ready,
        .mem_req,
        .mem_resp_valid,
        .mem_resp_ready,
        .mem_resp,
        .wb_data            (memory_wb_data),
        .wb_grant           (memory_wb_grant),
        .complete_data      (memory_complete_data),
        .complete_grant     (memory_complete_grant),
        .count              (memory_queue_count)
    );

    reservation_station #(
        .DEPTH (BRANCH_RS_DEPTH)
    ) branch_station (
        .clk,
        .rst,
        .flush,
        .select             (branch_select),
        .port_bus1_sel      (branch_port_bus1_sel),
        .dispatch_data_0    (rs_dispatch_data_0),
        .dispatch_data_1    (rs_dispatch_data_1),
        .port_ready         (branch_port_ready),
        .wb_bus_0,
        .wb_bus_1,
        .issue_valid        (branch_rs_issue_valid),
        .issue_data         (branch_rs_issue_data),
        .issue_grant        (branch_rs_issue_grant)
    );

    issue_buffer int_issue_queue (
        .clk,
        .rst,
        .flush,
        .input_valid        (int_rs_issue_valid),
        .input_data         (int_rs_issue_data),
        .input_ready        (int_rs_issue_grant),
        .output_valid       (int_issue_valid),
        .output_data        (int_issue_data),
        .output_ready       (int_issue_ready)
    );

    issue_buffer branch_issue_queue (
        .clk,
        .rst,
        .flush,
        .input_valid        (branch_rs_issue_valid),
        .input_data         (branch_rs_issue_data),
        .input_ready        (branch_rs_issue_grant),
        .output_valid       (branch_issue_valid),
        .output_data        (branch_issue_buffer_data),
        .output_ready       (branch_issue_ready)
    );

    generate
        if (ENABLE_RV32M) begin : gen_rv32m_execute
            logic muldiv_rs_issue_valid;
            logic muldiv_rs_issue_grant;
            rv32im_types::res_stat_t muldiv_rs_issue_data;
            logic muldiv_issue_valid;
            logic muldiv_issue_ready;
            rv32im_types::res_stat_t muldiv_issue_data;

            reservation_station #(
                .DEPTH (MULDIV_RS_DEPTH)
            ) muldiv_station (
                .clk,
                .rst,
                .flush,
                .select             (muldiv_select),
                .port_bus1_sel      (muldiv_port_bus1_sel),
                .dispatch_data_0    (rs_dispatch_data_0),
                .dispatch_data_1    (rs_dispatch_data_1),
                .port_ready         (muldiv_port_ready),
                .wb_bus_0,
                .wb_bus_1,
                .issue_valid        (muldiv_rs_issue_valid),
                .issue_data         (muldiv_rs_issue_data),
                .issue_grant        (muldiv_rs_issue_grant)
            );

            issue_buffer muldiv_issue_queue (
                .clk,
                .rst,
                .flush,
                .input_valid        (muldiv_rs_issue_valid),
                .input_data         (muldiv_rs_issue_data),
                .input_ready        (muldiv_rs_issue_grant),
                .output_valid       (muldiv_issue_valid),
                .output_data        (muldiv_issue_data),
                .output_ready       (muldiv_issue_ready)
            );

            muldiv_exec #(
                .MUL_STAGES (MUL_STAGES),
                .DIV_CYC    (DIV_CYC)
            ) muldiv_execute (
                .clk,
                .rst,
                .flush,
                .issue_valid        (muldiv_issue_valid),
                .issue_data         (muldiv_issue_data),
                .issue_ready        (muldiv_issue_ready),
                .mul_wb_data,
                .mul_result_grant,
                .mul_result_valid,
                .mul_complete_data,
                .div_wb_data,
                .div_result_grant,
                .div_result_valid,
                .div_complete_data
            );
        end else begin : gen_no_rv32m_execute
            assign muldiv_port_ready = 2'b00;
            assign mul_wb_data = '0;
            assign div_wb_data = '0;
            assign mul_result_valid = 1'b0;
            assign div_result_valid = 1'b0;
            assign mul_complete_data = '0;
            assign div_complete_data = '0;
        end
    endgenerate

    always_comb begin
        branch_issue_data = '0;
        branch_issue_data.pc = branch_issue_buffer_data.pc;
        branch_issue_data.imm = branch_issue_buffer_data.imm;
        branch_issue_data.target_pc = branch_issue_buffer_data.pc +
                                      branch_issue_buffer_data.imm;
        branch_issue_data.op = branch_issue_buffer_data.op;
        branch_issue_data.phy_rd = branch_issue_buffer_data.phy_rd;
        branch_issue_data.value_1 = branch_issue_buffer_data.value_1;
        branch_issue_data.value_2 = branch_issue_buffer_data.value_2;
        branch_issue_data.rob_tag = branch_issue_buffer_data.rob_tag;
        branch_issue_data.pred_taken = branch_issue_buffer_data.pred_taken;
        branch_issue_data.pred_pc = branch_issue_buffer_data.pred_taken
                                  ? branch_issue_buffer_data.pred_pc
                                  : (branch_issue_buffer_data.pc + 32'd4);
        branch_issue_data.bp_is_call = branch_issue_buffer_data.bp_is_call;
        branch_issue_data.bp_is_return = branch_issue_buffer_data.bp_is_return;
    end

    alu_exec int_execute (
        .clk,
        .rst,
        .flush,
        .issue_valid        (int_issue_valid),
        .issue_data         (int_issue_data),
        .issue_ready        (int_issue_ready),
        .wb_data            (alu_wb_data),
        .wb_grant           (alu_wb_grant),
        .result_valid       (alu_result_valid),
        .complete_data      (alu_complete_data)
    );

    branch_unit branch_execute (
        .clk,
        .rst,
        .flush,
        .issue_valid        (branch_issue_valid),
        .issue_data         (branch_issue_data),
        .issue_ready        (branch_issue_ready),
        .wb_data            (branch_wb_data),
        .wb_grant           (branch_wb_grant),
        .result_valid       (branch_result_valid),
        .complete_data      (branch_complete_data)
    );

    regfile #(
        .NUM_REGS        (NUM_PHYS_REGS),
        .NUM_READ_PORTS  (4),
        .NUM_WRITE_PORTS (2)
    ) physical_registers (
        .clk,
        .rst,
        .raddr            (rf_raddr),
        .rdata            (rf_rdata),
        .wen              (rf_wen),
        .waddr            (rf_waddr),
        .wdata            (rf_wdata)
    );

    always_comb begin
        alu_candidate = alu_result_valid;
        branch_candidate = branch_result_valid;
        mul_candidate = mul_result_valid;
        div_candidate = div_result_valid;
        memory_candidate = memory_complete_data.valid;

        wb_bus_0 = '0;
        wb_bus_1 = '0;
        rob_complete_data_0 = '0;
        rob_complete_data_1 = '0;
        alu_wb_grant = 1'b0;
        branch_wb_grant = 1'b0;
        memory_wb_grant = 1'b0;
        memory_complete_grant = 1'b0;
        mul_result_grant = 1'b0;
        div_result_grant = 1'b0;
        branch_selected = 1'b0;
        div_selected = 1'b0;
        mul_selected = 1'b0;
        alu_selected = 1'b0;
        // System operations execute only at the ROB head. Keeping the dispatch
        // lane occupied until the LSU drains makes FENCE a real memory-ordering
        // boundary and also prevents younger work from passing a precise trap.
        system_ready = !memory_candidate && !branch_candidate &&
                       !div_candidate && !mul_candidate && !alu_candidate &&
                       (memory_queue_count == '0) && rob_head_valid &&
                       buffered_dispatch_valid[0] &&
                       (buffered_dispatch_data_0.rob_tag == rob_head_tag);

        if (!flush && memory_candidate) begin
            memory_complete_grant = 1'b1;
            memory_wb_grant = memory_wb_data.valid;
            wb_bus_0 = memory_wb_data;
            rob_complete_data_0 = memory_complete_data;
        end else if (!flush && branch_candidate) begin
            branch_selected = 1'b1;
            branch_wb_grant = branch_wb_data.valid;
            wb_bus_0 = branch_wb_data;
            rob_complete_data_0 = branch_complete_data;
        end else if (!flush && div_candidate) begin
            div_selected = 1'b1;
            div_result_grant = 1'b1;
            wb_bus_0 = div_wb_data;
            rob_complete_data_0 = div_complete_data;
        end else if (!flush && mul_candidate) begin
            mul_selected = 1'b1;
            mul_result_grant = 1'b1;
            wb_bus_0 = mul_wb_data;
            rob_complete_data_0 = mul_complete_data;
        end else if (!flush && alu_candidate) begin
            alu_selected = 1'b1;
            alu_wb_grant = alu_wb_data.valid;
            wb_bus_0 = alu_wb_data;
            rob_complete_data_0 = alu_complete_data;
        end

        if (!flush && branch_candidate && !branch_selected) begin
            branch_selected = 1'b1;
            branch_wb_grant = branch_wb_data.valid;
            wb_bus_1 = branch_wb_data;
            rob_complete_data_1 = branch_complete_data;
        end else if (!flush && div_candidate && !div_selected) begin
            div_selected = 1'b1;
            div_result_grant = 1'b1;
            wb_bus_1 = div_wb_data;
            rob_complete_data_1 = div_complete_data;
        end else if (!flush && mul_candidate && !mul_selected) begin
            mul_selected = 1'b1;
            mul_result_grant = 1'b1;
            wb_bus_1 = mul_wb_data;
            rob_complete_data_1 = mul_complete_data;
        end else if (!flush && alu_candidate && !alu_selected) begin
            alu_selected = 1'b1;
            alu_wb_grant = alu_wb_data.valid;
            wb_bus_1 = alu_wb_data;
            rob_complete_data_1 = alu_complete_data;
        end

        if (!flush && system_ready) begin
            rob_complete_data_0 = system_complete_data_0;
            rob_complete_data_1 = system_complete_data_1;
        end

        rf_wen[0] = wb_bus_0.valid;
        rf_wen[1] = wb_bus_1.valid;
        rf_waddr[0] = wb_bus_0.phy_rd;
        rf_waddr[1] = wb_bus_1.phy_rd;
        rf_wdata[0] = wb_bus_0.value;
        rf_wdata[1] = wb_bus_1.value;
    end

    commit_control retirement (
        .clk,
        .rst,
        .rob_commit_valid,
        .rob_commit_data_0,
        .rob_commit_data_1,
        .rob_commit_ready,
        .rename_commit_valid,
        .rename_commit_arch_rd_0,
        .rename_commit_new_phys_0,
        .rename_commit_old_phys_0,
        .rename_commit_arch_rd_1,
        .rename_commit_new_phys_1,
        .rename_commit_old_phys_1,
        .retire_valid,
        .retire_data_0,
        .retire_data_1,
        .flush,
        .redirect_valid,
        .redirect_pc,
        .bp_update_valid,
        .bp_update_pc,
        .bp_update_is_cond_branch,
        .bp_update_is_jalr,
        .bp_update_is_call,
        .bp_update_is_return,
        .bp_update_taken,
        .bp_update_target,
        .trap_valid,
        .trap_ready,
        .trap_cause,
        .trap_pc
    );

    always_comb begin
        branch_retire_0 = retire_valid[0] && retire_data_0.result.branch_valid;
        branch_retire_1 = retire_valid[1] && retire_data_1.result.branch_valid;
        mispredict_retire_0 = branch_retire_0 &&
                              retire_data_0.result.branch_mispredict;
        mispredict_retire_1 = branch_retire_1 &&
                              retire_data_1.result.branch_mispredict;

        rob_full_event = rob_count == ROB_COUNT_WIDTH'(ROB_DEPTH);
        rs_full_event = 1'b0;
        if (!flush && buffered_dispatch_valid[0]) begin
            unique case (buffered_dispatch_data_0.renamed.decoded.fu_class)
                rv32im_types::FU_INT:
                    rs_full_event = !int_port_ready[0];
                rv32im_types::FU_BRANCH:
                    rs_full_event = !branch_port_ready[0];
                rv32im_types::FU_MULDIV:
                    rs_full_event = ENABLE_RV32M && !muldiv_port_ready[0];
                default:
                    rs_full_event = 1'b0;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            perf_cycle_count <= '0;
            perf_instret_count <= '0;
            perf_branch_count <= '0;
            perf_branch_mispredict_count <= '0;
            perf_frontend_stall_count <= '0;
            perf_rob_full_count <= '0;
            perf_rs_full_count <= '0;
        end else if (!trap_valid) begin
            perf_cycle_count <= perf_cycle_count + 64'd1;
            perf_instret_count <= perf_instret_count +
                                  64'(retire_valid[0]) +
                                  64'(retire_valid[1]);
            perf_branch_count <= perf_branch_count +
                                 64'(branch_retire_0) +
                                 64'(branch_retire_1);
            perf_branch_mispredict_count <= perf_branch_mispredict_count +
                                            64'(mispredict_retire_0) +
                                            64'(mispredict_retire_1);
            perf_frontend_stall_count <= perf_frontend_stall_count +
                                         64'(frontend_stall);
            perf_rob_full_count <= perf_rob_full_count + 64'(rob_full_event);
            perf_rs_full_count <= perf_rs_full_count + 64'(rs_full_event);
        end
    end

endmodule : backend_core
