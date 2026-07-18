module div_iterative_tb #(
    parameter integer unsigned WIDTH   = 32,
    parameter integer unsigned DIV_CYC = 11
);
    timeunit 1ns;
    timeprecision 1ps;

    logic                   clk;
    logic                   rst;
    logic                   flush;
    logic                   input_valid;
    logic                   input_ready;
    logic [WIDTH-1:0]       input_dividend;
    logic [WIDTH-1:0]       input_divisor;
    logic                   output_valid;
    logic                   output_ready;
    logic [WIDTH-1:0]       output_quotient;
    logic [WIDTH-1:0]       output_remainder;
    logic                   output_divide_by_zero;

    div_iterative #(
        .WIDTH   (WIDTH),
        .DIV_CYC (DIV_CYC)
    ) dut (
        .clk,
        .rst,
        .flush,
        .input_valid,
        .input_ready,
        .input_dividend,
        .input_divisor,
        .output_valid,
        .output_ready,
        .output_quotient,
        .output_remainder,
        .output_divide_by_zero
    );

    always #5ns clk = ~clk;

    task automatic run_case(
        input logic [WIDTH-1:0] dividend,
        input logic [WIDTH-1:0] divisor
    );
        logic [WIDTH-1:0] expected_quotient;
        logic [WIDTH-1:0] expected_remainder;
        integer unsigned elapsed_cycles;

        expected_quotient = (divisor == '0) ? '1 : dividend / divisor;
        expected_remainder = (divisor == '0) ? dividend : dividend % divisor;

        @(negedge clk);
        input_valid    = 1'b1;
        input_dividend = dividend;
        input_divisor  = divisor;
        output_ready   = 1'b0;

        while (!input_ready) begin
            @(posedge clk);
            @(negedge clk);
        end

        @(posedge clk);
        #1ns;
        @(negedge clk);
        input_valid = 1'b0;

        elapsed_cycles = 0;
        if (divisor != '0) begin
            while (!output_valid) begin
                @(posedge clk);
                #1ns;
                elapsed_cycles = elapsed_cycles + 1;
                if (elapsed_cycles > DIV_CYC) begin
                    $fatal(1, "divider test timed out");
                end
            end

            if (elapsed_cycles != DIV_CYC) begin
                $fatal(1, "expected latency %0d, got %0d", DIV_CYC, elapsed_cycles);
            end
        end else if (!output_valid) begin
            $fatal(1, "divide-by-zero result was not produced immediately");
        end

        if ((output_quotient !== expected_quotient) ||
            (output_remainder !== expected_remainder) ||
            (output_divide_by_zero !== (divisor == '0))) begin
            $fatal(1,
                   "divide mismatch: %0h / %0h expected q=%0h r=%0h, got q=%0h r=%0h",
                   dividend, divisor, expected_quotient, expected_remainder,
                   output_quotient, output_remainder);
        end

        repeat (2) begin
            @(posedge clk);
            #1ns;
            if (!output_valid ||
                (output_quotient !== expected_quotient) ||
                (output_remainder !== expected_remainder)) begin
                $fatal(1, "divider result changed under backpressure");
            end
        end

        @(negedge clk);
        output_ready = 1'b1;
        @(posedge clk);
        #1ns;
        if (output_valid) begin
            $fatal(1, "divider result did not clear after handshake");
        end
    endtask

    task automatic test_flush;
        @(negedge clk);
        input_valid    = 1'b1;
        input_dividend = WIDTH'(32'hffff_fff1);
        input_divisor  = WIDTH'(32'h0000_0011);
        output_ready   = 1'b0;

        @(posedge clk);
        @(negedge clk);
        input_valid = 1'b0;

        if (DIV_CYC > 1) begin
            @(posedge clk);
        end

        @(negedge clk);
        flush = 1'b1;
        @(posedge clk);
        #1ns;
        if (output_valid) begin
            $fatal(1, "flush did not cancel divider output");
        end

        @(negedge clk);
        flush = 1'b0;
        #1ns;
        if (!input_ready) begin
            $fatal(1, "divider was not ready after flush");
        end
    endtask

    initial begin
        clk                   = 1'b0;
        rst                   = 1'b1;
        flush                 = 1'b0;
        input_valid           = 1'b0;
        input_dividend        = '0;
        input_divisor         = '0;
        output_ready          = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        run_case('0, WIDTH'(1));
        run_case('1, WIDTH'(1));
        run_case('1, '1);
        run_case('1, '0);
        run_case(WIDTH'(32'h8000_0000), WIDTH'(3));
        run_case(WIDTH'(32'hffff_ffff), WIDTH'(32'h0000_ffff));

        for (integer unsigned i = 1; i <= 16; i = i + 1) begin
            run_case(
                WIDTH'((i * 32'h1020_4081) ^ 32'hdeaf_beef),
                WIDTH'((i * 32'h0001_0041) | 32'h0000_0001)
            );
        end

        test_flush();
        run_case(WIDTH'(123456789), WIDTH'(12345));

        $display("PASS: div_iterative WIDTH=%0d DIV_CYC=%0d", WIDTH, DIV_CYC);
        $finish;
    end
endmodule : div_iterative_tb
