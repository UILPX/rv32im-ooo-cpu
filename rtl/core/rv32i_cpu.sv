module rv32i_cpu #(
    parameter integer unsigned FRONTEND_QUEUE_DEPTH = 8,
    parameter integer unsigned FETCH_ROB_DEPTH = 4,
    parameter integer unsigned FETCH_WIDTH = 2,
    parameter integer unsigned DECODE_WIDTH = 2,
    parameter integer unsigned DECODE_BUFFER_DEPTH = 4,
    parameter bit ENABLE_RV32M = 1'b1,
    parameter logic [31:0] RESET_PC = 32'h0000_1000,
    parameter integer unsigned BP_PHT_ENTRIES = 128,
    parameter integer unsigned BP_RAS_ENTRIES = 4,
    parameter integer unsigned NUM_PHYS_REGS = 64,
    parameter integer unsigned ROB_DEPTH = 16,
    parameter integer unsigned DISPATCH_BUFFER_DEPTH = 4,
    parameter integer unsigned INT_RS_DEPTH = 4,
    parameter integer unsigned BRANCH_RS_DEPTH = 4,
    parameter integer unsigned MULDIV_RS_DEPTH = 4,
    parameter integer unsigned MEMORY_QUEUE_DEPTH = 4,
    parameter integer unsigned MUL_STAGES = 2,
    parameter integer unsigned DIV_CYC = 11
) (
    input   logic                           clk,
    input   logic                           rst,

    output  logic   [31:0]                  imem_addr_0,
    output  logic   [3:0]                   imem_rmask_0,
    input   logic   [31:0]                  imem_rdata_0,
    input   logic                           imem_resp_0,
    output  logic   [31:0]                  imem_addr_1,
    output  logic   [3:0]                   imem_rmask_1,
    input   logic   [31:0]                  imem_rdata_1,
    input   logic                           imem_resp_1,

    output  logic                           dmem_req_valid,
    input   logic                           dmem_req_ready,
    output  rv32im_types::dcache_cpu_req_t  dmem_req,
    input   logic                           dmem_resp_valid,
    output  logic                           dmem_resp_ready,
    input   rv32im_types::dcache_cpu_resp_t dmem_resp,

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

    localparam integer unsigned DECODE_BUFFER_COUNT_WIDTH =
        (DECODE_BUFFER_DEPTH <= 1) ? 1 : $clog2(DECODE_BUFFER_DEPTH + 1);

    logic [1:0] frontend_decode_valid;
    logic [1:0] frontend_decode_ready;
    rv32im_types::decoded_uop_t frontend_decode_data_0;
    rv32im_types::decoded_uop_t frontend_decode_data_1;
    logic [1:0] decode_valid;
    logic [1:0] decode_ready;
    rv32im_types::decoded_uop_t decode_data_0;
    rv32im_types::decoded_uop_t decode_data_1;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [DECODE_BUFFER_COUNT_WIDTH-1:0] decode_buffer_count;
    /* verilator lint_on UNUSEDSIGNAL */
    logic frontend_stall;
    logic flush;
    logic redirect_valid;
    rv32im_types::xlen_t redirect_pc;
    logic bp_update_valid;
    rv32im_types::xlen_t bp_update_pc;
    logic bp_update_is_cond_branch;
    logic bp_update_is_jalr;
    logic bp_update_is_call;
    logic bp_update_is_return;
    logic bp_update_taken;
    rv32im_types::xlen_t bp_update_target;

    frontend_decode #(
        .QUEUE_DEPTH     (FRONTEND_QUEUE_DEPTH),
        .FETCH_ROB_DEPTH (FETCH_ROB_DEPTH),
        .FETCH_WIDTH     (FETCH_WIDTH),
        .DECODE_WIDTH    (DECODE_WIDTH),
        .ENABLE_RV32M    (ENABLE_RV32M),
        .RESET_PC        (RESET_PC),
        .BP_PHT_ENTRIES  (BP_PHT_ENTRIES),
        .BP_RAS_ENTRIES  (BP_RAS_ENTRIES)
    ) frontend (
        .clk,
        .rst,
        .flush,
        .new_pc                      (redirect_pc),
        .bp_update_valid,
        .bp_update_pc,
        .bp_update_is_cond_branch,
        .bp_update_is_jalr,
        .bp_update_is_call,
        .bp_update_is_return,
        .bp_update_taken,
        .bp_update_target,
        .addr_0                      (imem_addr_0),
        .rmask_0                     (imem_rmask_0),
        .rdata_0                     (imem_rdata_0),
        .resp_0                      (imem_resp_0),
        .addr_1                      (imem_addr_1),
        .rmask_1                     (imem_rmask_1),
        .rdata_1                     (imem_rdata_1),
        .resp_1                      (imem_resp_1),
        .decode_valid                (frontend_decode_valid),
        .decode_data_0               (frontend_decode_data_0),
        .decode_data_1               (frontend_decode_data_1),
        .decode_ready                (frontend_decode_ready)
    );

    decode_buffer #(
        .DEPTH        (DECODE_BUFFER_DEPTH),
        .DECODE_WIDTH (DECODE_WIDTH)
    ) decoded_uop_queue (
        .clk,
        .rst,
        .flush,
        .push_valid   (frontend_decode_valid),
        .push_data_0  (frontend_decode_data_0),
        .push_data_1  (frontend_decode_data_1),
        .push_ready   (frontend_decode_ready),
        .decode_valid,
        .decode_data_0,
        .decode_data_1,
        .decode_ready,
        .count        (decode_buffer_count)
    );

    assign frontend_stall = frontend_decode_valid[0] &&
                            !frontend_decode_ready[0];

    backend_core #(
        .NUM_PHYS_REGS         (NUM_PHYS_REGS),
        .ROB_DEPTH             (ROB_DEPTH),
        .DISPATCH_BUFFER_DEPTH (DISPATCH_BUFFER_DEPTH),
        .INT_RS_DEPTH          (INT_RS_DEPTH),
        .BRANCH_RS_DEPTH       (BRANCH_RS_DEPTH),
        .ENABLE_RV32M          (ENABLE_RV32M),
        .MULDIV_RS_DEPTH       (MULDIV_RS_DEPTH),
        .MEMORY_QUEUE_DEPTH    (MEMORY_QUEUE_DEPTH),
        .MUL_STAGES            (MUL_STAGES),
        .DIV_CYC               (DIV_CYC)
    ) backend (
        .clk,
        .rst,
        .decode_valid,
        .decode_data_0,
        .decode_data_1,
        .decode_ready,
        .frontend_stall,
        .mem_req_valid                (dmem_req_valid),
        .mem_req_ready                (dmem_req_ready),
        .mem_req                      (dmem_req),
        .mem_resp_valid               (dmem_resp_valid),
        .mem_resp_ready               (dmem_resp_ready),
        .mem_resp                     (dmem_resp),
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
        .trap_pc,
        .retire_valid,
        .retire_data_0,
        .retire_data_1,
        .perf_cycle_count,
        .perf_instret_count,
        .perf_branch_count,
        .perf_branch_mispredict_count,
        .perf_frontend_stall_count,
        .perf_rob_full_count,
        .perf_rs_full_count
    );

    logic _unused_redirect_valid;
    assign _unused_redirect_valid = redirect_valid;

endmodule : rv32i_cpu
