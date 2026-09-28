module sp_sram_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer unsigned DATA_WIDTH = 32;
    localparam integer unsigned DEPTH      = 4;
    localparam integer unsigned MASK_WIDTH = 4;
    localparam integer unsigned ADDR_WIDTH = $clog2(DEPTH);

    logic                      clk0;
    logic                      csb0;
    logic                      web0;
    logic [MASK_WIDTH-1:0]     wmask0;
    logic [ADDR_WIDTH-1:0]     addr0;
    logic [DATA_WIDTH-1:0]     din0;
    logic [DATA_WIDTH-1:0]     dout0;

    sp_sram #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH),
        .MASK_WIDTH (MASK_WIDTH)
    ) dut (
        .clk0,
        .csb0,
        .web0,
        .wmask0,
        .addr0,
        .din0,
        .dout0
    );

    always #5ns clk0 = ~clk0;

    task automatic write_word(
        input logic [ADDR_WIDTH-1:0] write_addr,
        input logic [DATA_WIDTH-1:0] write_data,
        input logic [MASK_WIDTH-1:0] write_mask
    );
        @(negedge clk0);
        csb0   = 1'b0;
        web0   = 1'b0;
        wmask0 = write_mask;
        addr0  = write_addr;
        din0   = write_data;
        @(posedge clk0);
        #1ns;
    endtask

    task automatic read_word(
        input logic [ADDR_WIDTH-1:0] read_addr,
        input logic [DATA_WIDTH-1:0] expected_data
    );
        @(negedge clk0);
        csb0  = 1'b0;
        web0  = 1'b1;
        addr0 = read_addr;
        @(posedge clk0);
        #1ns;
        if (dout0 !== expected_data) begin
            $fatal(1, "address %0d: expected 0x%08h, got 0x%08h",
                   read_addr, expected_data, dout0);
        end
    endtask

    initial begin
        clk0   = 1'b0;
        csb0   = 1'b1;
        web0   = 1'b1;
        wmask0 = '0;
        addr0  = '0;
        din0   = '0;

        write_word(2'd1, 32'h1122_3344, 4'b1111);
        read_word(2'd1, 32'h1122_3344);

        write_word(2'd1, 32'hAABB_CCDD, 4'b0101);
        read_word(2'd1, 32'h11BB_33DD);

        @(negedge clk0);
        csb0 = 1'b1;
        addr0 = 2'd2;
        @(posedge clk0);
        #1ns;
        if (dout0 !== 32'h11BB_33DD) begin
            $fatal(1, "disabled SRAM must hold its previous read output");
        end

        $display("sp_sram_tb: PASS");
        $finish;
    end

endmodule : sp_sram_tb
