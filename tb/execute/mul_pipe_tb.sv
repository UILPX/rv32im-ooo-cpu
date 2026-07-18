module mul_pipe_tb #(
    parameter integer unsigned WIDTH      = 32,
    parameter integer unsigned NUM_STAGES = 2
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer unsigned TEST_ITEMS = 64;

    logic                   clk;
    logic                   rst;
    logic                   flush;
    logic                   input_valid;
    logic                   input_ready;
    logic [WIDTH-1:0]       input_a;
    logic [WIDTH-1:0]       input_b;
    logic                   output_valid;
    logic                   output_ready;
    logic [2*WIDTH-1:0]     output_product;

    logic [2*WIDTH-1:0] expected_queue[$];
    logic [2*WIDTH-1:0] expected_product;
    logic [2*WIDTH-1:0] blocked_product;
    logic               output_blocked;

    integer unsigned cycle_count;
    integer unsigned sent_count;
    integer unsigned received_count;

    mul_pipe #(
        .WIDTH      (WIDTH),
        .NUM_STAGES (NUM_STAGES)
    ) dut (
        .clk,
        .rst,
        .flush,
        .input_valid,
        .input_ready,
        .input_a,
        .input_b,
        .output_valid,
        .output_ready,
        .output_product
    );

    always #5ns clk = ~clk;

    function automatic logic [WIDTH-1:0] operand_a(input integer unsigned index);
        return WIDTH'((index * 32'h1021) ^ 32'h8000_0055);
    endfunction

    function automatic logic [WIDTH-1:0] operand_b(input integer unsigned index);
        return WIDTH'((index * 32'h0041) ^ 32'h0000_00a3);
    endfunction

    initial begin
        clk              = 1'b0;
        rst              = 1'b1;
        flush            = 1'b0;
        input_valid      = 1'b0;
        input_a          = '0;
        input_b          = '0;
        output_ready     = 1'b0;
        cycle_count      = 0;
        sent_count       = 0;
        received_count   = 0;
        output_blocked   = 1'b0;
        blocked_product  = '0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while ((sent_count < TEST_ITEMS) ||
               (expected_queue.size() != 0) || output_valid) begin
            @(negedge clk);
            cycle_count = cycle_count + 1;

            flush = (cycle_count == 23);
            output_ready = (cycle_count > 23) ||
                           ((cycle_count % 7) != 3 && (cycle_count % 7) != 4);

            input_valid = (sent_count < TEST_ITEMS) && !flush;
            input_a = operand_a(sent_count);
            input_b = operand_b(sent_count);

            @(posedge clk);

            if (flush) begin
                expected_queue.delete();
                output_blocked = 1'b0;
            end else begin
                if (output_blocked) begin
                    if (!output_valid || (output_product !== blocked_product)) begin
                        $fatal(1, "blocked multiplier output changed");
                    end
                    if (output_ready) begin
                        output_blocked = 1'b0;
                    end
                end

                if (input_valid && input_ready) begin
                    expected_product = input_a * input_b;
                    expected_queue.push_back(expected_product);
                    sent_count = sent_count + 1;
                end

                if (output_valid && output_ready) begin
                    if (expected_queue.size() == 0) begin
                        $fatal(1, "multiplier produced an unexpected result");
                    end

                    expected_product = expected_queue.pop_front();
                    if (output_product !== expected_product) begin
                        $fatal(1, "expected 0x%0h, got 0x%0h",
                               expected_product, output_product);
                    end
                    received_count = received_count + 1;
                end else if (output_valid && !output_ready && !output_blocked) begin
                    output_blocked  = 1'b1;
                    blocked_product = output_product;
                end
            end

            if (cycle_count > 400) begin
                $fatal(1, "multiplier test timed out");
            end
        end

        @(negedge clk);
        input_valid  = 1'b0;
        output_ready = 1'b1;
        repeat (2) @(posedge clk);

        $display("PASS: mul_pipe WIDTH=%0d NUM_STAGES=%0d received=%0d",
                 WIDTH, NUM_STAGES, received_count);
        $finish;
    end
endmodule : mul_pipe_tb
