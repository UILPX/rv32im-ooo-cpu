module rename_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic flush;
    logic [1:0] decode_valid;
    decoded_uop_t decode_data_0;
    decoded_uop_t decode_data_1;
    logic [1:0] decode_ready;
    logic [1:0] rename_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    renamed_uop_t rename_data_0;
    renamed_uop_t rename_data_1;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0] rename_ready;
    logic [1:0] commit_valid;
    arch_reg_t commit_arch_rd_0;
    phys_reg_t commit_new_phys_0;
    phys_reg_t commit_old_phys_0;
    arch_reg_t commit_arch_rd_1;
    phys_reg_t commit_new_phys_1;
    phys_reg_t commit_old_phys_1;
    wb_bus_t wb_bus_0;
    wb_bus_t wb_bus_1;
    logic [PHYS_REG_BITS:0] free_count;

    rename dut (.*);

    always #5ns clk = ~clk;

    function automatic decoded_uop_t make_uop(
        input uop_t op,
        input arch_reg_t rs1,
        input arch_reg_t rs2,
        input arch_reg_t rd,
        input logic uses_rs1,
        input logic uses_rs2,
        input logic writes_rd
    );
        decoded_uop_t result;
        result = '0;
        result.op = op;
        result.fu_class = FU_INT;
        result.rs1 = rs1;
        result.rs2 = rs2;
        result.rd = rd;
        result.uses_rs1 = uses_rs1;
        result.uses_rs2 = uses_rs2;
        result.writes_rd = writes_rd;
        make_uop = result;
    endfunction

    task automatic clear_events;
        decode_valid = 2'b00;
        decode_data_0 = '0;
        decode_data_1 = '0;
        commit_valid = 2'b00;
        commit_arch_rd_0 = '0;
        commit_new_phys_0 = '0;
        commit_old_phys_0 = '0;
        commit_arch_rd_1 = '0;
        commit_new_phys_1 = '0;
        commit_old_phys_1 = '0;
        wb_bus_0 = '0;
        wb_bus_1 = '0;
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        rename_ready = 2'b00;
        clear_events();

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1ns;
        if (free_count != 7'd32) begin
            $fatal(1, "reset free-list count mismatch: %0d", free_count);
        end

        decode_data_0 = make_uop(OP_ADDI, 5'd0, 5'd0, 5'd5,
                                 1'b1, 1'b0, 1'b1);
        decode_data_1 = make_uop(OP_ADD, 5'd5, 5'd3, 5'd6,
                                 1'b1, 1'b1, 1'b1);
        decode_valid = 2'b11;
        #1ns;
        if ((rename_valid != 2'b11) || (decode_ready != 2'b00) ||
            (rename_data_0.phy_rd != 6'd32) ||
            (rename_data_0.stale_phy_rd != 6'd5) ||
            (rename_data_1.phy_rd != 6'd33) ||
            (rename_data_1.phy_rs1 != 6'd32) ||
            rename_data_1.ready_rs1 ||
            (rename_data_1.phy_rs2 != 6'd3) ||
            !rename_data_1.ready_rs2) begin
            $fatal(1, "dual rename or same-bundle RAW dependency failed");
        end

        @(posedge clk);
        #1ns;
        if (free_count != 7'd32) begin
            $fatal(1, "backpressure changed rename state");
        end

        @(negedge clk);
        rename_ready = 2'b11;
        @(posedge clk);
        #1ns;
        if (free_count != 7'd30) begin
            $fatal(1, "accepted destinations were not allocated");
        end

        @(negedge clk);
        clear_events();
        decode_data_0 = make_uop(OP_ADD, 5'd5, 5'd6, 5'd0,
                                 1'b1, 1'b1, 1'b0);
        decode_valid = 2'b01;
        #1ns;
        if ((rename_data_0.phy_rs1 != 6'd32) ||
            (rename_data_0.phy_rs2 != 6'd33) ||
            rename_data_0.ready_rs1 || rename_data_0.ready_rs2) begin
            $fatal(1, "speculative RAT or destination readiness was lost");
        end

        wb_bus_0.valid = 1'b1;
        wb_bus_0.phy_rd = 6'd32;
        wb_bus_0.value = 32'h1234_5678;
        #1ns;
        if (!rename_data_0.ready_rs1 || rename_data_0.ready_rs2) begin
            $fatal(1, "same-cycle writeback readiness bypass failed");
        end
        @(posedge clk);
        @(negedge clk);
        wb_bus_0 = '0;
        #1ns;
        if (!rename_data_0.ready_rs1) begin
            $fatal(1, "writeback did not persist physical readiness");
        end

        wb_bus_1.valid = 1'b1;
        wb_bus_1.phy_rd = 6'd33;
        @(posedge clk);
        @(negedge clk);
        clear_events();
        commit_valid = 2'b11;
        commit_arch_rd_0 = 5'd5;
        commit_new_phys_0 = 6'd32;
        commit_old_phys_0 = 6'd5;
        commit_arch_rd_1 = 5'd6;
        commit_new_phys_1 = 6'd33;
        commit_old_phys_1 = 6'd6;
        @(posedge clk);
        #1ns;
        if (free_count != 7'd32) begin
            $fatal(1, "commit did not release stale physical registers");
        end

        @(negedge clk);
        clear_events();
        decode_data_0 = make_uop(OP_ADDI, 5'd0, 5'd0, 5'd5,
                                 1'b0, 1'b0, 1'b1);
        decode_data_1 = make_uop(OP_ADDI, 5'd0, 5'd0, 5'd5,
                                 1'b0, 1'b0, 1'b1);
        decode_valid = 2'b11;
        #1ns;
        if ((rename_data_0.phy_rd != 6'd5) ||
            (rename_data_0.stale_phy_rd != 6'd32) ||
            (rename_data_1.phy_rd != 6'd6) ||
            (rename_data_1.stale_phy_rd != 6'd5)) begin
            $fatal(1, "same-bundle WAW stale mappings were incorrect");
        end
        @(posedge clk);

        @(negedge clk);
        clear_events();
        flush = 1'b1;
        #1ns;
        if ((rename_valid != 2'b00) || (decode_ready != 2'b00)) begin
            $fatal(1, "flush did not suppress rename transfers");
        end
        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        decode_data_0 = make_uop(OP_ADD, 5'd5, 5'd6, 5'd0,
                                 1'b1, 1'b1, 1'b0);
        decode_valid = 2'b01;
        #1ns;
        if ((free_count != 7'd32) ||
            (rename_data_0.phy_rs1 != 6'd32) ||
            (rename_data_0.phy_rs2 != 6'd33) ||
            !rename_data_0.ready_rs1 || !rename_data_0.ready_rs2) begin
            $fatal(1, "flush did not restore committed rename state");
        end

        decode_data_0 = make_uop(OP_ADDI, 5'd0, 5'd0, 5'd0,
                                 1'b1, 1'b0, 1'b1);
        decode_valid = 2'b01;
        #1ns;
        if (rename_data_0.allocates_rd || (rename_data_0.phy_rd != '0) ||
            !rename_data_0.ready_rs1 || (free_count != 7'd32)) begin
            $fatal(1, "architectural x0 consumed a physical register");
        end

        for (integer unsigned i = 0; i < 16; i = i + 1) begin
            @(negedge clk);
            decode_data_0 = make_uop(OP_ADDI, 5'd0, 5'd0, 5'd10,
                                     1'b0, 1'b0, 1'b1);
            decode_data_1 = make_uop(OP_ADDI, 5'd0, 5'd0, 5'd11,
                                     1'b0, 1'b0, 1'b1);
            decode_valid = 2'b11;
            rename_ready = 2'b11;
            #1ns;
            if (rename_valid != 2'b11) begin
                $fatal(1, "rename stalled before exhausting free registers");
            end
            @(posedge clk);
        end

        @(negedge clk);
        #1ns;
        if ((free_count != '0) || (rename_valid != 2'b00) ||
            (decode_ready != 2'b00)) begin
            $fatal(1, "rename did not stall on free-list exhaustion");
        end

        decode_data_0 = make_uop(OP_BEQ, 5'd1, 5'd2, 5'd0,
                                 1'b1, 1'b1, 1'b0);
        decode_valid = 2'b01;
        #1ns;
        if ((rename_valid != 2'b01) || !decode_ready[0]) begin
            $fatal(1, "non-destination instruction stalled on an empty free list");
        end

        $display("rename_tb: PASS");
        $finish;
    end

endmodule : rename_tb
