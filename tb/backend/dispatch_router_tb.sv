module dispatch_router_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic flush;
    logic [1:0] dispatch_valid;
    rob_uop_t dispatch_data_0;
    rob_uop_t dispatch_data_1;
    logic [1:0] dispatch_ready;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [3:0][PHYS_REG_BITS-1:0] rf_raddr;
    logic [3:0][XLEN-1:0] rf_rdata;
    res_stat_t rs_data_0;
    res_stat_t rs_data_1;
    logic [1:0] int_port_ready;
    logic [1:0] int_select;
    logic [1:0] int_port_bus1_sel;
    logic [1:0] branch_port_ready;
    logic [1:0] branch_select;
    logic [1:0] branch_port_bus1_sel;
    logic [1:0] muldiv_port_ready;
    logic [1:0] muldiv_select;
    logic [1:0] muldiv_port_bus1_sel;
    logic [1:0] memory_port_ready;
    logic [1:0] memory_select;
    logic [1:0] memory_port_bus1_sel;
    logic system_ready;
    rob_complete_t system_complete_data_0;
    rob_complete_t system_complete_data_1;
    /* verilator lint_on UNUSEDSIGNAL */

    dispatch_router dut (.*);

    function automatic rob_uop_t make_uop(
        input uop_t op,
        input fu_class_t fu_class,
        input rob_tag_t tag,
        input phys_reg_t rs1,
        input phys_reg_t rs2,
        input phys_reg_t rd,
        input logic uses_rs1,
        input logic uses_rs2,
        input logic [31:0] imm
    );
        rob_uop_t result;
        result = '0;
        result.rob_tag = tag;
        result.renamed.decoded.op = op;
        result.renamed.decoded.fu_class = fu_class;
        result.renamed.decoded.fetch.pc = 32'h8000_0100 + {26'd0, tag, 2'b00};
        result.renamed.decoded.imm = imm;
        result.renamed.decoded.uses_rs1 = uses_rs1;
        result.renamed.decoded.uses_rs2 = uses_rs2;
        result.renamed.phy_rs1 = rs1;
        result.renamed.phy_rs2 = rs2;
        result.renamed.phy_rd = rd;
        result.renamed.ready_rs1 = !uses_rs1;
        result.renamed.ready_rs2 = !uses_rs2;
        make_uop = result;
    endfunction

    initial begin
        flush = 1'b0;
        dispatch_valid = 2'b11;
        dispatch_data_0 = make_uop(OP_ADDI, FU_INT, 4'd1,
                                   6'd2, 6'd0, 6'd32, 1'b1, 1'b0, 32'd7);
        dispatch_data_0.renamed.ready_rs1 = 1'b1;
        dispatch_data_1 = make_uop(OP_MUL, FU_MULDIV, 4'd2,
                                   6'd3, 6'd4, 6'd33, 1'b1, 1'b1, 32'd0);
        int_port_ready = 2'b11;
        branch_port_ready = 2'b11;
        muldiv_port_ready = 2'b11;
        memory_port_ready = 2'b11;
        system_ready = 1'b1;
        rf_rdata[0] = 32'd10;
        rf_rdata[1] = 32'd20;
        rf_rdata[2] = 32'd30;
        rf_rdata[3] = 32'd40;
        #1ns;

        if ((dispatch_ready != 2'b11) || (int_select != 2'b01) ||
            (muldiv_select != 2'b01) ||
            (muldiv_port_bus1_sel != 2'b01) ||
            (rf_raddr[0] != 6'd2) || (rf_raddr[2] != 6'd3) ||
            (rs_data_0.value_1 != 32'd10) ||
            (rs_data_0.value_2 != 32'd7) ||
            (rs_data_1.value_1 != 32'd30) ||
            (rs_data_1.value_2 != 32'd40)) begin
            $fatal(1, "mixed-class dispatch routing or operand formation failed");
        end
        dispatch_data_1 = make_uop(OP_ADD, FU_INT, 4'd3,
                                   6'd5, 6'd6, 6'd34, 1'b1, 1'b1, 32'd0);
        int_port_ready = 2'b01;
        #1ns;
        if ((dispatch_ready != 2'b01) || (int_select != 2'b01)) begin
            $fatal(1, "second same-class lane ignored one-slot capacity");
        end
        int_port_ready = 2'b11;
        #1ns;
        if ((dispatch_ready != 2'b11) || (int_select != 2'b11) ||
            (int_port_bus1_sel != 2'b10)) begin
            $fatal(1, "two same-class lanes were not routed to both insert ports");
        end

        dispatch_data_0 = make_uop(OP_BEQ, FU_BRANCH, 4'd4,
                                   6'd1, 6'd2, 6'd0, 1'b1, 1'b1, 32'd8);
        dispatch_data_1 = make_uop(OP_ADD, FU_INT, 4'd5,
                                   6'd3, 6'd4, 6'd35, 1'b1, 1'b1, 32'd0);
        branch_port_ready = 2'b00;
        #1ns;
        if ((dispatch_ready != 2'b00) || (int_select != 2'b00) ||
            (branch_select != 2'b00)) begin
            $fatal(1, "younger lane bypassed a blocked older branch");
        end

        dispatch_data_0 = make_uop(OP_ECALL, FU_SYSTEM, 4'd6,
                                   6'd0, 6'd0, 6'd0, 1'b0, 1'b0, 32'd0);
        dispatch_data_1 = make_uop(OP_ADD, FU_INT, 4'd7,
                                   6'd3, 6'd4, 6'd36, 1'b1, 1'b1, 32'd0);
        branch_port_ready = 2'b11;
        #1ns;
        if ((dispatch_ready != 2'b11) ||
            !system_complete_data_0.valid || system_complete_data_1.valid ||
            (system_complete_data_0.rob_tag != 4'd6) ||
            !system_complete_data_0.exception_valid ||
            (system_complete_data_0.exception_cause != EXC_ECALL_MMODE) ||
            (int_select != 2'b01) || (int_port_bus1_sel != 2'b01)) begin
            $fatal(1, "system sink or younger independent routing failed");
        end

        dispatch_valid = 2'b01;
        dispatch_data_0 = make_uop(OP_AUIPC, FU_INT, 4'd8,
                                   6'd0, 6'd0, 6'd37, 1'b0, 1'b0, 32'h1000);
        #1ns;
        if ((rs_data_0.value_1 != dispatch_data_0.renamed.decoded.fetch.pc) ||
            (rs_data_0.value_2 != 32'h1000) ||
            !rs_data_0.ready_1 || !rs_data_0.ready_2) begin
            $fatal(1, "AUIPC operands were not formed from PC plus immediate");
        end

        dispatch_data_0 = make_uop(OP_INVALID, FU_INVALID, 4'd9,
                                   6'd0, 6'd0, 6'd0, 1'b0, 1'b0, 32'd0);
        #1ns;
        if (!dispatch_ready[0] || !system_complete_data_0.valid ||
            !system_complete_data_0.exception_valid ||
            system_complete_data_0.exception_cause != EXC_ILLEGAL ||
            system_complete_data_0.rob_tag != 4'd9) begin
            $fatal(1, "illegal instruction did not produce a precise exception");
        end

        flush = 1'b1;
        #1ns;
        if ((dispatch_ready != 2'b00) || (int_select != 2'b00) ||
            system_complete_data_0.valid || system_complete_data_1.valid) begin
            $fatal(1, "flush did not suppress dispatch router transfers");
        end

        $display("dispatch_router_tb: PASS");
        $finish;
    end

endmodule : dispatch_router_tb
