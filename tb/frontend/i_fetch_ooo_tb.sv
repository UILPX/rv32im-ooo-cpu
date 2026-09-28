module i_fetch_ooo_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic        clk;
    logic        rst;
    logic        flush;
    logic [31:0] new_pc;
    logic        bp_update_valid;
    logic [31:0] bp_update_pc;
    logic        bp_update_is_cond_branch;
    logic        bp_update_is_jalr;
    logic        bp_update_is_call;
    logic        bp_update_is_return;
    logic        bp_update_taken;
    logic [31:0] bp_update_target;
    logic [31:0] addr_0;
    logic [3:0]  rmask_0;
    logic [31:0] rdata_0;
    logic        resp_0;
    logic [31:0] addr_1;
    logic [3:0]  rmask_1;
    logic [31:0] rdata_1;
    logic        resp_1;
    logic [1:0]  push_mask;
    fetch_inst_t push_data_0;
    fetch_inst_t push_data_1;
    logic [3:0]  queue_left;

    localparam logic [31:0] RESET_PC    = 32'haaaaa000;
    localparam logic [31:0] BEQ_PLUS_8  = 32'h00000463;
    localparam logic [31:0] NOP         = 32'h00000013;

    i_fetch_ooo #(
        .QUE_DEPTH(8),
        .FETCH_ROB_DEPTH(4),
        .BP_PHT_ENTRIES(8),
        .BP_RAS_ENTRIES(4)
    ) dut (.*);

    always #5ns clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        new_pc = '0;
        bp_update_valid = 1'b0;
        bp_update_pc = '0;
        bp_update_is_cond_branch = 1'b0;
        bp_update_is_jalr = 1'b0;
        bp_update_is_call = 1'b0;
        bp_update_is_return = 1'b0;
        bp_update_taken = 1'b0;
        bp_update_target = '0;
        rdata_0 = '0;
        resp_0 = 1'b0;
        rdata_1 = '0;
        resp_1 = 1'b0;
        queue_left = 4'd8;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        @(negedge clk);
        #1ns;
        if ((addr_0 !== RESET_PC) || (addr_1 !== (RESET_PC + 32'd4)) ||
            (rmask_0 !== 4'hf) || (rmask_1 !== 4'hf)) begin
            $fatal(1, "fetch did not issue the reset-PC instruction pair");
        end

        rdata_0 = BEQ_PLUS_8;
        rdata_1 = NOP;
        resp_0 = 1'b1;
        resp_1 = 1'b1;
        #1ns;

        if (push_mask !== 2'b01 ||
            (push_data_0.pc !== RESET_PC) ||
            (push_data_0.inst !== BEQ_PLUS_8) ||
            (push_data_0.rvfi_order !== 64'd0) ||
            !push_data_0.pred_taken ||
            (push_data_0.pred_pc !== (RESET_PC + 32'd8)) ||
            (push_data_1 !== '0)) begin
            $fatal(1, "fetch did not attach lane-zero prediction metadata");
        end

        @(posedge clk);
        @(negedge clk);
        resp_0 = 1'b0;
        resp_1 = 1'b0;

        @(posedge clk);
        @(negedge clk);
        #1ns;
        if ((addr_0 !== (RESET_PC + 32'd8)) ||
            (addr_1 !== (RESET_PC + 32'd12))) begin
            $fatal(1, "fetch did not redirect requests to the predicted target");
        end

        $display("i_fetch_ooo_tb: PASS");
        $finish;
    end
endmodule : i_fetch_ooo_tb
