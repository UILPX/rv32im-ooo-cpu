module decode_buffer_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic flush;
    logic [1:0] push_valid;
    decoded_uop_t push_data_0;
    decoded_uop_t push_data_1;
    logic [1:0] push_ready;
    logic [1:0] decode_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    decoded_uop_t decode_data_0;
    decoded_uop_t decode_data_1;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0] decode_ready;
    logic [2:0] count;

    decode_buffer #(
        .DEPTH (4)
    ) dut (.*);

    always #5ns clk = ~clk;

    function automatic decoded_uop_t make_uop(input logic [31:0] pc);
        decoded_uop_t result;
        result = '0;
        result.fetch.pc = pc;
        result.fetch.rvfi_order = 64'(pc) >> 2;
        result.op = OP_ADDI;
        result.fu_class = FU_INT;
        make_uop = result;
    endfunction

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        push_valid = 2'b00;
        push_data_0 = '0;
        push_data_1 = '0;
        decode_ready = 2'b00;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        push_valid = 2'b11;
        push_data_0 = make_uop(32'h1000);
        push_data_1 = make_uop(32'h1004);
        #1ns;
        if (push_ready != 2'b11)
            $fatal(1, "empty decode buffer did not accept two uops");
        @(posedge clk);

        @(negedge clk);
        push_data_0 = make_uop(32'h1008);
        push_data_1 = make_uop(32'h100c);
        @(posedge clk);

        @(negedge clk);
        push_valid = 2'b00;
        #1ns;
        if ((count != 3'd4) || (decode_valid != 2'b11) ||
            (decode_data_0.fetch.pc != 32'h1000) ||
            (decode_data_1.fetch.pc != 32'h1004)) begin
            $fatal(1, "decode buffer did not preserve full-queue order");
        end

        decode_ready = 2'b11;
        push_valid = 2'b11;
        push_data_0 = make_uop(32'h1010);
        push_data_1 = make_uop(32'h1014);
        #1ns;
        if (push_ready != 2'b00) begin
            $fatal(1, "full queue borrowed combinational pop capacity");
        end
        @(posedge clk);

        @(negedge clk);
        #1ns;
        if ((count != 3'd2) || (push_ready != 2'b11) ||
            (decode_data_0.fetch.pc != 32'h1008) ||
            (decode_data_1.fetch.pc != 32'h100c)) begin
            $fatal(1, "full-queue pop did not expose the next pair");
        end
        @(posedge clk);

        @(negedge clk);
        push_valid = 2'b00;
        decode_ready = 2'b00;
        #1ns;
        if ((count != 3'd2) ||
            (decode_data_0.fetch.pc != 32'h1010) ||
            (decode_data_1.fetch.pc != 32'h1014)) begin
            $fatal(1, "simultaneous two-wide replace lost ordering");
        end

        flush = 1'b1;
        #1ns;
        if ((decode_valid != 2'b00) || (push_ready != 2'b00))
            $fatal(1, "flush did not suppress decode-buffer transfers");
        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        #1ns;
        if (count != '0)
            $fatal(1, "flush did not clear the decode buffer");

        $display("decode_buffer_tb: PASS");
        $finish;
    end

endmodule : decode_buffer_tb
