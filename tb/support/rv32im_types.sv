package rv32im_types;
    localparam integer unsigned PHYS_REG_BITS = 6;

    localparam logic [4:0] OP_MUL    = 5'd0;
    localparam logic [4:0] OP_MULH   = 5'd1;
    localparam logic [4:0] OP_MULHSU = 5'd2;
    localparam logic [4:0] OP_MULHU  = 5'd3;
    localparam logic [4:0] OP_DIV    = 5'd4;
    localparam logic [4:0] OP_DIVU   = 5'd5;
    localparam logic [4:0] OP_REM    = 5'd6;
    localparam logic [4:0] OP_REMU   = 5'd7;

    typedef struct packed {
        logic [4:0]               op;
        logic [31:0]              value_1;
        logic [31:0]              value_2;
        logic [PHYS_REG_BITS-1:0] phy_rd;
    } simple_issue_t;

    typedef struct packed {
        logic                     valid;
        logic [PHYS_REG_BITS-1:0] phy_rd;
        logic [31:0]              value;
    } wb_bus_t;
endpackage : rv32im_types
