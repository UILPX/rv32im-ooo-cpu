module sp_ff_array_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer unsigned S_INDEX = 2;
    localparam integer unsigned WIDTH   = 8;

    logic                 clk0;
    logic                 rst0;
    logic                 csb0;
    logic                 web0;
    logic [S_INDEX-1:0]   addr0;
    logic [WIDTH-1:0]     din0;
    logic [WIDTH-1:0]     dout0;

    sp_ff_array #(
        .S_INDEX(S_INDEX),
        .WIDTH(WIDTH)
    ) dut (
        .clk0,
        .rst0,
        .csb0,
        .web0,
        .addr0,
        .din0,
        .dout0
    );

    always #5ns clk0 = ~clk0;

    task automatic write_word(
        input logic [S_INDEX-1:0] write_addr,
        input logic [WIDTH-1:0]   write_data
    );
        @(negedge clk0);
        csb0  = 1'b0;
        web0  = 1'b0;
        addr0 = write_addr;
        din0  = write_data;

        @(negedge clk0);
        csb0 = 1'b1;
        web0 = 1'b1;

        @(posedge clk0);
        #1ns;
    endtask

    task automatic read_word(
        input logic [S_INDEX-1:0] read_addr,
        input logic [WIDTH-1:0]   expected_data
    );
        @(negedge clk0);
        csb0  = 1'b0;
        web0  = 1'b1;
        addr0 = read_addr;

        @(posedge clk0);
        #1ns;
        if (dout0 !== expected_data) begin
            $fatal(1, "address %0d: expected 0x%0h, got 0x%0h",
                   read_addr, expected_data, dout0);
        end

        @(negedge clk0);
        csb0 = 1'b1;
    endtask

    initial begin
        clk0  = 1'b0;
        rst0  = 1'b1;
        csb0  = 1'b1;
        web0  = 1'b1;
        addr0 = '0;
        din0  = '0;

        repeat (2) @(posedge clk0);
        @(negedge clk0);
        rst0 = 1'b0;

        read_word(2'd0, 8'h00);
        write_word(2'd2, 8'hA5);
        read_word(2'd2, 8'hA5);
        read_word(2'd1, 8'h00);

        $display("PASS: sp_ff_array smoke test");
        $finish;
    end
endmodule : sp_ff_array_tb
