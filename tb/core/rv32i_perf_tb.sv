module rv32i_perf_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam logic [31:0] RESET_PC = 32'h0000_1000;
    localparam integer unsigned LOOP_ITERATIONS = 100;
    localparam integer unsigned EXPECTED_INSTRET = 2 +
        (2 * LOOP_ITERATIONS) + 1;

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

    logic [31:0] final_x1_value;

    rv32i_cpu #(
        .FRONTEND_QUEUE_DEPTH (8),
        .FETCH_ROB_DEPTH      (4),
        .FETCH_WIDTH          (2),
        .DECODE_WIDTH         (2),
        .DECODE_BUFFER_DEPTH  (4),
        .ENABLE_RV32M         (1'b0),
        .RESET_PC             (RESET_PC),
        .BP_PHT_ENTRIES       (128),
        .BP_RAS_ENTRIES       (4),
        .ROB_DEPTH            (16)
    ) dut (.*);

    always #5ns clk = ~clk;

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [31:0] encode_blt(
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input logic [12:0] imm
    );
        encode_blt = {imm[12], imm[10:5], rs2, rs1, 3'b100,
                      imm[4:1], imm[11], rv32im_types::op_b_branch};
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [31:0] read_instruction(input logic [31:0] addr);
        unique case (addr)
            32'h0000_1000: read_instruction = 32'h0000_0093; // addi x1,x0,0
            32'h0000_1004: read_instruction = 32'h0640_0113; // addi x2,x0,100
            32'h0000_1008: read_instruction = 32'h0010_8093; // addi x1,x1,1
            32'h0000_100c: read_instruction = encode_blt(5'd1, 5'd2,
                                                         13'h1ffc); // -4
            32'h0000_1010: read_instruction = 32'h0000_0073; // ecall
            default:       read_instruction = 32'h0000_0013; // nop
        endcase
    endfunction

    always_comb begin
        imem_rdata_0 = read_instruction(imem_addr_0);
        imem_rdata_1 = read_instruction(imem_addr_1);
        imem_resp_0 = imem_rmask_0 != 4'b0000;
        imem_resp_1 = imem_rmask_1 != 4'b0000;
        dmem_req_ready = 1'b1;
        dmem_resp_valid = 1'b0;
        dmem_resp = '0;
        trap_ready = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            final_x1_value <= '0;
        end else begin
            if (retire_valid[0] && retire_data_0.result.rd_write &&
                (retire_data_0.uop.renamed.decoded.rd == 5'd1)) begin
                final_x1_value <= retire_data_0.result.rd_value;
            end
            if (retire_valid[1] && retire_data_1.result.rd_write &&
                (retire_data_1.uop.renamed.decoded.rd == 5'd1)) begin
                final_x1_value <= retire_data_1.result.rd_value;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (!trap_valid) @(negedge clk);
        #1ns;
        if ((trap_cause != rv32im_types::EXC_ECALL_MMODE) ||
            (trap_pc != 32'h0000_1010)) begin
            $fatal(1, "loop workload did not terminate at ECALL");
        end
        if (perf_instret_count != 64'(EXPECTED_INSTRET) ||
            perf_branch_count != 64'(LOOP_ITERATIONS) ||
            final_x1_value != 32'(LOOP_ITERATIONS)) begin
            $fatal(1, "loop workload architectural result mismatch");
        end
        if (dmem_req_valid)
            $fatal(1, "integer loop unexpectedly issued a data-memory request");

        $display("PERF workload=rv32i_loop iterations=%0d cycles=%0d instret=%0d IPC=%0f CPI=%0f branches=%0d branch_misses=%0d frontend_stall=%0d rob_full=%0d rs_full=%0d",
                 LOOP_ITERATIONS, perf_cycle_count, perf_instret_count,
                 real'(perf_instret_count) / real'(perf_cycle_count),
                 real'(perf_cycle_count) / real'(perf_instret_count),
                 perf_branch_count, perf_branch_mispredict_count,
                 perf_frontend_stall_count, perf_rob_full_count,
                 perf_rs_full_count);
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk);
        $fatal(1, "RV32I performance workload timed out");
    end

    logic _unused_memory_outputs;
    assign _unused_memory_outputs = &{1'b0, dmem_req, dmem_resp_ready};

endmodule : rv32i_perf_tb
