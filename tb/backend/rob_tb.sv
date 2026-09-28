module rob_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic flush;
    logic [1:0] alloc_valid;
    renamed_uop_t alloc_data_0;
    renamed_uop_t alloc_data_1;
    logic [1:0] alloc_ready;
    logic [1:0] dispatch_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    rob_uop_t dispatch_data_0;
    rob_uop_t dispatch_data_1;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0] dispatch_ready;
    rob_complete_t complete_data_0;
    rob_complete_t complete_data_1;
    logic [1:0] commit_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    rob_commit_t commit_data_0;
    rob_commit_t commit_data_1;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0] commit_ready;
    logic head_valid;
    rob_tag_t head_tag;
    logic [2:0] count;

    rob #(.DEPTH(4)) dut (.*);

    always #5ns clk = ~clk;

    function automatic renamed_uop_t make_uop(
        input logic [63:0] order,
        input arch_reg_t rd,
        input phys_reg_t new_phys,
        input phys_reg_t old_phys,
        input logic illegal
    );
        renamed_uop_t result;
        result = '0;
        result.decoded.fetch.rvfi_order = order;
        result.decoded.op = illegal ? OP_INVALID : OP_ADDI;
        result.decoded.fu_class = illegal ? FU_INVALID : FU_INT;
        result.decoded.rd = rd;
        result.decoded.writes_rd = (rd != '0);
        result.decoded.illegal = illegal;
        result.allocates_rd = (rd != '0);
        result.phy_rd = new_phys;
        result.stale_phy_rd = old_phys;
        result.ready_rs1 = 1'b1;
        result.ready_rs2 = 1'b1;
        make_uop = result;
    endfunction

    task automatic clear_events;
        alloc_valid = 2'b00;
        alloc_data_0 = '0;
        alloc_data_1 = '0;
        complete_data_0 = '0;
        complete_data_1 = '0;
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        dispatch_ready = 2'b00;
        commit_ready = 2'b00;
        clear_events();

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        alloc_data_0 = make_uop(64'd10, 5'd1, 6'd32, 6'd1, 1'b0);
        alloc_data_1 = make_uop(64'd11, 5'd2, 6'd33, 6'd2, 1'b0);
        alloc_valid = 2'b11;
        #1ns;
        if ((dispatch_valid != 2'b11) || (alloc_ready != 2'b00) ||
            (dispatch_data_0.rob_tag != 4'd0) ||
            (dispatch_data_1.rob_tag != 4'd1)) begin
            $fatal(1, "initial ROB tags or dispatch backpressure failed");
        end
        @(posedge clk);
        #1ns;
        if (count != 3'd0) begin
            $fatal(1, "blocked dispatch allocated ROB entries");
        end

        @(negedge clk);
        dispatch_ready = 2'b11;
        @(posedge clk);
        @(negedge clk);
        clear_events();
        #1ns;
        if ((count != 3'd2) || (commit_valid != 2'b00) ||
            !head_valid || (head_tag != 4'd0)) begin
            $fatal(1, "dual ROB allocation count mismatch");
        end

        complete_data_0.valid = 1'b1;
        complete_data_0.rob_tag = 4'd1;
        @(posedge clk);
        @(negedge clk);
        clear_events();
        #1ns;
        if (commit_valid != 2'b00) begin
            $fatal(1, "younger completed entry bypassed ROB head");
        end

        complete_data_0.valid = 1'b1;
        complete_data_0.rob_tag = 4'd0;
        @(posedge clk);
        @(negedge clk);
        clear_events();
        #1ns;
        if ((commit_valid != 2'b11) ||
            (commit_data_0.uop.renamed.decoded.fetch.rvfi_order != 64'd10) ||
            (commit_data_1.uop.renamed.decoded.fetch.rvfi_order != 64'd11)) begin
            $fatal(1, "completed entries did not commit in program order");
        end

        commit_ready = 2'b01;
        @(posedge clk);
        @(negedge clk);
        #1ns;
        if ((count != 3'd1) || (commit_valid != 2'b01) ||
            (commit_data_0.uop.rob_tag != 4'd1)) begin
            $fatal(1, "single-lane commit did not advance the head once");
        end
        commit_ready = 2'b11;
        @(posedge clk);
        @(negedge clk);
        commit_ready = 2'b00;
        #1ns;
        if (count != 3'd0) begin
            $fatal(1, "ROB did not drain after second commit");
        end

        alloc_data_0 = make_uop(64'd20, 5'd1, 6'd34, 6'd32, 1'b0);
        alloc_data_1 = make_uop(64'd21, 5'd2, 6'd35, 6'd33, 1'b0);
        alloc_valid = 2'b11;
        dispatch_ready = 2'b11;
        @(posedge clk);
        @(negedge clk);
        alloc_data_0 = make_uop(64'd22, 5'd3, 6'd36, 6'd3, 1'b0);
        alloc_data_1 = make_uop(64'd23, 5'd4, 6'd37, 6'd4, 1'b0);
        @(posedge clk);
        @(negedge clk);
        clear_events();
        #1ns;
        if (count != 3'd4) begin
            $fatal(1, "ROB did not reach full occupancy");
        end

        alloc_data_0 = make_uop(64'd24, 5'd5, 6'd38, 6'd5, 1'b0);
        alloc_data_1 = make_uop(64'd25, 5'd6, 6'd39, 6'd6, 1'b0);
        alloc_valid = 2'b11;
        #1ns;
        if ((dispatch_valid != 2'b00) || (alloc_ready != 2'b00)) begin
            $fatal(1, "full ROB accepted entries without retirement");
        end

        alloc_valid = 2'b00;
        complete_data_0.valid = 1'b1;
        complete_data_0.rob_tag = 4'd2;
        complete_data_1.valid = 1'b1;
        complete_data_1.rob_tag = 4'd3;
        @(posedge clk);
        @(negedge clk);
        complete_data_0.rob_tag = 4'd0;
        complete_data_1.rob_tag = 4'd1;
        @(posedge clk);
        @(negedge clk);
        clear_events();
        commit_ready = 2'b11;
        alloc_data_0 = make_uop(64'd24, 5'd5, 6'd38, 6'd5, 1'b0);
        alloc_data_1 = make_uop(64'd25, 5'd6, 6'd39, 6'd6, 1'b0);
        alloc_valid = 2'b11;
        #1ns;
        if ((commit_valid != 2'b11) || (dispatch_valid != 2'b11) ||
            (dispatch_data_0.rob_tag != 4'd2) ||
            (dispatch_data_1.rob_tag != 4'd3)) begin
            $fatal(1, "full ROB did not reuse committing slots");
        end
        @(posedge clk);
        @(negedge clk);
        clear_events();
        commit_ready = 2'b00;
        #1ns;
        if ((count != 3'd4) || (commit_valid != 2'b11) ||
            (commit_data_0.uop.rob_tag != 4'd0) ||
            (commit_data_1.uop.rob_tag != 4'd1)) begin
            $fatal(1, "simultaneous commit/allocation corrupted ROB order");
        end

        flush = 1'b1;
        #1ns;
        if ((commit_valid != 2'b00) || (dispatch_valid != 2'b00)) begin
            $fatal(1, "flush did not suppress ROB transfers");
        end
        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        #1ns;
        if ((count != '0) || head_valid) begin
            $fatal(1, "flush did not clear in-flight ROB entries");
        end

        alloc_data_0 = make_uop(64'd30, 5'd0, 6'd0, 6'd0, 1'b1);
        alloc_valid = 2'b01;
        dispatch_ready = 2'b11;
        @(posedge clk);
        @(negedge clk);
        clear_events();
        #1ns;
        if ((commit_valid != 2'b01) ||
            !commit_data_0.uop.renamed.decoded.illegal ||
            !commit_data_0.result.exception_valid ||
            (commit_data_0.result.exception_cause != EXC_ILLEGAL)) begin
            $fatal(1, "illegal instruction was not made retire-ready");
        end

        $display("rob_tb: PASS");
        $finish;
    end

endmodule : rob_tb
