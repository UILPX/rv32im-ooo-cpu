module rv32i_cpu_ppa (
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

    output  logic   [63:0]                  perf_cycle_count,
    output  logic   [63:0]                  perf_instret_count,
    output  logic   [63:0]                  perf_branch_count,
    output  logic   [63:0]                  perf_branch_mispredict_count,
    output  logic   [63:0]                  perf_frontend_stall_count,
    output  logic   [63:0]                  perf_rob_full_count,
    output  logic   [63:0]                  perf_rs_full_count
);

    // The functional CPU top exposes the full commit trace. The physical PPA
    // top omits that wide debug-only interface while retaining all counters.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [1:0] retire_valid;
    rv32im_types::rob_commit_t retire_data_0;
    rv32im_types::rob_commit_t retire_data_1;
    /* verilator lint_on UNUSEDSIGNAL */

    rv32i_cpu #(
        .ENABLE_RV32M (1'b0)
    ) cpu (
        .clk,
        .rst,
        .imem_addr_0,
        .imem_rmask_0,
        .imem_rdata_0,
        .imem_resp_0,
        .imem_addr_1,
        .imem_rmask_1,
        .imem_rdata_1,
        .imem_resp_1,
        .dmem_req_valid,
        .dmem_req_ready,
        .dmem_req,
        .dmem_resp_valid,
        .dmem_resp_ready,
        .dmem_resp,
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

endmodule : rv32i_cpu_ppa
