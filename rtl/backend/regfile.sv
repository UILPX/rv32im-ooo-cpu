module regfile #(
    parameter integer unsigned DATA_WIDTH      = 32,
    parameter integer unsigned NUM_REGS        = 64,
    parameter integer unsigned ADDR_WIDTH      = (NUM_REGS <= 1) ? 1 : $clog2(NUM_REGS),
    parameter integer unsigned NUM_READ_PORTS  = 4,
    parameter integer unsigned NUM_WRITE_PORTS = 2,
    parameter integer unsigned ZERO_REG_EN     = 1,
    parameter integer unsigned RESET_DATA      = 1
) (
    input   logic                                               clk,
    input   logic                                               rst,

    // Read ports: dispatch/issue provide physical register indices directly.
    input   logic   [NUM_READ_PORTS-1:0][ADDR_WIDTH-1:0]        raddr,
    output  logic   [NUM_READ_PORTS-1:0][DATA_WIDTH-1:0]        rdata,

    // Writeback ports: execution writes result data and marks preg ready.
    input   logic   [NUM_WRITE_PORTS-1:0]                       wen,
    input   logic   [NUM_WRITE_PORTS-1:0][ADDR_WIDTH-1:0]       waddr,
    input   logic   [NUM_WRITE_PORTS-1:0][DATA_WIDTH-1:0]       wdata
);

    localparam logic [ADDR_WIDTH-1:0] ZERO_REG_IDX = '0;

    logic [DATA_WIDTH-1:0] preg_data_q [NUM_REGS];

    logic [NUM_WRITE_PORTS-1:0] write_fire;

    always_comb begin
        for (integer unsigned i = 0; i < NUM_WRITE_PORTS; i = i + 1) begin
            write_fire[i] = wen[i] &&
                            !((ZERO_REG_EN != 0) && (waddr[i] == ZERO_REG_IDX));
        end
    end

    generate
        if (RESET_DATA != 0) begin : gen_reset_data
            always_ff @(posedge clk) begin
                if (rst) begin
                    for (integer unsigned i = 0; i < NUM_REGS; i = i + 1) begin
                        preg_data_q[i] <= '0;
                    end
                end else begin
                    for (integer unsigned i = 0; i < NUM_WRITE_PORTS; i = i + 1) begin
                        if (write_fire[i]) begin
                            preg_data_q[waddr[i]] <= wdata[i];
                        end
                    end

                    if (ZERO_REG_EN != 0) begin
                        preg_data_q[ZERO_REG_IDX] <= '0;
                    end
                end
            end
        end else begin : gen_no_reset_data
            always_ff @(posedge clk) begin
                if (!rst) begin
                    for (integer unsigned i = 0; i < NUM_WRITE_PORTS; i = i + 1) begin
                        if (write_fire[i]) begin
                            preg_data_q[waddr[i]] <= wdata[i];
                        end
                    end

                    if (ZERO_REG_EN != 0) begin
                        preg_data_q[ZERO_REG_IDX] <= '0;
                    end
                end
            end
        end
    endgenerate

    always_comb begin
        for (integer unsigned i = 0; i < NUM_READ_PORTS; i = i + 1) begin
            rdata[i] = '0;

            if ((ZERO_REG_EN != 0) && (raddr[i] == ZERO_REG_IDX)) begin
                rdata[i] = '0;
            end else begin
                rdata[i] = preg_data_q[raddr[i]];

                // Same-cycle writeback bypasses stored data.
                for (integer unsigned j = 0; j < NUM_WRITE_PORTS; j = j + 1) begin
                    if (write_fire[j] && (waddr[j] == raddr[i])) begin
                        rdata[i] = wdata[j];
                    end
                end
            end
        end
    end

endmodule : regfile
