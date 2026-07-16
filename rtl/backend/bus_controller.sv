/*
这个模块是 CP2 使用的写回总线控制器。

作用：
1. 收集 alu0、alu1、mem、branch、mul、div 六个执行单元的完成结果。
2. 每拍最多向外驱动两条共享 writeback bus。
3. 给每个结果生产者返回 grant，告诉它这拍自己的结果有没有被总线接收。

当前仲裁策略：
1. 长延迟单元 mul/div 的结果优先级最高。
2. mem 写回优先级低于 mul/div，但高于 branch 和普通整数 ALU。
3. branch 写回优先级低于 mem，但高于普通整数 ALU。
4. 如果 mul 和 div 同拍都完成，就直接占满两条 bus。
5. 如果只有一个 mul/div 完成，另一条 bus 优先给 mem，再给 branch，最后给 ALU。
6. 如果没有 mul/div 完成，就优先给 mem，再给 branch，最后从两个 ALU 中补满剩余 bus。
7. ALU 之间当前采用固定优先级：alu0 高于 alu1。

实现假设：
1. 这是纯组合逻辑模块，本身不带寄存器。
2. 每个生产者都会把自己的结果保持住，直到对应 grant 拉高为止。
3. 现在的 wb_bus_t 里没有年龄信息，所以这里不能做 oldest-first，只能先用固定优先级。
*/
module bus_controller
import rv32im_types::*;
(
    input   logic               flush,

    input   wb_bus_t            alu_wb [2],
    output  logic       [1:0]   alu_wb_grant,

    input   wb_bus_t            mem_wb,
    output  logic               mem_wb_grant,

    input   wb_bus_t            br_wb,
    output  logic               br_wb_grant,

    input   wb_bus_t            mul_wb,
    input   wb_bus_t            div_wb,
    output  logic               mul_wb_grant,
    output  logic               div_wb_grant,

    output  wb_bus_t            wb_bus [2]
);

    always_comb begin
        wb_bus[0] = '0;
        wb_bus[1] = '0;

        alu_wb_grant = '0;
        mem_wb_grant = 1'b0;
        br_wb_grant = 1'b0;
        mul_wb_grant = 1'b0;
        div_wb_grant = 1'b0;

        if (!flush) begin
            if (mul_wb.valid && div_wb.valid) begin
                wb_bus[0] = mul_wb;
                wb_bus[1] = div_wb;

                mul_wb_grant = 1'b1;
                div_wb_grant = 1'b1;
            end else if (mul_wb.valid) begin
                wb_bus[0] = mul_wb;
                mul_wb_grant = 1'b1;

                if (mem_wb.valid) begin
                    wb_bus[1] = mem_wb;
                    mem_wb_grant = 1'b1;
                end else if (br_wb.valid) begin
                    wb_bus[1] = br_wb;
                    br_wb_grant = 1'b1;
                end else if (alu_wb[0].valid) begin
                    wb_bus[1] = alu_wb[0];
                    alu_wb_grant[0] = 1'b1;
                end else if (alu_wb[1].valid) begin
                    wb_bus[1] = alu_wb[1];
                    alu_wb_grant[1] = 1'b1;
                end
            end else if (div_wb.valid) begin
                wb_bus[0] = div_wb;
                div_wb_grant = 1'b1;

                if (mem_wb.valid) begin
                    wb_bus[1] = mem_wb;
                    mem_wb_grant = 1'b1;
                end else if (br_wb.valid) begin
                    wb_bus[1] = br_wb;
                    br_wb_grant = 1'b1;
                end else if (alu_wb[0].valid) begin
                    wb_bus[1] = alu_wb[0];
                    alu_wb_grant[0] = 1'b1;
                end else if (alu_wb[1].valid) begin
                    wb_bus[1] = alu_wb[1];
                    alu_wb_grant[1] = 1'b1;
                end
            end else if (mem_wb.valid) begin
                wb_bus[0] = mem_wb;
                mem_wb_grant = 1'b1;

                if (br_wb.valid) begin
                    wb_bus[1] = br_wb;
                    br_wb_grant = 1'b1;
                end else if (alu_wb[0].valid) begin
                    wb_bus[1] = alu_wb[0];
                    alu_wb_grant[0] = 1'b1;
                end else if (alu_wb[1].valid) begin
                    wb_bus[1] = alu_wb[1];
                    alu_wb_grant[1] = 1'b1;
                end
            end else if (br_wb.valid) begin
                wb_bus[0] = br_wb;
                br_wb_grant = 1'b1;

                if (alu_wb[0].valid) begin
                    wb_bus[1] = alu_wb[0];
                    alu_wb_grant[0] = 1'b1;
                end else if (alu_wb[1].valid) begin
                    wb_bus[1] = alu_wb[1];
                    alu_wb_grant[1] = 1'b1;
                end
            end else begin
                if (alu_wb[0].valid) begin
                    wb_bus[0] = alu_wb[0];
                    alu_wb_grant[0] = 1'b1;
                end

                if (alu_wb[1].valid) begin
                    if (alu_wb_grant[0]) begin
                        wb_bus[1] = alu_wb[1];
                    end else begin
                        wb_bus[0] = alu_wb[1];
                    end
                    alu_wb_grant[1] = 1'b1;
                end
            end
        end
    end

endmodule : bus_controller
