module backend_core_tb;
    timeunit 1ns;
    timeprecision 1ps;

    logic clk;
    logic rst;
    logic [1:0] decode_valid;
    rv32im_types::decoded_uop_t decode_data_0;
    rv32im_types::decoded_uop_t decode_data_1;
    logic [1:0] decode_ready;
    logic frontend_stall;
    logic mem_req_valid;
    logic mem_req_ready;
    rv32im_types::dcache_cpu_req_t mem_req;
    logic mem_resp_valid;
    logic mem_resp_ready;
    rv32im_types::dcache_cpu_resp_t mem_resp;
    logic flush;
    logic redirect_valid;
    rv32im_types::xlen_t redirect_pc;
    logic bp_update_valid;
    rv32im_types::xlen_t bp_update_pc;
    logic bp_update_is_cond_branch;
    logic bp_update_is_jalr;
    logic bp_update_is_call;
    logic bp_update_is_return;
    logic bp_update_taken;
    rv32im_types::xlen_t bp_update_target;
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

    integer unsigned retired_count;
    logic [31:0] retired_pc [16];
    logic [31:0] retired_value [16];
    logic retired_rd_write [16];
    logic retired_mem_valid [16];
    logic [3:0] retired_mem_rmask [16];
    logic [3:0] retired_mem_wmask [16];
    logic [31:0] retired_mem_rdata [16];
    logic [31:0] retired_mem_wdata [16];
    logic [31:0] memory_word;
    logic saw_bp_update;
    logic [31:0] observed_bp_pc;
    logic observed_bp_is_cond_branch;
    logic observed_bp_is_jalr;
    logic observed_bp_is_call;
    logic observed_bp_is_return;
    logic observed_bp_taken;
    logic [31:0] observed_bp_target;

    backend_core #(
        .ROB_DEPTH             (8),
        .DISPATCH_BUFFER_DEPTH (4),
        .INT_RS_DEPTH          (4),
        .BRANCH_RS_DEPTH       (4)
    ) dut (.*);

    always #5ns clk = ~clk;

    assign frontend_stall = decode_valid[0] && !decode_ready[0];

    assign mem_req_ready = !mem_resp_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_resp_valid <= 1'b0;
            mem_resp <= '0;
            memory_word <= '0;
        end else begin
            if (mem_resp_valid && mem_resp_ready) begin
                mem_resp_valid <= 1'b0;
            end
            if (mem_req_valid && mem_req_ready) begin
                mem_resp_valid <= 1'b1;
                mem_resp.id <= mem_req.id;
                mem_resp.addr <= mem_req.addr;
                mem_resp.rmask <= mem_req.rmask;
                mem_resp.wmask <= mem_req.wmask;
                mem_resp.rdata <= memory_word;
                for (integer unsigned byte_index = 0;
                     byte_index < 4; byte_index++) begin
                    if (mem_req.wmask[byte_index]) begin
                        memory_word[byte_index * 8 +: 8] <=
                            mem_req.wdata[byte_index * 8 +: 8];
                    end
                end
            end
        end
    end

    function automatic rv32im_types::decoded_uop_t make_uop(
        input rv32im_types::uop_t op,
        input rv32im_types::fu_class_t fu_class,
        input logic [31:0] pc,
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input logic [4:0] rd,
        input logic [31:0] imm,
        input logic uses_rs1,
        input logic uses_rs2,
        input logic writes_rd
    );
        rv32im_types::decoded_uop_t result;
        begin
            result = '0;
            result.fetch.pc = pc;
            result.fetch.inst = 32'h0000_0013;
            result.fetch.rvfi_order = 64'(pc) >> 2;
            result.fetch.pred_pc = pc + 32'd4;
            result.op = op;
            result.fu_class = fu_class;
            result.rs1 = rs1;
            result.rs2 = rs2;
            result.rd = rd;
            result.imm = imm;
            result.uses_rs1 = uses_rs1;
            result.uses_rs2 = uses_rs2;
            result.writes_rd = writes_rd;
            make_uop = result;
        end
    endfunction

    task automatic send_one(input rv32im_types::decoded_uop_t uop);
        @(negedge clk);
        decode_valid = 2'b01;
        decode_data_0 = uop;
        decode_data_1 = '0;
        while (!decode_ready[0]) begin
            @(negedge clk);
        end
        @(posedge clk);
        @(negedge clk);
        decode_valid = 2'b00;
        decode_data_0 = '0;
    endtask

    task automatic send_two(
        input rv32im_types::decoded_uop_t uop_0,
        input rv32im_types::decoded_uop_t uop_1
    );
        @(negedge clk);
        decode_valid = 2'b11;
        decode_data_0 = uop_0;
        decode_data_1 = uop_1;
        while (!decode_ready[1]) begin
            @(negedge clk);
        end
        @(posedge clk);
        @(negedge clk);
        decode_valid = 2'b00;
        decode_data_0 = '0;
        decode_data_1 = '0;
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            if (bp_update_valid) begin
                saw_bp_update <= 1'b1;
                observed_bp_pc <= bp_update_pc;
                observed_bp_is_cond_branch <= bp_update_is_cond_branch;
                observed_bp_is_jalr <= bp_update_is_jalr;
                observed_bp_is_call <= bp_update_is_call;
                observed_bp_is_return <= bp_update_is_return;
                observed_bp_taken <= bp_update_taken;
                observed_bp_target <= bp_update_target;
            end
            if (retire_valid[0]) begin
                retired_pc[retired_count] <=
                    retire_data_0.uop.renamed.decoded.fetch.pc;
                retired_value[retired_count] <= retire_data_0.result.rd_value;
                retired_rd_write[retired_count] <= retire_data_0.result.rd_write;
                retired_mem_valid[retired_count] <= retire_data_0.result.mem_valid;
                retired_mem_rmask[retired_count] <= retire_data_0.result.mem_rmask;
                retired_mem_wmask[retired_count] <= retire_data_0.result.mem_wmask;
                retired_mem_rdata[retired_count] <= retire_data_0.result.mem_rdata;
                retired_mem_wdata[retired_count] <= retire_data_0.result.mem_wdata;
                retired_count <= retired_count + 1;
            end
            if (retire_valid[1]) begin
                retired_pc[retired_count + retire_valid[0]] <=
                    retire_data_1.uop.renamed.decoded.fetch.pc;
                retired_value[retired_count + retire_valid[0]] <=
                    retire_data_1.result.rd_value;
                retired_rd_write[retired_count + retire_valid[0]] <=
                    retire_data_1.result.rd_write;
                retired_mem_valid[retired_count + retire_valid[0]] <=
                    retire_data_1.result.mem_valid;
                retired_mem_rmask[retired_count + retire_valid[0]] <=
                    retire_data_1.result.mem_rmask;
                retired_mem_wmask[retired_count + retire_valid[0]] <=
                    retire_data_1.result.mem_wmask;
                retired_mem_rdata[retired_count + retire_valid[0]] <=
                    retire_data_1.result.mem_rdata;
                retired_mem_wdata[retired_count + retire_valid[0]] <=
                    retire_data_1.result.mem_wdata;
                retired_count <= retired_count + retire_valid[0] + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        decode_valid = 2'b00;
        decode_data_0 = '0;
        decode_data_1 = '0;
        trap_ready = 1'b0;
        retired_count = 0;
        saw_bp_update = 1'b0;
        observed_bp_pc = '0;
        observed_bp_is_cond_branch = 1'b0;
        observed_bp_is_jalr = 1'b0;
        observed_bp_is_call = 1'b0;
        observed_bp_is_return = 1'b0;
        observed_bp_taken = 1'b0;
        observed_bp_target = '0;
        for (integer unsigned i = 0; i < 16; i++) begin
            retired_pc[i] = '0;
            retired_value[i] = '0;
            retired_rd_write[i] = 1'b0;
            retired_mem_valid[i] = 1'b0;
            retired_mem_rmask[i] = '0;
            retired_mem_wmask[i] = '0;
            retired_mem_rdata[i] = '0;
            retired_mem_wdata[i] = '0;
        end

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        send_two(
            make_uop(rv32im_types::OP_ADDI, rv32im_types::FU_INT,
                     32'h0000_0100, 5'd0, 5'd0, 5'd1, 32'd5,
                     1'b1, 1'b0, 1'b1),
            make_uop(rv32im_types::OP_ADDI, rv32im_types::FU_INT,
                     32'h0000_0104, 5'd1, 5'd0, 5'd2, 32'd7,
                     1'b1, 1'b0, 1'b1)
        );

        begin
            rv32im_types::decoded_uop_t branch_uop;
            branch_uop = make_uop(rv32im_types::OP_BLT, rv32im_types::FU_BRANCH,
                                  32'h0000_010c, 5'd2, 5'd3, 5'd0, 32'h20,
                                  1'b1, 1'b1, 1'b0);
            branch_uop.fetch.pred_taken = 1'b0;
            branch_uop.fetch.pred_pc = 32'h0000_0110;
            send_two(
                make_uop(rv32im_types::OP_ADD, rv32im_types::FU_INT,
                         32'h0000_0108, 5'd1, 5'd2, 5'd3, 32'd0,
                         1'b1, 1'b1, 1'b1),
                branch_uop
            );
        end

        send_one(
            make_uop(rv32im_types::OP_ADDI, rv32im_types::FU_INT,
                     32'h0000_0110, 5'd0, 5'd0, 5'd4, 32'd99,
                     1'b1, 1'b0, 1'b1)
        );

        while (!flush) @(negedge clk);
        if (!redirect_valid || redirect_pc != 32'h0000_012c)
            $fatal(1, "branch recovery target mismatch");
        @(negedge clk);
        while (flush) @(negedge clk);

        send_one(
            make_uop(rv32im_types::OP_ADDI, rv32im_types::FU_INT,
                     32'h0000_012c, 5'd0, 5'd0, 5'd5, 32'd42,
                     1'b1, 1'b0, 1'b1)
        );
        send_two(
            make_uop(rv32im_types::OP_SW, rv32im_types::FU_STORE,
                     32'h0000_0130, 5'd0, 5'd5, 5'd0, 32'd0,
                     1'b1, 1'b1, 1'b0),
            make_uop(rv32im_types::OP_LW, rv32im_types::FU_LOAD,
                     32'h0000_0134, 5'd0, 5'd0, 5'd6, 32'd0,
                     1'b1, 1'b0, 1'b1)
        );
        send_two(
            make_uop(rv32im_types::OP_MUL, rv32im_types::FU_MULDIV,
                     32'h0000_0138, 5'd5, 5'd1, 5'd7, 32'd0,
                     1'b1, 1'b1, 1'b1),
            make_uop(rv32im_types::OP_DIV, rv32im_types::FU_MULDIV,
                     32'h0000_013c, 5'd7, 5'd1, 5'd8, 32'd0,
                     1'b1, 1'b1, 1'b1)
        );
        send_one(
            make_uop(rv32im_types::OP_ECALL, rv32im_types::FU_SYSTEM,
                     32'h0000_0140, 5'd0, 5'd0, 5'd0, 32'd0,
                     1'b0, 1'b0, 1'b0)
        );

        while (!trap_valid) @(negedge clk);
        #1ns;
        if (trap_cause != rv32im_types::EXC_ECALL_MMODE ||
            trap_pc != 32'h0000_0140)
            $fatal(1, "ECALL trap metadata mismatch");
        if (retired_count != 10)
            $fatal(1, "expected 10 retired instructions, got %0d", retired_count);

        if (retired_pc[0] != 32'h100 || !retired_rd_write[0] ||
            retired_value[0] != 32'd5)
            $fatal(1, "x1 ADDI retirement mismatch");
        if (retired_pc[1] != 32'h104 || !retired_rd_write[1] ||
            retired_value[1] != 32'd12)
            $fatal(1, "same-bundle RAW result mismatch");
        if (retired_pc[2] != 32'h108 || !retired_rd_write[2] ||
            retired_value[2] != 32'd17)
            $fatal(1, "dependent ADD result mismatch");
        if (retired_pc[3] != 32'h10c || retired_rd_write[3])
            $fatal(1, "branch retirement mismatch");
        if (retired_pc[4] != 32'h12c || !retired_rd_write[4] ||
            retired_value[4] != 32'd42)
            $fatal(1, "redirect target instruction mismatch");
        if (retired_pc[5] != 32'h130 || retired_rd_write[5] ||
            !retired_mem_valid[5] || retired_mem_rmask[5] != 4'b0000 ||
            retired_mem_wmask[5] != 4'b1111 ||
            retired_mem_wdata[5] != 32'd42)
            $fatal(1, "store retirement mismatch");
        if (retired_pc[6] != 32'h134 || !retired_rd_write[6] ||
            retired_value[6] != 32'd42 || !retired_mem_valid[6] ||
            retired_mem_rmask[6] != 4'b1111 ||
            retired_mem_wmask[6] != 4'b0000 ||
            retired_mem_rdata[6] != 32'd42)
            $fatal(1, "load retirement mismatch");
        if (retired_pc[7] != 32'h138 || !retired_rd_write[7] ||
            retired_value[7] != 32'd210)
            $fatal(1, "MUL retirement mismatch");
        if (retired_pc[8] != 32'h13c || !retired_rd_write[8] ||
            retired_value[8] != 32'd42)
            $fatal(1, "dependent DIV retirement mismatch");
        if (retired_pc[9] != 32'h140 || retired_rd_write[9])
            $fatal(1, "ECALL retirement mismatch");
        for (integer unsigned i = 0; i < retired_count; i++) begin
            if (retired_pc[i] == 32'h110)
                $fatal(1, "wrong-path instruction retired");
        end

        if (perf_instret_count != 64'd10 || perf_branch_count != 64'd1 ||
            perf_branch_mispredict_count != 64'd1 || perf_cycle_count == 64'd0)
            $fatal(1, "performance counters mismatch");

        if (!saw_bp_update || observed_bp_pc != 32'h10c ||
            !observed_bp_is_cond_branch || observed_bp_is_jalr ||
            observed_bp_is_call || observed_bp_is_return ||
            !observed_bp_taken || observed_bp_target != 32'h12c)
            $fatal(1, "branch predictor update mismatch");

        $display("backend_core_tb: PASS cycles=%0d instret=%0d CPI=%0f frontend_stall=%0d rob_full=%0d rs_full=%0d",
                 perf_cycle_count, perf_instret_count,
                 real'(perf_cycle_count) / real'(perf_instret_count),
                 perf_frontend_stall_count, perf_rob_full_count,
                 perf_rs_full_count);
        $finish;
    end

endmodule : backend_core_tb
