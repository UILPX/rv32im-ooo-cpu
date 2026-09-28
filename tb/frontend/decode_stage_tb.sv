module decode_stage_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic [1:0] fetch_valid;
    fetch_inst_t fetch_data_0;
    fetch_inst_t fetch_data_1;
    logic [1:0] fetch_ready;
    logic [1:0] decode_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    decoded_uop_t decode_data_0;
    decoded_uop_t decode_data_1;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0] decode_ready;
    logic flush;

    decode_stage #(.DECODE_WIDTH(2)) dut (.*);

    initial begin
        fetch_valid = 2'b11;
        fetch_data_0 = '0;
        fetch_data_1 = '0;
        fetch_data_0.inst = 32'h0010_0093;
        fetch_data_0.rvfi_order = 64'd10;
        fetch_data_1.inst = 32'h0220_81b3;
        fetch_data_1.rvfi_order = 64'd11;
        decode_ready = 2'b00;
        flush = 1'b0;
        #1ns;

        if ((decode_valid != 2'b11) || (fetch_ready != 2'b00) ||
            (decode_data_0.op != OP_ADDI) || (decode_data_1.op != OP_MUL) ||
            (decode_data_0.fetch.rvfi_order != 64'd10) ||
            (decode_data_1.fetch.rvfi_order != 64'd11)) begin
            $fatal(1, "dual-lane decode or blocked handshake failed");
        end

        decode_ready = 2'b10;
        #1ns;
        if (fetch_ready != 2'b00) begin
            $fatal(1, "lane one bypassed a blocked lane zero");
        end

        decode_ready = 2'b01;
        #1ns;
        if (fetch_ready != 2'b01) begin
            $fatal(1, "lane zero could not advance independently");
        end

        decode_ready = 2'b11;
        #1ns;
        if (fetch_ready != 2'b11) begin
            $fatal(1, "dual-lane transfer was not accepted");
        end

        flush = 1'b1;
        #1ns;
        if ((decode_valid != 2'b00) || (fetch_ready != 2'b00)) begin
            $fatal(1, "flush did not suppress decode transfers");
        end

        $display("decode_stage_tb: PASS");
        $finish;
    end

endmodule : decode_stage_tb
