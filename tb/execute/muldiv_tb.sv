module muldiv_tb #(
    parameter integer unsigned MUL_STAGES = 2,
    parameter integer unsigned DIV_CYC    = 11
);
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic           clk;
    logic           rst;
    logic           flush;
    logic           issue_valid;
    simple_issue_t  issue_data;
    logic           issue_ready;
    wb_bus_t        mul_wb;
    logic           mul_wb_grant;
    wb_bus_t        div_wb;
    logic           div_wb_grant;

    muldiv #(
        .MUL_STAGES (MUL_STAGES),
        .DIV_CYC    (DIV_CYC)
    ) dut (
        .clk,
        .rst,
        .flush,
        .issue_valid,
        .issue_data,
        .issue_ready,
        .mul_wb,
        .mul_wb_grant,
        .div_wb,
        .div_wb_grant
    );

    always #5ns clk = ~clk;

    function automatic logic is_mul(input logic [4:0] op);
        return (op == OP_MUL) || (op == OP_MULH) ||
               (op == OP_MULHSU) || (op == OP_MULHU);
    endfunction

    task automatic issue_request(
        input logic [4:0]               op,
        input logic [31:0]              a,
        input logic [31:0]              b,
        input logic [PHYS_REG_BITS-1:0] phy_rd
    );
        logic accepted;
        integer unsigned timeout;

        @(negedge clk);
        issue_valid       = 1'b1;
        issue_data.op     = op;
        issue_data.value_1 = a;
        issue_data.value_2 = b;
        issue_data.phy_rd = phy_rd;

        accepted = 1'b0;
        timeout = 0;
        while (!accepted) begin
            @(posedge clk);
            accepted = issue_ready;
            timeout = timeout + 1;
            if (timeout > DIV_CYC + 20) begin
                $fatal(1, "issue request timed out for op %0d", op);
            end
            @(negedge clk);
        end

        issue_valid = 1'b0;
    endtask

    task automatic wait_result(
        input logic [4:0]               op,
        input logic [31:0]              expected_value,
        input logic [PHYS_REG_BITS-1:0] expected_phy_rd
    );
        wb_bus_t observed;
        integer unsigned timeout;

        timeout = 0;
        observed = '0;

        if (is_mul(op)) begin
            while (!mul_wb.valid) begin
                @(posedge clk);
                #1ns;
                timeout = timeout + 1;
                if (timeout > MUL_STAGES + 10) begin
                    $fatal(1, "multiply result timed out for op %0d", op);
                end
            end
            observed = mul_wb;
        end else begin
            while (!div_wb.valid) begin
                @(posedge clk);
                #1ns;
                timeout = timeout + 1;
                if (timeout > DIV_CYC + 10) begin
                    $fatal(1, "divide result timed out for op %0d", op);
                end
            end
            observed = div_wb;
        end

        if ((observed.value !== expected_value) ||
            (observed.phy_rd !== expected_phy_rd)) begin
            $fatal(1,
                   "op %0d expected rd=%0d value=%0h, got rd=%0d value=%0h",
                   op, expected_phy_rd, expected_value,
                   observed.phy_rd, observed.value);
        end

        repeat (2) begin
            @(posedge clk);
            #1ns;
            if (is_mul(op)) begin
                if (mul_wb !== observed) begin
                    $fatal(1, "multiply writeback changed under backpressure");
                end
            end else if (div_wb !== observed) begin
                $fatal(1, "divide writeback changed under backpressure");
            end
        end

        @(negedge clk);
        if (is_mul(op)) begin
            mul_wb_grant = 1'b1;
        end else begin
            div_wb_grant = 1'b1;
        end

        @(posedge clk);
        #1ns;
        if ((is_mul(op) && mul_wb.valid) || (!is_mul(op) && div_wb.valid)) begin
            $fatal(1, "writeback did not clear after grant");
        end

        @(negedge clk);
        mul_wb_grant = 1'b0;
        div_wb_grant = 1'b0;
    endtask

    task automatic run_case(
        input logic [4:0]               op,
        input logic [31:0]              a,
        input logic [31:0]              b,
        input logic [31:0]              expected_value,
        input logic [PHYS_REG_BITS-1:0] phy_rd
    );
        issue_request(op, a, b, phy_rd);
        wait_result(op, expected_value, phy_rd);
    endtask

    task automatic test_parallel_results;
        wb_bus_t held_mul;
        wb_bus_t held_div;
        integer unsigned timeout;

        issue_request(OP_DIVU, 32'd100, 32'd7, 6'd20);
        issue_request(OP_MULHU, 32'hffff_ffff, 32'd2, 6'd21);

        timeout = 0;
        while (!mul_wb.valid || !div_wb.valid) begin
            @(posedge clk);
            #1ns;
            timeout = timeout + 1;
            if (timeout > DIV_CYC + MUL_STAGES + 10) begin
                $fatal(1, "parallel mul/div results timed out");
            end
        end

        held_mul = mul_wb;
        held_div = div_wb;
        if (!held_mul.valid || !held_div.valid ||
            (held_mul.value !== 32'd1) || (held_mul.phy_rd !== 6'd21) ||
            (held_div.value !== 32'd14) || (held_div.phy_rd !== 6'd20)) begin
            $fatal(1, "parallel mul/div results were incorrect");
        end

        @(negedge clk);
        mul_wb_grant = 1'b1;
        div_wb_grant = 1'b1;
        @(posedge clk);
        #1ns;
        if (mul_wb.valid || div_wb.valid) begin
            $fatal(1, "parallel grants did not clear both results");
        end

        @(negedge clk);
        mul_wb_grant = 1'b0;
        div_wb_grant = 1'b0;
    endtask

    task automatic test_flush;
        issue_request(OP_DIVU, 32'hffff_fff1, 32'd17, 6'd30);
        issue_request(OP_MUL, 32'd1234, 32'd5678, 6'd31);

        @(negedge clk);
        flush = 1'b1;
        @(posedge clk);
        #1ns;
        if (mul_wb.valid || div_wb.valid || issue_ready) begin
            $fatal(1, "flush did not suppress muldiv state");
        end

        @(negedge clk);
        flush = 1'b0;
        issue_data.op = OP_DIVU;
        #1ns;
        if (!issue_ready) begin
            $fatal(1, "divider was not ready immediately after flush");
        end

        run_case(OP_DIVU, 32'd81, 32'd9, 32'd9, 6'd32);
    endtask

    initial begin
        clk          = 1'b0;
        rst          = 1'b1;
        flush        = 1'b0;
        issue_valid  = 1'b0;
        issue_data   = '0;
        mul_wb_grant = 1'b0;
        div_wb_grant = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        run_case(OP_MUL,    32'd7,          32'd9,          32'd63,        6'd1);
        run_case(OP_MULH,   32'hffff_fffe,  32'd3,          32'hffff_ffff, 6'd2);
        run_case(OP_MULHSU, 32'hffff_fffe,  32'h8000_0000,  32'hffff_ffff, 6'd3);
        run_case(OP_MULHU,  32'hffff_ffff,  32'd2,          32'd1,         6'd4);

        run_case(OP_DIV,    32'hffff_ffec,  32'd3,          32'hffff_fffa, 6'd5);
        run_case(OP_DIVU,   32'hffff_ffff,  32'd3,          32'h5555_5555, 6'd6);
        run_case(OP_REM,    32'hffff_ffec,  32'd3,          32'hffff_fffe, 6'd7);
        run_case(OP_REMU,   32'd20,         32'd3,          32'd2,         6'd8);

        run_case(OP_DIV,    32'd123,        32'd0,          32'hffff_ffff, 6'd9);
        run_case(OP_REM,    32'hffff_ff85,  32'd0,          32'hffff_ff85, 6'd10);
        run_case(OP_DIV,    32'h8000_0000,  32'hffff_ffff,  32'h8000_0000, 6'd11);
        run_case(OP_REM,    32'h8000_0000,  32'hffff_ffff,  32'd0,         6'd12);

        test_parallel_results();
        test_flush();

        $display("PASS: muldiv MUL_STAGES=%0d DIV_CYC=%0d", MUL_STAGES, DIV_CYC);
        $finish;
    end
endmodule : muldiv_tb
