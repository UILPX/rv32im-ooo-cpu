module regfile_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer unsigned NUM_READ_PORTS  = 4;
    localparam integer unsigned NUM_WRITE_PORTS = 2;
    localparam integer unsigned ADDR_WIDTH      = 6;

    logic                                            clk;
    logic                                            rst;
    logic [NUM_READ_PORTS-1:0][ADDR_WIDTH-1:0]       raddr;
    logic [NUM_READ_PORTS-1:0][31:0]                 rdata;
    logic [NUM_WRITE_PORTS-1:0]                      wen;
    logic [NUM_WRITE_PORTS-1:0][ADDR_WIDTH-1:0]      waddr;
    logic [NUM_WRITE_PORTS-1:0][31:0]                wdata;

    regfile dut (.*);

    always #5ns clk = ~clk;

    task automatic clear_writes;
        wen   = '0;
        waddr = '0;
        wdata = '0;
    endtask

    task automatic expect_read(
        input integer unsigned port,
        input logic [31:0]     expected,
        input string           message
    );
        #1ns;
        if (rdata[port] !== expected) begin
            $fatal(1, "%s: port %0d expected %08h, got %08h",
                   message, port, expected, rdata[port]);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        raddr = '0;
        clear_writes();

        repeat (2) @(posedge clk);
        #1ns;
        for (integer unsigned i = 0; i < NUM_READ_PORTS; i = i + 1) begin
            if (rdata[i] !== 32'd0) begin
                $fatal(1, "reset did not clear read port %0d", i);
            end
        end

        @(negedge clk);
        rst = 1'b0;

        // Independent dual writes and same-cycle bypass.
        raddr[0] = 6'd1;
        raddr[1] = 6'd2;
        wen      = 2'b11;
        waddr[0] = 6'd1;
        waddr[1] = 6'd2;
        wdata[0] = 32'h1111_1111;
        wdata[1] = 32'h2222_2222;
        expect_read(0, 32'h1111_1111, "write-port-0 bypass");
        expect_read(1, 32'h2222_2222, "write-port-1 bypass");

        @(posedge clk);
        @(negedge clk);
        clear_writes();
        expect_read(0, 32'h1111_1111, "stored write-port-0 data");
        expect_read(1, 32'h2222_2222, "stored write-port-1 data");

        // All read ports can select independently.
        raddr[0] = 6'd2;
        raddr[1] = 6'd1;
        raddr[2] = 6'd0;
        raddr[3] = 6'd63;
        expect_read(0, 32'h2222_2222, "independent read port 0");
        expect_read(1, 32'h1111_1111, "independent read port 1");
        expect_read(2, 32'd0, "zero register read");
        expect_read(3, 32'd0, "unwritten register read");

        // The existing implementation gives the higher write port priority.
        @(negedge clk);
        raddr[0] = 6'd10;
        wen      = 2'b11;
        waddr[0] = 6'd10;
        waddr[1] = 6'd10;
        wdata[0] = 32'haaaa_aaaa;
        wdata[1] = 32'hbbbb_bbbb;
        expect_read(0, 32'hbbbb_bbbb, "same-address bypass priority");

        @(posedge clk);
        @(negedge clk);
        clear_writes();
        expect_read(0, 32'hbbbb_bbbb, "same-address stored priority");

        // Writes to physical register zero are ignored on both ports.
        @(negedge clk);
        raddr[0] = 6'd0;
        wen      = 2'b11;
        waddr    = '0;
        wdata[0] = 32'hffff_ffff;
        wdata[1] = 32'h1234_5678;
        expect_read(0, 32'd0, "zero-register bypass suppression");

        @(posedge clk);
        @(negedge clk);
        clear_writes();
        expect_read(0, 32'd0, "zero-register stored suppression");

        // Synchronous reset clears previously written physical registers.
        raddr[0] = 6'd1;
        expect_read(0, 32'h1111_1111, "pre-reset data");
        rst = 1'b1;
        @(posedge clk);
        #1ns;
        if (rdata[0] !== 32'd0) begin
            $fatal(1, "synchronous reset did not clear stored data");
        end

        $display("PASS: regfile directed tests");
        $finish;
    end
endmodule : regfile_tb
