package rv32im_types;
    localparam integer unsigned XLEN                = 32;
    localparam integer unsigned INST_BITS           = 32;
    localparam integer unsigned RVFI_ORDER_BITS     = 64;
    localparam integer unsigned ARCH_REG_BITS       = 5;
    localparam integer unsigned PHYS_REG_BITS       = 6;
    localparam integer unsigned ROB_TAG_BITS        = 4;
    localparam integer unsigned UOP_BITS            = 6;
    localparam integer unsigned WB_DATA_BITS        = XLEN;
    localparam integer unsigned DCACHE_REQ_ID_BITS  = 4;

    localparam integer unsigned CACHE_LINE_BITS     = 256;
    localparam integer unsigned CACHE_OFFSET_BITS   = 5;
    localparam integer unsigned CACHE_SET_BITS      = 4;
    localparam integer unsigned CACHE_WAY_BITS      = 2;
    localparam integer unsigned CACHE_MSHR_ID_BITS  = 4;
    localparam integer unsigned ICACHE_PORTS        = 2;

    typedef logic [XLEN-1:0]            xlen_t;
    typedef logic [INST_BITS-1:0]       inst_t;
    typedef logic [RVFI_ORDER_BITS-1:0] rvfi_order_t;
    typedef logic [ARCH_REG_BITS-1:0]   arch_reg_t;
    typedef logic [PHYS_REG_BITS-1:0]   phys_reg_t;
    typedef logic [ROB_TAG_BITS-1:0]    rob_tag_t;

    typedef enum logic [UOP_BITS-1:0] {
        OP_INVALID = 6'd0,
        OP_LUI     = 6'd1,
        OP_AUIPC   = 6'd2,
        OP_JAL     = 6'd3,
        OP_JALR    = 6'd4,
        OP_BEQ     = 6'd5,
        OP_BNE     = 6'd6,
        OP_BLT     = 6'd7,
        OP_BGE     = 6'd8,
        OP_BLTU    = 6'd9,
        OP_BGEU    = 6'd10,
        OP_LB      = 6'd11,
        OP_LH      = 6'd12,
        OP_LW      = 6'd13,
        OP_LBU     = 6'd14,
        OP_LHU     = 6'd15,
        OP_SB      = 6'd16,
        OP_SH      = 6'd17,
        OP_SW      = 6'd18,
        OP_ADDI    = 6'd19,
        OP_SLTI    = 6'd20,
        OP_SLTIU   = 6'd21,
        OP_XORI    = 6'd22,
        OP_ORI     = 6'd23,
        OP_ANDI    = 6'd24,
        OP_SLLI    = 6'd25,
        OP_SRLI    = 6'd26,
        OP_SRAI    = 6'd27,
        OP_ADD     = 6'd28,
        OP_SUB     = 6'd29,
        OP_SLL     = 6'd30,
        OP_SLT     = 6'd31,
        OP_SLTU    = 6'd32,
        OP_XOR     = 6'd33,
        OP_SRL     = 6'd34,
        OP_SRA     = 6'd35,
        OP_OR      = 6'd36,
        OP_AND     = 6'd37,
        OP_FENCE   = 6'd38,
        OP_ECALL   = 6'd39,
        OP_EBREAK  = 6'd40,
        OP_MUL     = 6'd41,
        OP_MULH    = 6'd42,
        OP_MULHSU  = 6'd43,
        OP_MULHU   = 6'd44,
        OP_DIV     = 6'd45,
        OP_DIVU    = 6'd46,
        OP_REM     = 6'd47,
        OP_REMU    = 6'd48
    } uop_t;

    localparam logic [6:0] op_b_lui     = 7'b0110111;
    localparam logic [6:0] op_b_auipc   = 7'b0010111;
    localparam logic [6:0] op_b_jal     = 7'b1101111;
    localparam logic [6:0] op_b_jalr    = 7'b1100111;
    localparam logic [6:0] op_b_branch  = 7'b1100011;
    localparam logic [6:0] op_b_load    = 7'b0000011;
    localparam logic [6:0] op_b_store   = 7'b0100011;
    localparam logic [6:0] op_b_imm     = 7'b0010011;
    localparam logic [6:0] op_b_reg     = 7'b0110011;
    localparam logic [6:0] op_b_fence   = 7'b0001111;
    localparam logic [6:0] op_b_system  = 7'b1110011;

    typedef struct packed {
        xlen_t       pc;
        inst_t       inst;
        rvfi_order_t rvfi_order;
    } fetch_inst_t;

    typedef struct packed {
        uop_t      op;
        phys_reg_t phy_rd;
        xlen_t     value_1;
        xlen_t     value_2;
    } simple_issue_t;

    typedef struct packed {
        xlen_t     pc;
        xlen_t     imm;
        xlen_t     target_pc;
        uop_t      op;
        phys_reg_t phy_rd;
        xlen_t     value_1;
        xlen_t     value_2;
        rob_tag_t  rob_tag;
        logic      pred_taken;
        xlen_t     pred_pc;
        logic      bp_is_call;
        logic      bp_is_return;
    } branch_issue_t;

    typedef struct packed {
        uop_t      op;
        phys_reg_t phy_rd;
        phys_reg_t phy_rs1;
        phys_reg_t phy_rs2;
        logic      ready_1;
        logic      ready_2;
        xlen_t     value_1;
        xlen_t     value_2;
        xlen_t     pc;
        xlen_t     imm;
        rob_tag_t  rob_tag;
        logic      pred_taken;
        xlen_t     pred_pc;
        logic      bp_is_call;
        logic      bp_is_return;
    } res_stat_t;

    typedef struct packed {
        logic      valid;
        phys_reg_t phy_rd;
        xlen_t     value;
    } wb_bus_t;

    typedef struct packed {
        logic [DCACHE_REQ_ID_BITS-1:0] id;
        xlen_t                         addr;
        logic [3:0]                    rmask;
        logic [3:0]                    wmask;
        xlen_t                         wdata;
    } dcache_cpu_req_t;

    typedef struct packed {
        logic [DCACHE_REQ_ID_BITS-1:0] id;
        xlen_t                         addr;
        logic [3:0]                    rmask;
        logic [3:0]                    wmask;
        xlen_t                         rdata;
    } dcache_cpu_resp_t;

    typedef enum logic {
        cache_src_icache = 1'b0,
        cache_src_dcache = 1'b1
    } cache_src_t;

    typedef enum logic [1:0] {
        cache_req_demand_read   = 2'd0,
        cache_req_prefetch_read = 2'd1,
        cache_req_writeback     = 2'd2
    } cache_req_kind_t;

    typedef struct packed {
        cache_src_t                       src;
        cache_req_kind_t                  kind;
        xlen_t                            line_addr;
        logic [CACHE_LINE_BITS-1:0]       line_wdata;
        logic [CACHE_SET_BITS-1:0]        set_idx;
        logic [CACHE_WAY_BITS-1:0]        fill_way;
        logic [CACHE_MSHR_ID_BITS-1:0]    mshr_id;
        logic [ICACHE_PORTS-1:0]          icache_port_mask;
        logic                             critical;
    } cache_mem_req_t;

    typedef struct packed {
        cache_src_t                       src;
        logic [CACHE_MSHR_ID_BITS-1:0]    mshr_id;
        xlen_t                            line_addr;
        logic [CACHE_LINE_BITS-1:0]       line_data;
    } cache_mem_resp_t;
endpackage : rv32im_types
