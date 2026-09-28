/*
这个模块是 CP2 用的基础整数 ALU，后面通过 bus manager 写回。

设计思路：
1. ALU 本体仍然是组合运算。
2. 组合结果先进入一个 1-entry output buffer，再由 bus manager 取走。
3. 如果 buffer 还没被取走，这个 ALU 就不再接受新的 issue。

接口语义：
1. issue_valid + issue_data: 来自 RS / issue stage 的一条候选指令。
2. issue_ready: 当前 ALU 能不能接收这条候选指令。
3. wb_data: output buffer 中当前准备写回的数据。
4. wb_grant: bus manager 这一拍是否真的取走了 wb_data。

当前只支持常规整数运算，不处理：
1. branch / jump
2. load / store 地址生成
3. mul / div
*/
module alu (
    input   logic       clk,
    input   logic       rst,
    input   logic       flush,

    input   logic           issue_valid,
    input   rv32im_types::simple_issue_t issue_data,
    output  logic           issue_ready,

    output  rv32im_types::wb_bus_t wb_data,
    input   logic       wb_grant
);

    logic   [31:0]  a, b;
    logic   [31:0]  result;
    logic           op_supported;
    logic           issue_fire;

    logic signed   [31:0] as, bs;
    logic unsigned [31:0] au, bu;

    rv32im_types::wb_bus_t wb_buf_q, wb_buf_d;

    assign a  = issue_data.value_1;
    assign b  = issue_data.value_2;
    assign as =   signed'(a);
    assign bs =   signed'(b);
    assign au = unsigned'(a);
    assign bu = unsigned'(b);

    always_comb begin
        result = '0;
        op_supported = 1'b1;

        unique case (issue_data.op)
            rv32im_types::OP_ADD,
            rv32im_types::OP_ADDI,
            rv32im_types::OP_AUIPC: result = au + bu;

            rv32im_types::OP_SUB: result = au - bu;

            rv32im_types::OP_XOR,
            rv32im_types::OP_XORI: result = au ^ bu;

            rv32im_types::OP_OR,
            rv32im_types::OP_ORI: result = au | bu;

            rv32im_types::OP_AND,
            rv32im_types::OP_ANDI: result = au & bu;

            rv32im_types::OP_SLL,
            rv32im_types::OP_SLLI: result = au << bu[4:0];

            rv32im_types::OP_SRL,
            rv32im_types::OP_SRLI: result = au >> bu[4:0];

            rv32im_types::OP_SRA,
            rv32im_types::OP_SRAI: result = unsigned'(as >>> bu[4:0]);

            rv32im_types::OP_SLT,
            rv32im_types::OP_SLTI: result = {31'd0, (as < bs)};

            rv32im_types::OP_SLTU,
            rv32im_types::OP_SLTIU: result = {31'd0, (au < bu)};

            rv32im_types::OP_LUI: result = b;

            default: begin
                result = '0;
                op_supported = 1'b0;
            end
        endcase
    end

    always_comb begin
        // Only accept when the output buffer is empty at the start of the cycle.
        // This keeps writeback grant arbitration off the issue-to-result path.
        issue_ready = !flush && op_supported && !wb_buf_q.valid;
        issue_fire = issue_valid && issue_ready;
    end

    always_comb begin
        wb_buf_d = wb_buf_q;

        // bus manager 取走当前结果后，默认把 buffer 清空。
        if (wb_buf_q.valid && wb_grant) begin
            wb_buf_d = '0;
        end

        // 如果这一拍接收到了新的 issue，就把新的结果写进 buffer。
        if (issue_fire) begin
            wb_buf_d.valid  = 1'b1;
            wb_buf_d.phy_rd = issue_data.phy_rd;
            wb_buf_d.value  = result;
        end
    end

    assign wb_data = wb_buf_q;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            wb_buf_q <= '0;
        end else begin
            wb_buf_q <= wb_buf_d;
        end
    end

endmodule : alu
