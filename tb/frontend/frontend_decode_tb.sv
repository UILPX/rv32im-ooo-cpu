module frontend_decode_tb #(
    parameter integer unsigned FETCH_WIDTH = 2,
    parameter integer unsigned DECODE_WIDTH = 2
);
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic flush;
    logic [31:0] new_pc;
    logic bp_update_valid;
    logic [31:0] bp_update_pc;
    logic bp_update_is_cond_branch;
    logic bp_update_is_jalr;
    logic bp_update_is_call;
    logic bp_update_is_return;
    logic bp_update_taken;
    logic [31:0] bp_update_target;
    logic [31:0] addr_0;
    logic [3:0] rmask_0;
    logic [31:0] rdata_0;
    logic resp_0;
    logic [31:0] addr_1;
    logic [3:0] rmask_1;
    logic [31:0] rdata_1;
    logic resp_1;
    logic [1:0] decode_valid;
    decoded_uop_t decode_data_0;
    decoded_uop_t decode_data_1;
    logic [1:0] decode_ready;

    localparam logic [31:0] RESET_PC = 32'haaaa_a000;
    localparam logic [31:0] ADDI_X1 = 32'hff01_0093;
    localparam logic [31:0] MUL_X3 = 32'h0220_81b3;
    localparam logic [1:0] ACTIVE_MASK =
        ((FETCH_WIDTH > 1) && (DECODE_WIDTH > 1)) ? 2'b11 : 2'b01;

    frontend_decode #(
        .QUEUE_DEPTH(4),
        .FETCH_ROB_DEPTH(4),
        .FETCH_WIDTH(FETCH_WIDTH),
        .DECODE_WIDTH(DECODE_WIDTH),
        .BP_PHT_ENTRIES(8),
        .BP_RAS_ENTRIES(4)
    ) dut (.*);

    always #5ns clk = ~clk;

    initial begin
        decoded_uop_t held_0;
        decoded_uop_t held_1;

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
        decode_ready = 2'b00;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        @(negedge clk);
        #1ns;

        if ((addr_0 != RESET_PC) || (rmask_0 != 4'hf)) begin
            $fatal(1, "decoded frontend did not issue the reset PC");
        end
        if ((FETCH_WIDTH > 1) &&
            ((addr_1 != (RESET_PC + 32'd4)) || (rmask_1 != 4'hf))) begin
            $fatal(1, "decoded frontend did not issue lane one");
        end else if ((FETCH_WIDTH == 1) && (rmask_1 != 4'h0)) begin
            $fatal(1, "disabled fetch lane one issued a request");
        end

        rdata_0 = ADDI_X1;
        resp_0 = 1'b1;
        if (FETCH_WIDTH > 1) begin
            rdata_1 = MUL_X3;
            resp_1 = 1'b1;
        end

        @(posedge clk);
        #1ns;
        if ((decode_valid != ACTIVE_MASK) ||
            (decode_data_0.op != OP_ADDI) || decode_data_0.illegal ||
            (decode_data_0.imm != 32'hffff_fff0) ||
            (decode_data_0.fetch.pc != RESET_PC) ||
            (decode_data_0.fetch.rvfi_order != 64'd0)) begin
            $fatal(1, "lane zero was not fetched and decoded correctly");
        end
        if ((ACTIVE_MASK[1]) &&
            ((decode_data_1.op != OP_MUL) || decode_data_1.illegal ||
             (decode_data_1.fetch.pc != (RESET_PC + 32'd4)) ||
             (decode_data_1.fetch.rvfi_order != 64'd1))) begin
            $fatal(1, "lane one was not fetched and decoded correctly");
        end

        held_0 = decode_data_0;
        held_1 = decode_data_1;
        @(negedge clk);
        resp_0 = 1'b0;
        resp_1 = 1'b0;
        @(posedge clk);
        #1ns;
        if ((decode_data_0 != held_0) ||
            (ACTIVE_MASK[1] && (decode_data_1 != held_1))) begin
            $fatal(1, "decode output changed under backpressure");
        end

        @(negedge clk);
        flush = 1'b1;
        new_pc = 32'h8000_0000;
        #1ns;
        if (decode_valid != 2'b00) begin
            $fatal(1, "flush did not suppress decoded output");
        end
        @(posedge clk);
        flush = 1'b0;

        $display("frontend_decode_tb FETCH_WIDTH=%0d DECODE_WIDTH=%0d: PASS",
                 FETCH_WIDTH, DECODE_WIDTH);
        $finish;
    end

endmodule : frontend_decode_tb
