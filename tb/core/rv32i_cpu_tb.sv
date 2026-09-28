module rv32i_cpu_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam logic [31:0] RESET_PC = 32'h0000_1000;

    logic clk;
    logic rst;
    logic [31:0] imem_addr_0;
    logic [3:0] imem_rmask_0;
    logic [31:0] imem_rdata_0;
    logic imem_resp_0;
    logic [31:0] imem_addr_1;
    logic [3:0] imem_rmask_1;
    logic [31:0] imem_rdata_1;
    logic imem_resp_1;
    logic dmem_req_valid;
    logic dmem_req_ready;
    rv32im_types::dcache_cpu_req_t dmem_req;
    logic dmem_resp_valid;
    logic dmem_resp_ready;
    rv32im_types::dcache_cpu_resp_t dmem_resp;
    logic trap_valid;
    logic trap_ready;
    rv32im_types::exception_cause_t trap_cause;
    rv32im_types::xlen_t trap_pc;
    logic [1:0] retire_valid;
    rv32im_types::rob_commit_t retire_data_0;
    rv32im_types::rob_commit_t retire_data_1;
    logic [63:0] perf_cycle_count;
    logic [63:0] perf_instret_count;
    logic [63:0] perf_branch_count;
    logic [63:0] perf_branch_mispredict_count;
    logic [63:0] perf_frontend_stall_count;
    logic [63:0] perf_rob_full_count;
    logic [63:0] perf_rs_full_count;

    logic [31:0] data_word;
    integer unsigned retired_count;
    logic [31:0] retired_pc [16];
    logic [31:0] retired_value [16];
    logic retired_rd_write [16];

    rv32i_cpu #(
        .FRONTEND_QUEUE_DEPTH (4),
        .FETCH_ROB_DEPTH      (4),
        .FETCH_WIDTH          (2),
        .DECODE_WIDTH         (2),
        .RESET_PC             (RESET_PC),
        .BP_PHT_ENTRIES       (8),
        .BP_RAS_ENTRIES       (4),
        .ROB_DEPTH            (8)
    ) dut (.*);

    always #5ns clk = ~clk;

    function automatic logic [31:0] read_instruction(input logic [31:0] addr);
        unique case (addr)
            32'h0000_1000: read_instruction = 32'h0050_0093; // addi x1,x0,5
            32'h0000_1004: read_instruction = 32'h0070_8113; // addi x2,x1,7
            32'h0000_1008: read_instruction = 32'h0020_81b3; // add  x3,x1,x2
            32'h0000_100c: read_instruction = 32'h0030_2023; // sw   x3,0(x0)
            32'h0000_1010: read_instruction = 32'h0000_000f; // fence
            32'h0000_1014: read_instruction = 32'h0000_2203; // lw   x4,0(x0)
            32'h0000_1018: read_instruction = 32'h0032_1663; // bne  x4,x3,+12
            32'h0000_101c: read_instruction = 32'h02a0_0293; // addi x5,x0,42
            32'h0000_1020: read_instruction = 32'h0080_006f; // jal  x0,+8
            32'h0000_1024: read_instruction = 32'h0630_0293; // wrong-path addi
            32'h0000_1028: read_instruction = 32'h0000_0073; // ecall
            default:       read_instruction = 32'h0000_0013; // nop
        endcase
    endfunction

    always_comb begin
        imem_rdata_0 = read_instruction(imem_addr_0);
        imem_rdata_1 = read_instruction(imem_addr_1);
        imem_resp_0 = imem_rmask_0 != 4'b0000;
        imem_resp_1 = imem_rmask_1 != 4'b0000;
        dmem_req_ready = !dmem_resp_valid;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            dmem_resp_valid <= 1'b0;
            dmem_resp <= '0;
            data_word <= '0;
        end else begin
            if (dmem_resp_valid && dmem_resp_ready) begin
                dmem_resp_valid <= 1'b0;
            end
            if (dmem_req_valid && dmem_req_ready) begin
                dmem_resp_valid <= 1'b1;
                dmem_resp.id <= dmem_req.id;
                dmem_resp.addr <= dmem_req.addr;
                dmem_resp.rmask <= dmem_req.rmask;
                dmem_resp.wmask <= dmem_req.wmask;
                dmem_resp.rdata <= data_word;
                for (integer unsigned byte_index = 0;
                     byte_index < 4; byte_index++) begin
                    if (dmem_req.wmask[byte_index]) begin
                        data_word[byte_index * 8 +: 8] <=
                            dmem_req.wdata[byte_index * 8 +: 8];
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (retire_valid[0]) begin
                retired_pc[retired_count] <=
                    retire_data_0.uop.renamed.decoded.fetch.pc;
                retired_value[retired_count] <= retire_data_0.result.rd_value;
                retired_rd_write[retired_count] <= retire_data_0.result.rd_write;
                retired_count <= retired_count + 1;
            end
            if (retire_valid[1]) begin
                retired_pc[retired_count + retire_valid[0]] <=
                    retire_data_1.uop.renamed.decoded.fetch.pc;
                retired_value[retired_count + retire_valid[0]] <=
                    retire_data_1.result.rd_value;
                retired_rd_write[retired_count + retire_valid[0]] <=
                    retire_data_1.result.rd_write;
                retired_count <= retired_count + retire_valid[0] + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        trap_ready = 1'b0;
        retired_count = 0;
        for (integer unsigned i = 0; i < 16; i++) begin
            retired_pc[i] = '0;
            retired_value[i] = '0;
            retired_rd_write[i] = 1'b0;
        end

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (!trap_valid) @(negedge clk);
        #1ns;
        if (trap_cause != rv32im_types::EXC_ECALL_MMODE ||
            trap_pc != 32'h0000_1028)
            $fatal(1, "program did not stop at the expected ECALL");
        if (retired_count != 10)
            $fatal(1, "expected 10 retired instructions, got %0d", retired_count);
        if (data_word != 32'd17)
            $fatal(1, "store result mismatch");
        if (retired_pc[4] != 32'h0000_1010 || retired_rd_write[4])
            $fatal(1, "FENCE retirement mismatch");
        if (retired_pc[5] != 32'h0000_1014 || !retired_rd_write[5] ||
            retired_value[5] != 32'd17)
            $fatal(1, "load result mismatch");
        if (retired_pc[7] != 32'h0000_101c || !retired_rd_write[7] ||
            retired_value[7] != 32'd42)
            $fatal(1, "branch recovery path mismatch");
        for (integer unsigned i = 0; i < retired_count; i++) begin
            if (retired_pc[i] == 32'h0000_1024)
                $fatal(1, "wrong-path instruction retired");
        end
        if (perf_instret_count != 64'd10 || perf_branch_count != 64'd2 ||
            perf_branch_mispredict_count != 64'd1)
            $fatal(1, "program performance counters mismatch");

        $display("rv32i_cpu_tb: PASS cycles=%0d instret=%0d CPI=%0f frontend_stall=%0d rob_full=%0d rs_full=%0d",
                 perf_cycle_count, perf_instret_count,
                 real'(perf_cycle_count) / real'(perf_instret_count),
                 perf_frontend_stall_count, perf_rob_full_count,
                 perf_rs_full_count);
        $finish;
    end

    initial begin
        repeat (500) @(posedge clk);
        $fatal(1, "CPU program timed out");
    end

endmodule : rv32i_cpu_tb
