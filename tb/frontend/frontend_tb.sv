module frontend_tb #(
    parameter integer unsigned FETCH_WIDTH = 2,
    parameter integer unsigned DISPATCH_WIDTH = 2
);
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
    logic [1:0]  dispatch_valid;
    fetch_inst_t dispatch_data_0;
    fetch_inst_t dispatch_data_1;
    logic [1:0]  dispatch_ready;

    localparam logic [31:0] RESET_PC = 32'haaaaa000;
    localparam logic [31:0] INST_A = 32'h00100013;
    localparam logic [31:0] INST_B = 32'h00200013;
    localparam logic [31:0] INST_C = 32'h00300013;
    localparam logic [31:0] INST_D = 32'h00400013;
    localparam logic [1:0] FETCH_MASK =
        (FETCH_WIDTH == 1) ? 2'b01 : 2'b11;
    localparam logic [1:0] DISPATCH_MASK =
        (DISPATCH_WIDTH == 1) ? 2'b01 : 2'b11;

    frontend #(
        .QUEUE_DEPTH(4),
        .FETCH_ROB_DEPTH(4),
        .FETCH_WIDTH(FETCH_WIDTH),
        .DISPATCH_WIDTH(DISPATCH_WIDTH),
        .BP_PHT_ENTRIES(8),
        .BP_RAS_ENTRIES(4)
    ) dut (.*);

    always #5ns clk = ~clk;

    initial begin
        fetch_inst_t held_0;
        fetch_inst_t held_1;

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
        dispatch_ready = 2'b00;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        @(negedge clk);
        #1ns;
        if ((addr_0 !== RESET_PC) || (rmask_0 !== 4'hf)) begin
            $fatal(1, "lane zero did not issue the reset PC");
        end
        if (FETCH_WIDTH == 1) begin
            if (rmask_1 !== 4'h0) begin
                $fatal(1, "disabled fetch lane one issued a request");
            end
        end else if ((addr_1 !== (RESET_PC + 32'd4)) ||
                     (rmask_1 !== 4'hf)) begin
            $fatal(1, "lane one did not issue the second reset-PC request");
        end

        rdata_0 = INST_A;
        resp_0 = 1'b1;
        if (FETCH_WIDTH > 1) begin
            rdata_1 = INST_B;
            resp_1 = 1'b1;
        end

        @(posedge clk);
        #1ns;
        if ((dispatch_valid !== (FETCH_MASK & DISPATCH_MASK)) ||
            (dispatch_data_0.inst !== INST_A) ||
            (dispatch_data_0.rvfi_order !== 64'd0)) begin
            $fatal(1, "first fetch bundle did not reach the dispatch queue");
        end
        if ((FETCH_WIDTH > 1) && (DISPATCH_WIDTH > 1) &&
            ((dispatch_data_1.inst !== INST_B) ||
             (dispatch_data_1.rvfi_order !== 64'd1))) begin
            $fatal(1, "second lane lost ordering or instruction data");
        end

        held_0 = dispatch_data_0;
        held_1 = dispatch_data_1;
        @(negedge clk);
        resp_0 = 1'b0;
        resp_1 = 1'b0;
        @(posedge clk);
        @(negedge clk);
        #1ns;

        if ((dispatch_data_0 !== held_0) ||
            ((FETCH_WIDTH > 1) && (DISPATCH_WIDTH > 1) &&
             (dispatch_data_1 !== held_1))) begin
            $fatal(1, "dispatch backpressure changed the oldest bundle");
        end

        if (FETCH_WIDTH == 1) begin
            if ((addr_0 !== (RESET_PC + 32'd4)) || (rmask_1 !== 4'h0)) begin
                $fatal(1, "single-wide frontend did not advance by one instruction");
            end
        end else if ((addr_0 !== (RESET_PC + 32'd8)) ||
                     (addr_1 !== (RESET_PC + 32'd12))) begin
            $fatal(1, "dual-wide frontend did not advance by two instructions");
        end

        rdata_0 = INST_C;
        resp_0 = 1'b1;
        if (FETCH_WIDTH > 1) begin
            rdata_1 = INST_D;
            resp_1 = 1'b1;
        end
        @(posedge clk);
        #1ns;

        if ((dispatch_data_0 !== held_0) ||
            ((FETCH_WIDTH > 1) && (DISPATCH_WIDTH > 1) &&
             (dispatch_data_1 !== held_1))) begin
            $fatal(1, "a younger fetch bundle bypassed blocked dispatch data");
        end

        @(negedge clk);
        resp_0 = 1'b0;
        resp_1 = 1'b0;
        dispatch_ready = DISPATCH_MASK;
        @(posedge clk);
        #1ns;
        dispatch_ready = 2'b00;

        if ((dispatch_valid !== DISPATCH_MASK) ||
            (dispatch_data_0.inst !==
             (((FETCH_WIDTH > 1) && (DISPATCH_WIDTH == 1)) ? INST_B : INST_C))) begin
            $fatal(1, "dispatch did not reveal the next buffered bundle");
        end
        if ((DISPATCH_WIDTH > 1) && (dispatch_data_1.inst !== INST_D)) begin
            $fatal(1, "dual dispatch did not preserve the next lane");
        end

        @(negedge clk);
        flush = 1'b1;
        new_pc = 32'h80000000;
        #1ns;
        if (dispatch_valid != 2'b00) begin
            $fatal(1, "flush did not suppress queued dispatch output");
        end
        @(posedge clk);
        #1ns;
        flush = 1'b0;
        if (dispatch_valid != 2'b00) begin
            $fatal(1, "flush did not clear buffered frontend instructions");
        end

        $display("frontend_tb FETCH_WIDTH=%0d DISPATCH_WIDTH=%0d: PASS",
                 FETCH_WIDTH, DISPATCH_WIDTH);
        $finish;
    end

endmodule : frontend_tb
