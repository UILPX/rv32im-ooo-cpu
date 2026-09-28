module reservation_station_tb;
    import rv32im_types::*;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer unsigned DISPATCH_PORTS = 2;
    localparam integer unsigned WB_PORTS = 2;

    logic                              clk;
    logic                              rst;
    logic                              flush;
    logic [DISPATCH_PORTS-1:0]         select;
    logic [DISPATCH_PORTS-1:0]         port_bus1_sel;
    res_stat_t                         dispatch_data_0;
    res_stat_t                         dispatch_data_1;
    logic [DISPATCH_PORTS-1:0]         port_ready;
    wb_bus_t                           wb_bus_0;
    wb_bus_t                           wb_bus_1;
    logic                              issue_valid;
    res_stat_t                         issue_data;
    logic                              issue_grant;
    logic                              _unused_issue_data;

    reservation_station #(
        .DEPTH(4),
        .DISPATCH_PORTS(DISPATCH_PORTS),
        .WB_PORTS(WB_PORTS)
    ) dut (.*);

    always #5ns clk = ~clk;

    assign _unused_issue_data = &{1'b0, issue_data};

    function automatic res_stat_t make_entry(
        input rob_tag_t tag,
        input phys_reg_t rs1,
        input phys_reg_t rs2,
        input logic ready_1,
        input logic ready_2
    );
        res_stat_t entry;
        entry = '0;
        entry.op = OP_ADD;
        entry.rob_tag = tag;
        entry.phy_rs1 = rs1;
        entry.phy_rs2 = rs2;
        entry.ready_1 = ready_1;
        entry.ready_2 = ready_2;
        entry.value_1 = 32'h11110000 | xlen_t'(tag);
        entry.value_2 = 32'h22220000 | xlen_t'(tag);
        return entry;
    endfunction

    task automatic clear_inputs;
        select = '0;
        port_bus1_sel = '0;
        dispatch_data_0 = '0;
        dispatch_data_1 = '0;
        wb_bus_0 = '0;
        wb_bus_1 = '0;
        issue_grant = 1'b0;
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        clear_inputs();

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        dispatch_data_0 = make_entry(rob_tag_t'(1), phys_reg_t'(10), phys_reg_t'(11), 1'b0, 1'b1);
        dispatch_data_1 = make_entry(rob_tag_t'(2), phys_reg_t'(12), phys_reg_t'(13), 1'b1, 1'b1);
        select = 2'b11;
        port_bus1_sel = 2'b10;
        #1ns;
        if (port_ready !== 2'b11) begin
            $fatal(1, "empty reservation station did not accept two entries");
        end

        @(posedge clk);
        #1ns;
        clear_inputs();
        if (!issue_valid || (issue_data.rob_tag !== rob_tag_t'(2))) begin
            $fatal(1, "reservation station did not choose the oldest ready entry");
        end

        @(negedge clk);
        issue_grant = 1'b1;
        @(posedge clk);
        #1ns;
        clear_inputs();
        if (issue_valid) begin
            $fatal(1, "blocked older entry unexpectedly issued before wakeup");
        end

        @(negedge clk);
        wb_bus_0.valid = 1'b1;
        wb_bus_0.phy_rd = phys_reg_t'(10);
        wb_bus_0.value = 32'hdeadbeef;
        issue_grant = 1'b1;
        #1ns;
        if (!issue_valid || (issue_data.rob_tag !== rob_tag_t'(1)) ||
            (issue_data.value_1 !== 32'hdeadbeef)) begin
            $fatal(1, "same-cycle CDB wakeup did not produce the issue candidate");
        end

        @(posedge clk);
        #1ns;
        clear_inputs();
        if (issue_valid || (port_ready !== 2'b11)) begin
            $fatal(1, "issued entries were not removed and compacted");
        end

        @(negedge clk);
        dispatch_data_0 = make_entry(rob_tag_t'(3), phys_reg_t'(20), phys_reg_t'(21), 1'b0, 1'b1);
        select[0] = 1'b1;
        wb_bus_1.valid = 1'b1;
        wb_bus_1.phy_rd = phys_reg_t'(20);
        wb_bus_1.value = 32'hcafef00d;
        @(posedge clk);
        #1ns;
        clear_inputs();
        if (!issue_valid || (issue_data.value_1 !== 32'hcafef00d)) begin
            $fatal(1, "newly dispatched entry missed a same-cycle broadcast");
        end

        @(negedge clk);
        flush = 1'b1;
        issue_grant = 1'b1;
        #1ns;
        if (issue_valid || (port_ready !== '0)) begin
            $fatal(1, "flush did not suppress reservation-station transfers");
        end

        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        issue_grant = 1'b0;
        #1ns;
        if (issue_valid || (port_ready !== 2'b11)) begin
            $fatal(1, "flush did not clear the reservation station");
        end

        $display("reservation_station_tb: PASS");
        $finish;
    end
endmodule : reservation_station_tb
