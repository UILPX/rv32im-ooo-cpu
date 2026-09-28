module frontend #(
    parameter integer unsigned QUEUE_DEPTH = 8,
    parameter integer unsigned FETCH_ROB_DEPTH = 4,
    parameter integer unsigned FETCH_WIDTH = 2,
    parameter integer unsigned DISPATCH_WIDTH = 2,
    parameter logic [31:0] RESET_PC = 32'hAAAAA000,
    parameter integer unsigned BP_PHT_ENTRIES = 128,
    parameter integer unsigned BP_RAS_ENTRIES = 4
) (
    input   logic           clk,
    input   logic           rst,

    input   logic           flush,
    input   logic   [31:0]  new_pc,

    input   logic           bp_update_valid,
    input   logic   [31:0]  bp_update_pc,
    input   logic           bp_update_is_cond_branch,
    input   logic           bp_update_is_jalr,
    input   logic           bp_update_is_call,
    input   logic           bp_update_is_return,
    input   logic           bp_update_taken,
    input   logic   [31:0]  bp_update_target,

    output  logic   [31:0]  addr_0,
    output  logic   [3:0]   rmask_0,
    input   logic   [31:0]  rdata_0,
    input   logic           resp_0,

    output  logic   [31:0]  addr_1,
    output  logic   [3:0]   rmask_1,
    input   logic   [31:0]  rdata_1,
    input   logic           resp_1,

    output  logic   [1:0]   dispatch_valid,
    output  rv32im_types::fetch_inst_t dispatch_data_0,
    output  rv32im_types::fetch_inst_t dispatch_data_1,
    input   logic   [1:0]   dispatch_ready
);

    localparam integer unsigned QUEUE_COUNT_WIDTH =
        (QUEUE_DEPTH <= 1) ? 1 : $clog2(QUEUE_DEPTH + 1);

    logic [1:0] push_mask;
    rv32im_types::fetch_inst_t push_data_0;
    rv32im_types::fetch_inst_t push_data_1;
    logic [QUEUE_COUNT_WIDTH-1:0] queue_slots;

    i_fetch_ooo #(
        .QUE_DEPTH          (QUEUE_DEPTH),
        .FETCH_ROB_DEPTH    (FETCH_ROB_DEPTH),
        .FETCH_WIDTH        (FETCH_WIDTH),
        .QUEUE_COUNT_WIDTH  (QUEUE_COUNT_WIDTH),
        .RESET_PC           (RESET_PC),
        .BP_PHT_ENTRIES     (BP_PHT_ENTRIES),
        .BP_RAS_ENTRIES     (BP_RAS_ENTRIES)
    ) fetch (
        .clk,
        .rst,
        .flush,
        .new_pc,
        .bp_update_valid,
        .bp_update_pc,
        .bp_update_is_cond_branch,
        .bp_update_is_jalr,
        .bp_update_is_call,
        .bp_update_is_return,
        .bp_update_taken,
        .bp_update_target,
        .addr_0,
        .rmask_0,
        .rdata_0,
        .resp_0,
        .addr_1,
        .rmask_1,
        .rdata_1,
        .resp_1,
        .push_mask,
        .push_data_0,
        .push_data_1,
        .queue_left (queue_slots)
    );

    fetch_queue #(
        .DEPTH           (QUEUE_DEPTH),
        .DISPATCH_WIDTH  (DISPATCH_WIDTH),
        .COUNT_WIDTH     (QUEUE_COUNT_WIDTH)
    ) queue (
        .clk,
        .rst,
        .flush,
        .push_mask,
        .push_data_0,
        .push_data_1,
        .slots_available (queue_slots),
        .dispatch_valid,
        .dispatch_data_0,
        .dispatch_data_1,
        .dispatch_ready
    );

endmodule : frontend
