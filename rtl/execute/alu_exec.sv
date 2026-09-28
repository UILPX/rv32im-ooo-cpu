module alu_exec (
    input   logic                           clk,
    input   logic                           rst,
    input   logic                           flush,

    input   logic                           issue_valid,
    /* verilator lint_off UNUSEDSIGNAL */
    input   rv32im_types::res_stat_t        issue_data,
    /* verilator lint_on UNUSEDSIGNAL */
    output  logic                           issue_ready,

    output  rv32im_types::wb_bus_t          wb_data,
    input   logic                           wb_grant,

    output  logic                           result_valid,
    output  rv32im_types::rob_complete_t    complete_data
);

    rv32im_types::simple_issue_t alu_issue_data;
    rv32im_types::wb_bus_t alu_wb_data;
    logic alu_issue_ready;
    logic alu_wb_grant;
    logic issue_fire;
    logic complete_fire;
    logic tag_valid_q;
    rv32im_types::rob_tag_t tag_q;

    always_comb begin
        alu_issue_data = '0;
        alu_issue_data.op = issue_data.op;
        alu_issue_data.phy_rd = issue_data.phy_rd;
        alu_issue_data.value_1 = issue_data.value_1;
        alu_issue_data.value_2 = issue_data.value_2;

        issue_ready = alu_issue_ready;
        issue_fire = issue_valid && issue_ready;
        result_valid = !flush && alu_wb_data.valid && tag_valid_q;

        wb_data = alu_wb_data;
        if (flush || (alu_wb_data.phy_rd == '0)) begin
            wb_data.valid = 1'b0;
        end

        alu_wb_grant = !flush && alu_wb_data.valid &&
            ((alu_wb_data.phy_rd == '0) || wb_grant);
        complete_fire = alu_wb_grant && tag_valid_q;
        complete_data = '0;
        complete_data.valid = complete_fire;
        complete_data.rob_tag = tag_q;
        complete_data.rd_write = complete_fire && (alu_wb_data.phy_rd != '0);
        complete_data.rd_value = alu_wb_data.value;
    end

    alu core (
        .clk,
        .rst,
        .flush,
        .issue_valid,
        .issue_data  (alu_issue_data),
        .issue_ready (alu_issue_ready),
        .wb_data     (alu_wb_data),
        .wb_grant    (alu_wb_grant)
    );

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            tag_valid_q <= 1'b0;
            tag_q <= '0;
        end else begin
            if (complete_fire) begin
                tag_valid_q <= 1'b0;
            end
            if (issue_fire) begin
                tag_valid_q <= 1'b1;
                tag_q <= issue_data.rob_tag;
            end
        end
    end

endmodule : alu_exec
