SHELL := /bin/sh

VERILATOR ?= verilator
YOSYS ?= yosys

CI_VERILATOR_VERSION ?= 5.020
CI_YOSYS_VERSION ?= 0.33

BUILD_DIR := build
VERILATOR_DIR := $(BUILD_DIR)/verilator
YOSYS_DIR := $(BUILD_DIR)/yosys
ORFS_BUILD_DIR := $(abspath $(BUILD_DIR)/orfs)

ORFS_IMAGE ?= openroad/orfs@sha256:3a07bd184d249fc95331e8ea55cdc6ca2ebec217c69a9b91154ad70225314cd1
ORFS_PLATFORM ?= linux/amd64
ORFS_VARIANT ?= rv32i-baseline
PPA_STAGE ?= finish

WIDTH ?= 32
MUL_STAGES ?= 2
DIV_CYC ?= 11
ENABLE_RV32M ?= 1
PHT_ENTRIES ?= 128
RAS_ENTRIES ?= 32
FETCH_WIDTH ?= 2
DISPATCH_WIDTH ?= $(FETCH_WIDTH)
DECODE_WIDTH ?= $(DISPATCH_WIDTH)
DECODE_BUFFER_DEPTH ?= 4
NUM_PHYS_REGS ?= 64
RENAME_WIDTH ?= 2
ROB_DEPTH ?= 16
DISPATCH_BUFFER_DEPTH ?= 4

MUL_STAGE_MATRIX := 1 2 4
DIV_CYCLE_MATRIX := 1 2 4 8 11 16 32

SMOKE_RTL := rtl/common/sp_ff_array.sv
SMOKE_TB := tb/smoke/sp_ff_array_tb.sv
SMOKE_TOP := sp_ff_array_tb
SMOKE_BINARY := $(VERILATOR_DIR)/V$(SMOKE_TOP)
SRAM_RTL := rtl/common/sp_sram.sv rtl/memory/mp_cache_data_array.sv \
	rtl/memory/mp_cache_tag_array.sv
SRAM_TB := tb/common/sp_sram_tb.sv
SRAM_TEST_DIR := $(VERILATOR_DIR)/sp-sram
SRAM_TEST_BINARY := $(SRAM_TEST_DIR)/Vsp_sram_tb

MUL_RTL := rtl/execute/mul_pipe.sv
DIV_RTL := rtl/execute/div_iterative.sv
MULDIV_RTL := $(MUL_RTL) $(DIV_RTL) rtl/execute/muldiv.sv
MULDIV_TYPES := rtl/pkg/rv32im_types.sv
BACKEND_MULDIV_RTL := $(MULDIV_RTL) rtl/execute/muldiv_exec.sv
ALU_RTL := $(MULDIV_TYPES) rtl/execute/alu.sv
ALU_EXEC_RTL := $(ALU_RTL) rtl/execute/alu_exec.sv
BRANCH_UNIT_RTL := $(MULDIV_TYPES) rtl/execute/branch_unit.sv
REGFILE_RTL := rtl/backend/regfile.sv
RS_RTL := $(MULDIV_TYPES) rtl/backend/reservation_station.sv
RENAME_RTL := $(MULDIV_TYPES) rtl/backend/rename.sv
ROB_RTL := $(MULDIV_TYPES) rtl/backend/rob.sv
DISPATCH_RTL := $(MULDIV_TYPES) rtl/backend/dispatch_buffer.sv \
	rtl/backend/dispatch_router.sv
COMMIT_RTL := $(MULDIV_TYPES) rtl/backend/commit_control.sv
LSU_RTL := $(MULDIV_TYPES) rtl/memory/lsu.sv
BACKEND_CORE_RTL := $(MULDIV_TYPES) rtl/backend/regfile.sv \
	rtl/backend/rename.sv rtl/backend/rob.sv rtl/backend/dispatch_buffer.sv \
	rtl/backend/dispatch_router.sv rtl/backend/reservation_station.sv \
	rtl/backend/issue_buffer.sv rtl/backend/commit_control.sv \
	rtl/execute/alu.sv rtl/execute/alu_exec.sv rtl/execute/branch_unit.sv \
	$(BACKEND_MULDIV_RTL) \
	rtl/memory/lsu.sv rtl/core/backend_core.sv
BP_RTL := rtl/frontend/br_pred.sv
FETCH_RTL := $(MULDIV_TYPES) $(BP_RTL) rtl/frontend/i_fetch_ooo.sv
FRONTEND_RTL := $(FETCH_RTL) rtl/frontend/fetch_queue.sv rtl/frontend/frontend.sv
DECODE_RTL := $(MULDIV_TYPES) rtl/frontend/decoder.sv rtl/frontend/decode_stage.sv
FRONTEND_DECODE_RTL := $(FRONTEND_RTL) rtl/frontend/decoder.sv \
	rtl/frontend/decode_stage.sv rtl/frontend/frontend_decode.sv
CPU_RTL := $(FRONTEND_DECODE_RTL) \
	rtl/frontend/decode_buffer.sv \
	$(filter-out $(MULDIV_TYPES),$(BACKEND_CORE_RTL)) rtl/core/rv32i_cpu.sv
CACHE_ADAPTER_RTL := $(MULDIV_TYPES) rtl/memory/cache_adapter_ooo.sv

MUL_TB := tb/execute/mul_pipe_tb.sv
DIV_TB := tb/execute/div_iterative_tb.sv
MULDIV_TB := tb/execute/muldiv_tb.sv
ALU_TB := tb/execute/alu_tb.sv
ALU_EXEC_TB := tb/execute/alu_exec_tb.sv
BRANCH_UNIT_TB := tb/execute/branch_unit_tb.sv
REGFILE_TB := tb/backend/regfile_tb.sv
RS_TB := tb/backend/reservation_station_tb.sv
RENAME_TB := tb/backend/rename_tb.sv
ROB_TB := tb/backend/rob_tb.sv
DISPATCH_BUFFER_TB := tb/backend/dispatch_buffer_tb.sv
DISPATCH_ROUTER_TB := tb/backend/dispatch_router_tb.sv
COMMIT_TB := tb/backend/commit_control_tb.sv
BACKEND_CORE_TB := tb/core/backend_core_tb.sv
CPU_TB := tb/core/rv32i_cpu_tb.sv
CPU_PERF_TB := tb/core/rv32i_perf_tb.sv
BP_TB := tb/frontend/br_pred_tb.sv
FETCH_TB := tb/frontend/i_fetch_ooo_tb.sv
FETCH_QUEUE_TB := tb/frontend/fetch_queue_tb.sv
FRONTEND_TB := tb/frontend/frontend_tb.sv
DECODER_TB := tb/frontend/decoder_tb.sv
DECODE_STAGE_TB := tb/frontend/decode_stage_tb.sv
FRONTEND_DECODE_TB := tb/frontend/frontend_decode_tb.sv
DECODE_BUFFER_TB := tb/frontend/decode_buffer_tb.sv
CACHE_ADAPTER_TB := tb/memory/cache_adapter_ooo_tb.sv
LSU_TB := tb/memory/lsu_tb.sv

MUL_TEST_DIR := $(VERILATOR_DIR)/mul-w$(WIDTH)-s$(MUL_STAGES)
DIV_TEST_DIR := $(VERILATOR_DIR)/div-w$(WIDTH)-c$(DIV_CYC)
MULDIV_TEST_DIR := $(VERILATOR_DIR)/muldiv-s$(MUL_STAGES)-c$(DIV_CYC)
ALU_TEST_DIR := $(VERILATOR_DIR)/alu
ALU_EXEC_TEST_DIR := $(VERILATOR_DIR)/alu-exec
BRANCH_UNIT_TEST_DIR := $(VERILATOR_DIR)/branch-unit
REGFILE_TEST_DIR := $(VERILATOR_DIR)/regfile
RS_TEST_DIR := $(VERILATOR_DIR)/reservation-station
RENAME_TEST_DIR := $(VERILATOR_DIR)/rename
ROB_TEST_DIR := $(VERILATOR_DIR)/rob
DISPATCH_BUFFER_TEST_DIR := $(VERILATOR_DIR)/dispatch-buffer
DISPATCH_ROUTER_TEST_DIR := $(VERILATOR_DIR)/dispatch-router
COMMIT_TEST_DIR := $(VERILATOR_DIR)/commit-control
BACKEND_CORE_TEST_DIR := $(VERILATOR_DIR)/backend-core
CPU_TEST_DIR := $(VERILATOR_DIR)/rv32i-cpu
CPU_PERF_TEST_DIR := $(VERILATOR_DIR)/rv32i-perf
BP_TEST_DIR := $(VERILATOR_DIR)/br-pred
FETCH_TEST_DIR := $(VERILATOR_DIR)/i-fetch-ooo
FETCH_QUEUE_TEST_DIR := $(VERILATOR_DIR)/fetch-queue
FRONTEND_TEST_DIR := $(VERILATOR_DIR)/frontend-f$(FETCH_WIDTH)-d$(DISPATCH_WIDTH)
DECODER_TEST_DIR := $(VERILATOR_DIR)/decoder
DECODE_STAGE_TEST_DIR := $(VERILATOR_DIR)/decode-stage
FRONTEND_DECODE_TEST_DIR := $(VERILATOR_DIR)/frontend-decode-f$(FETCH_WIDTH)-d$(DECODE_WIDTH)
DECODE_BUFFER_TEST_DIR := $(VERILATOR_DIR)/decode-buffer-d$(DECODE_BUFFER_DEPTH)
CACHE_ADAPTER_TEST_DIR := $(VERILATOR_DIR)/cache-adapter-ooo
LSU_TEST_DIR := $(VERILATOR_DIR)/lsu

MUL_TEST_BINARY := $(MUL_TEST_DIR)/Vmul_pipe_tb
DIV_TEST_BINARY := $(DIV_TEST_DIR)/Vdiv_iterative_tb
MULDIV_TEST_BINARY := $(MULDIV_TEST_DIR)/Vmuldiv_tb
ALU_TEST_BINARY := $(ALU_TEST_DIR)/Valu_tb
ALU_EXEC_TEST_BINARY := $(ALU_EXEC_TEST_DIR)/Valu_exec_tb
BRANCH_UNIT_TEST_BINARY := $(BRANCH_UNIT_TEST_DIR)/Vbranch_unit_tb
REGFILE_TEST_BINARY := $(REGFILE_TEST_DIR)/Vregfile_tb
RS_TEST_BINARY := $(RS_TEST_DIR)/Vreservation_station_tb
RENAME_TEST_BINARY := $(RENAME_TEST_DIR)/Vrename_tb
ROB_TEST_BINARY := $(ROB_TEST_DIR)/Vrob_tb
DISPATCH_BUFFER_TEST_BINARY := $(DISPATCH_BUFFER_TEST_DIR)/Vdispatch_buffer_tb
DISPATCH_ROUTER_TEST_BINARY := $(DISPATCH_ROUTER_TEST_DIR)/Vdispatch_router_tb
COMMIT_TEST_BINARY := $(COMMIT_TEST_DIR)/Vcommit_control_tb
BACKEND_CORE_TEST_BINARY := $(BACKEND_CORE_TEST_DIR)/Vbackend_core_tb
CPU_TEST_BINARY := $(CPU_TEST_DIR)/Vrv32i_cpu_tb
CPU_PERF_TEST_BINARY := $(CPU_PERF_TEST_DIR)/Vrv32i_perf_tb
BP_TEST_BINARY := $(BP_TEST_DIR)/Vbr_pred_tb
FETCH_TEST_BINARY := $(FETCH_TEST_DIR)/Vi_fetch_ooo_tb
FETCH_QUEUE_TEST_BINARY := $(FETCH_QUEUE_TEST_DIR)/Vfetch_queue_tb
FRONTEND_TEST_BINARY := $(FRONTEND_TEST_DIR)/Vfrontend_tb
DECODER_TEST_BINARY := $(DECODER_TEST_DIR)/Vdecoder_tb
DECODE_STAGE_TEST_BINARY := $(DECODE_STAGE_TEST_DIR)/Vdecode_stage_tb
FRONTEND_DECODE_TEST_BINARY := $(FRONTEND_DECODE_TEST_DIR)/Vfrontend_decode_tb
DECODE_BUFFER_TEST_BINARY := $(DECODE_BUFFER_TEST_DIR)/Vdecode_buffer_tb
CACHE_ADAPTER_TEST_BINARY := $(CACHE_ADAPTER_TEST_DIR)/Vcache_adapter_ooo_tb
LSU_TEST_BINARY := $(LSU_TEST_DIR)/Vlsu_tb

.PHONY: help setup doctor doctor-pinned lint lint-sram lint-frontend lint-cache-adapter lint-lsu lint-rename lint-rob lint-dispatch lint-commit lint-exec lint-backend lint-cpu \
	lint-muldiv test test-alu \
	test-sram test-regfile test-rs test-rename test-rob test-dispatch test-commit test-exec test-backend test-cpu perf-cpu test-cache-adapter test-lsu test-unit test-mul test-div \
	test-muldiv-wrapper test-muldiv \
	test-bp test-fetch test-fetch-queue test-frontend-wrapper test-frontend \
	test-decode test-decode-buffer test-frontend-decode-wrapper \
	synth synth-sram synth-bp synth-frontend synth-frontend-decode synth-rename synth-rob synth-dispatch synth-commit synth-exec synth-lsu synth-backend synth-cpu synth-mul synth-div \
	sweep-muldiv ppa-asap7 check ci clean

help:
	@echo "Available targets:"
	@echo "  setup   Install the macOS toolchain from Brewfile"
	@echo "  doctor  Show the active Verilator and Yosys versions"
	@echo "  doctor-pinned     Verify the canonical CI tool versions"
	@echo "  lint    Lint the standalone smoke-test RTL"
	@echo "  test    Build and run the Verilator smoke test"
	@echo "  test-sram          Run the parameterized single-port SRAM test"
	@echo "  test-alu           Run directed ALU tests"
	@echo "  test-regfile       Run directed physical-register-file tests"
	@echo "  test-rs            Run generic reservation-station tests"
	@echo "  test-rename        Run RAT/free-list/readiness and recovery tests"
	@echo "  test-rob           Run ROB allocation, completion, and retirement tests"
	@echo "  test-dispatch      Run dispatch buffering, routing, and operand tests"
	@echo "  test-commit        Run precise commit, recovery, and trap-control tests"
	@echo "  test-exec          Run integer and branch execution-adapter tests"
	@echo "  test-backend       Run the integer/branch/mul-div/LSU integration test"
	@echo "  test-lsu           Run ordered load/store and recovery tests"
	@echo "  test-cpu           Run a machine-code RV32I program end to end"
	@echo "  perf-cpu           Run the deterministic 100-iteration RV32I loop"
	@echo "  test-cache-adapter Run shared OOO cache-adapter tests"
	@echo "  test-bp            Run directed branch-predictor tests"
	@echo "  test-frontend      Test the frontend with fetch widths 1 and 2"
	@echo "  test-decode        Test RV32IM decode and two-lane prefix backpressure"
	@echo "  test-decode-buffer Test the registered frontend/backend timing boundary"
	@echo "  test-unit          Run ALU, register-file, RS, and cache-adapter tests"
	@echo "  synth   Synthesize the smoke-test RTL with Yosys"
	@echo "  synth-sram        Synthesize the inferred single-port SRAM"
	@echo "  lint-muldiv       Lint the open-source mul/div RTL and wrapper"
	@echo "  lint-frontend     Lint the branch predictor and fetch integration"
	@echo "  test-muldiv       Test mul stages 1/2/4 and div cycles 1/2/4/8/11/16/32"
	@echo "  synth-mul         Synthesize mul_pipe (WIDTH=32 MUL_STAGES=2)"
	@echo "  synth-div         Synthesize div_iterative (WIDTH=32 DIV_CYC=11)"
	@echo "  synth-bp          Synthesize br_pred (PHT_ENTRIES=128 RAS_ENTRIES=32)"
	@echo "  synth-frontend    Synthesize frontend (FETCH_WIDTH=1/2)"
	@echo "  synth-frontend-decode  Synthesize fetch through decoded-uop delivery"
	@echo "  synth-rename       Synthesize the parameterized rename state"
	@echo "  synth-rob          Synthesize the parameterized reorder buffer"
	@echo "  synth-dispatch     Synthesize the dispatch buffer and FU router"
	@echo "  synth-commit       Synthesize precise commit and recovery control"
	@echo "  synth-exec         Synthesize the integer and branch execution units"
	@echo "  synth-backend      Synthesize the current integrated backend"
	@echo "  synth-lsu          Synthesize the parameterized load/store unit"
	@echo "  synth-cpu          Synthesize the current RV32I CPU top level"
	@echo "  ppa-asap7          Run the pinned ASAP7 OpenROAD flow through finish"
	@echo "  sweep-muldiv      Synthesize the standard mul/div parameter matrix"
	@echo "  check             Run frontend, unit, smoke, mul/div, and synthesis checks"
	@echo "  ci                Verify pinned tool versions, then run check"
	@echo "  clean   Remove generated build artifacts"

setup:
	@command -v brew >/dev/null 2>&1 || { echo "error: Homebrew is required for make setup" >&2; exit 1; }
	brew bundle --no-upgrade

doctor:
	@command -v $(VERILATOR) >/dev/null 2>&1 || { echo "error: verilator not found; see docs/DEVELOPMENT.md" >&2; exit 1; }
	@command -v $(YOSYS) >/dev/null 2>&1 || { echo "error: yosys not found; see docs/DEVELOPMENT.md" >&2; exit 1; }
	@$(VERILATOR) --version
	@$(YOSYS) -V

doctor-pinned: doctor
	@case "$$($(VERILATOR) --version)" in \
		"Verilator $(CI_VERILATOR_VERSION) "*) ;; \
		*) echo "error: CI requires Verilator $(CI_VERILATOR_VERSION)" >&2; exit 1 ;; \
	esac
	@case "$$($(YOSYS) -V)" in \
		"Yosys $(CI_YOSYS_VERSION) "*|"Yosys $(CI_YOSYS_VERSION)+"*) ;; \
		*) echo "error: CI requires Yosys $(CI_YOSYS_VERSION)" >&2; exit 1 ;; \
	esac

lint:
	$(VERILATOR) --lint-only --Wall --top-module sp_ff_array $(SMOKE_RTL)

lint-sram:
	$(VERILATOR) --lint-only --Wall --top-module sp_sram rtl/common/sp_sram.sv
	$(VERILATOR) --lint-only --Wall --top-module mp_cache_data_array $(SRAM_RTL)
	$(VERILATOR) --lint-only --Wall --top-module mp_cache_tag_array $(SRAM_RTL)

lint-muldiv:
	$(VERILATOR) --lint-only --Wall --top-module mul_pipe \
		-GWIDTH=$(WIDTH) -GNUM_STAGES=$(MUL_STAGES) $(MUL_RTL)
	$(VERILATOR) --lint-only --Wall --top-module div_iterative \
		-GWIDTH=$(WIDTH) -GDIV_CYC=$(DIV_CYC) $(DIV_RTL)
	$(VERILATOR) --lint-only --Wall --top-module muldiv \
		-Wno-UNUSEDPARAM \
		-GMUL_STAGES=$(MUL_STAGES) -GDIV_CYC=$(DIV_CYC) \
		$(MULDIV_TYPES) $(MULDIV_RTL)

lint-frontend:
	$(VERILATOR) --lint-only --Wall --top-module br_pred \
		-GPHT_ENTRIES=$(PHT_ENTRIES) -GRAS_ENTRIES=$(RAS_ENTRIES) $(BP_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module i_fetch_ooo \
		$(FETCH_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module frontend \
		-GFETCH_WIDTH=$(FETCH_WIDTH) -GDISPATCH_WIDTH=$(DISPATCH_WIDTH) \
		$(FRONTEND_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module frontend_decode \
		-GFETCH_WIDTH=$(FETCH_WIDTH) -GDECODE_WIDTH=$(DECODE_WIDTH) \
		-GENABLE_RV32M=$(ENABLE_RV32M) \
		$(FRONTEND_DECODE_RTL)

lint-cache-adapter:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM \
		--top-module cache_adapter_ooo $(CACHE_ADAPTER_RTL)

lint-lsu:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module lsu \
		$(LSU_RTL)

lint-rename:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module rename \
		-GNUM_PHYS_REGS=$(NUM_PHYS_REGS) -GRENAME_WIDTH=$(RENAME_WIDTH) \
		$(RENAME_RTL)

lint-rob:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module rob \
		-GDEPTH=$(ROB_DEPTH) $(ROB_RTL)

lint-dispatch:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module dispatch_buffer \
		-GDEPTH=$(DISPATCH_BUFFER_DEPTH) $(MULDIV_TYPES) rtl/backend/dispatch_buffer.sv
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module dispatch_router \
		-GDISPATCH_WIDTH=$(DISPATCH_WIDTH) $(MULDIV_TYPES) rtl/backend/dispatch_router.sv

lint-commit:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module commit_control \
		$(COMMIT_RTL)

lint-exec:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module alu_exec \
		$(ALU_EXEC_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module branch_unit \
		$(BRANCH_UNIT_RTL)

lint-backend:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module backend_core \
		-GNUM_PHYS_REGS=$(NUM_PHYS_REGS) -GROB_DEPTH=$(ROB_DEPTH) \
		-GDISPATCH_BUFFER_DEPTH=$(DISPATCH_BUFFER_DEPTH) \
		-GENABLE_RV32M=$(ENABLE_RV32M) $(BACKEND_CORE_RTL)

lint-cpu:
	$(VERILATOR) --lint-only --Wall -Wno-UNUSEDPARAM --top-module rv32i_cpu \
		-GENABLE_RV32M=$(ENABLE_RV32M) \
		-GDECODE_BUFFER_DEPTH=$(DECODE_BUFFER_DEPTH) $(CPU_RTL)

$(SMOKE_BINARY): $(SMOKE_RTL) $(SMOKE_TB)
	@mkdir -p $(VERILATOR_DIR)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ --timescale 1ns/1ps \
		--Mdir $(VERILATOR_DIR) --top-module $(SMOKE_TOP) \
		$(SMOKE_RTL) $(SMOKE_TB)

test: $(SMOKE_BINARY)
	$(SMOKE_BINARY)

$(SRAM_TEST_BINARY): rtl/common/sp_sram.sv $(SRAM_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ \
		--timescale 1ns/1ps --Mdir $(SRAM_TEST_DIR) --top-module sp_sram_tb \
		rtl/common/sp_sram.sv $(SRAM_TB)

test-sram: $(SRAM_TEST_BINARY)
	$(SRAM_TEST_BINARY)

$(ALU_TEST_BINARY): $(ALU_RTL) $(ALU_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(ALU_TEST_DIR) --top-module alu_tb \
		$(ALU_RTL) $(ALU_TB)

test-alu: $(ALU_TEST_BINARY)
	$(ALU_TEST_BINARY)

$(ALU_EXEC_TEST_BINARY): $(ALU_EXEC_RTL) $(ALU_EXEC_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(ALU_EXEC_TEST_DIR) --top-module alu_exec_tb \
		$(ALU_EXEC_RTL) $(ALU_EXEC_TB)

$(BRANCH_UNIT_TEST_BINARY): $(BRANCH_UNIT_RTL) $(BRANCH_UNIT_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(BRANCH_UNIT_TEST_DIR) --top-module branch_unit_tb \
		$(BRANCH_UNIT_RTL) $(BRANCH_UNIT_TB)

test-exec: $(ALU_EXEC_TEST_BINARY) $(BRANCH_UNIT_TEST_BINARY)
	$(ALU_EXEC_TEST_BINARY)
	$(BRANCH_UNIT_TEST_BINARY)

$(BACKEND_CORE_TEST_BINARY): $(BACKEND_CORE_RTL) $(BACKEND_CORE_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(BACKEND_CORE_TEST_DIR) --top-module backend_core_tb \
		$(BACKEND_CORE_RTL) $(BACKEND_CORE_TB)

test-backend: $(BACKEND_CORE_TEST_BINARY)
	$(BACKEND_CORE_TEST_BINARY)

$(CPU_TEST_BINARY): $(CPU_RTL) $(CPU_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(CPU_TEST_DIR) --top-module rv32i_cpu_tb \
		$(CPU_RTL) $(CPU_TB)

test-cpu: $(CPU_TEST_BINARY)
	$(CPU_TEST_BINARY)

$(CPU_PERF_TEST_BINARY): $(CPU_RTL) $(CPU_PERF_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(CPU_PERF_TEST_DIR) \
		--top-module rv32i_perf_tb $(CPU_RTL) $(CPU_PERF_TB)

perf-cpu: $(CPU_PERF_TEST_BINARY)
	$(CPU_PERF_TEST_BINARY)

$(REGFILE_TEST_BINARY): $(REGFILE_RTL) $(REGFILE_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ \
		--timescale 1ns/1ps --Mdir $(REGFILE_TEST_DIR) --top-module regfile_tb \
		$(REGFILE_RTL) $(REGFILE_TB)

test-regfile: $(REGFILE_TEST_BINARY)
	$(REGFILE_TEST_BINARY)

$(RS_TEST_BINARY): $(RS_RTL) $(RS_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(RS_TEST_DIR) --top-module reservation_station_tb \
		$(RS_RTL) $(RS_TB)

test-rs: $(RS_TEST_BINARY)
	$(RS_TEST_BINARY)

$(RENAME_TEST_BINARY): $(RENAME_RTL) $(RENAME_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(RENAME_TEST_DIR) --top-module rename_tb \
		$(RENAME_RTL) $(RENAME_TB)

test-rename: $(RENAME_TEST_BINARY)
	$(RENAME_TEST_BINARY)

$(ROB_TEST_BINARY): $(ROB_RTL) $(ROB_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(ROB_TEST_DIR) --top-module rob_tb \
		$(ROB_RTL) $(ROB_TB)

test-rob: $(ROB_TEST_BINARY)
	$(ROB_TEST_BINARY)

$(DISPATCH_BUFFER_TEST_BINARY): $(MULDIV_TYPES) rtl/backend/dispatch_buffer.sv $(DISPATCH_BUFFER_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(DISPATCH_BUFFER_TEST_DIR) \
		--top-module dispatch_buffer_tb \
		$(MULDIV_TYPES) rtl/backend/dispatch_buffer.sv $(DISPATCH_BUFFER_TB)

$(DISPATCH_ROUTER_TEST_BINARY): $(MULDIV_TYPES) rtl/backend/dispatch_router.sv $(DISPATCH_ROUTER_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(DISPATCH_ROUTER_TEST_DIR) \
		--top-module dispatch_router_tb \
		$(MULDIV_TYPES) rtl/backend/dispatch_router.sv $(DISPATCH_ROUTER_TB)

test-dispatch: $(DISPATCH_BUFFER_TEST_BINARY) $(DISPATCH_ROUTER_TEST_BINARY)
	$(DISPATCH_BUFFER_TEST_BINARY)
	$(DISPATCH_ROUTER_TEST_BINARY)

$(COMMIT_TEST_BINARY): $(COMMIT_RTL) $(COMMIT_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(COMMIT_TEST_DIR) --top-module commit_control_tb \
		$(COMMIT_RTL) $(COMMIT_TB)

test-commit: $(COMMIT_TEST_BINARY)
	$(COMMIT_TEST_BINARY)

$(CACHE_ADAPTER_TEST_BINARY): $(CACHE_ADAPTER_RTL) $(CACHE_ADAPTER_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(CACHE_ADAPTER_TEST_DIR) \
		--top-module cache_adapter_ooo_tb \
		$(CACHE_ADAPTER_RTL) $(CACHE_ADAPTER_TB)

test-cache-adapter: $(CACHE_ADAPTER_TEST_BINARY)
	$(CACHE_ADAPTER_TEST_BINARY)

$(LSU_TEST_BINARY): $(LSU_RTL) $(LSU_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(LSU_TEST_DIR) --top-module lsu_tb \
		$(LSU_RTL) $(LSU_TB)

test-lsu: $(LSU_TEST_BINARY)
	$(LSU_TEST_BINARY)

test-unit: test-alu test-regfile test-rs test-rename test-rob test-dispatch test-commit test-exec test-lsu test-cache-adapter

$(BP_TEST_BINARY): $(BP_RTL) $(BP_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ \
		--timescale 1ns/1ps --Mdir $(BP_TEST_DIR) --top-module br_pred_tb \
		$(BP_RTL) $(BP_TB)

test-bp: $(BP_TEST_BINARY)
	$(BP_TEST_BINARY)

$(FETCH_TEST_BINARY): $(FETCH_RTL) $(FETCH_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(FETCH_TEST_DIR) --top-module i_fetch_ooo_tb \
		$(FETCH_RTL) $(FETCH_TB)

test-fetch: $(FETCH_TEST_BINARY)
	$(FETCH_TEST_BINARY)

$(FETCH_QUEUE_TEST_BINARY): $(MULDIV_TYPES) rtl/frontend/fetch_queue.sv $(FETCH_QUEUE_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(FETCH_QUEUE_TEST_DIR) \
		--top-module fetch_queue_tb \
		$(MULDIV_TYPES) rtl/frontend/fetch_queue.sv $(FETCH_QUEUE_TB)

test-fetch-queue: $(FETCH_QUEUE_TEST_BINARY)
	$(FETCH_QUEUE_TEST_BINARY)

$(FRONTEND_TEST_BINARY): $(FRONTEND_RTL) $(FRONTEND_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(FRONTEND_TEST_DIR) --top-module frontend_tb \
		-GFETCH_WIDTH=$(FETCH_WIDTH) -GDISPATCH_WIDTH=$(DISPATCH_WIDTH) \
		$(FRONTEND_RTL) $(FRONTEND_TB)

test-frontend-wrapper: $(FRONTEND_TEST_BINARY)
	$(FRONTEND_TEST_BINARY)

$(DECODER_TEST_BINARY): $(MULDIV_TYPES) rtl/frontend/decoder.sv $(DECODER_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(DECODER_TEST_DIR) --top-module decoder_tb \
		$(MULDIV_TYPES) rtl/frontend/decoder.sv $(DECODER_TB)

$(DECODE_STAGE_TEST_BINARY): $(DECODE_RTL) $(DECODE_STAGE_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(DECODE_STAGE_TEST_DIR) \
		--top-module decode_stage_tb $(DECODE_RTL) $(DECODE_STAGE_TB)

test-decode: $(DECODER_TEST_BINARY) $(DECODE_STAGE_TEST_BINARY)
	$(DECODER_TEST_BINARY)
	$(DECODE_STAGE_TEST_BINARY)

$(DECODE_BUFFER_TEST_BINARY): $(MULDIV_TYPES) rtl/frontend/decode_buffer.sv $(DECODE_BUFFER_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(DECODE_BUFFER_TEST_DIR) \
		--top-module decode_buffer_tb \
		$(MULDIV_TYPES) rtl/frontend/decode_buffer.sv $(DECODE_BUFFER_TB)

test-decode-buffer: $(DECODE_BUFFER_TEST_BINARY)
	$(DECODE_BUFFER_TEST_BINARY)

$(FRONTEND_DECODE_TEST_BINARY): $(FRONTEND_DECODE_RTL) $(FRONTEND_DECODE_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(FRONTEND_DECODE_TEST_DIR) \
		--top-module frontend_decode_tb \
		-GFETCH_WIDTH=$(FETCH_WIDTH) -GDECODE_WIDTH=$(DECODE_WIDTH) \
		$(FRONTEND_DECODE_RTL) $(FRONTEND_DECODE_TB)

test-frontend-decode-wrapper: $(FRONTEND_DECODE_TEST_BINARY)
	$(FRONTEND_DECODE_TEST_BINARY)

test-frontend: test-bp test-fetch test-fetch-queue test-decode test-decode-buffer
	@$(MAKE) --no-print-directory test-frontend-wrapper FETCH_WIDTH=1 DISPATCH_WIDTH=1
	@$(MAKE) --no-print-directory test-frontend-wrapper FETCH_WIDTH=2 DISPATCH_WIDTH=1
	@$(MAKE) --no-print-directory test-frontend-wrapper FETCH_WIDTH=2 DISPATCH_WIDTH=2
	@$(MAKE) --no-print-directory test-frontend-decode-wrapper FETCH_WIDTH=1 DECODE_WIDTH=1
	@$(MAKE) --no-print-directory test-frontend-decode-wrapper FETCH_WIDTH=2 DECODE_WIDTH=2

$(MUL_TEST_BINARY): $(MUL_RTL) $(MUL_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ --timescale 1ns/1ps \
		--Mdir $(MUL_TEST_DIR) --top-module mul_pipe_tb \
		-GWIDTH=$(WIDTH) -GNUM_STAGES=$(MUL_STAGES) $(MUL_RTL) $(MUL_TB)

test-mul: $(MUL_TEST_BINARY)
	$(MUL_TEST_BINARY)

$(DIV_TEST_BINARY): $(DIV_RTL) $(DIV_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ --timescale 1ns/1ps \
		--Mdir $(DIV_TEST_DIR) --top-module div_iterative_tb \
		-GWIDTH=$(WIDTH) -GDIV_CYC=$(DIV_CYC) $(DIV_RTL) $(DIV_TB)

test-div: $(DIV_TEST_BINARY)
	$(DIV_TEST_BINARY)

$(MULDIV_TEST_BINARY): $(MULDIV_TYPES) $(MULDIV_RTL) $(MULDIV_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps \
		--Mdir $(MULDIV_TEST_DIR) --top-module muldiv_tb \
		-GMUL_STAGES=$(MUL_STAGES) -GDIV_CYC=$(DIV_CYC) \
		$(MULDIV_TYPES) $(MULDIV_RTL) $(MULDIV_TB)

test-muldiv-wrapper: $(MULDIV_TEST_BINARY)
	$(MULDIV_TEST_BINARY)

test-muldiv: lint-muldiv
	@set -e; for stages in $(MUL_STAGE_MATRIX); do \
		$(MAKE) --no-print-directory test-mul WIDTH=32 MUL_STAGES=$$stages; \
	done
	@set -e; for cycles in $(DIV_CYCLE_MATRIX); do \
		$(MAKE) --no-print-directory test-div WIDTH=32 DIV_CYC=$$cycles; \
	done
	@$(MAKE) --no-print-directory test-muldiv-wrapper MUL_STAGES=2 DIV_CYC=11
	@$(MAKE) --no-print-directory test-muldiv-wrapper MUL_STAGES=1 DIV_CYC=1

synth:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -s scripts/synth_smoke.ys

synth-sram:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/sp-sram.log -p 'read_verilog -sv rtl/common/sp_sram.sv; hierarchy -check -top sp_sram; synth -top sp_sram; check; stat; write_json $(YOSYS_DIR)/sp-sram.json'

synth-bp:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/br-pred-p$(PHT_ENTRIES)-r$(RAS_ENTRIES).log -p 'read_verilog -sv $(BP_RTL); chparam -set PHT_ENTRIES $(PHT_ENTRIES) -set RAS_ENTRIES $(RAS_ENTRIES) br_pred; hierarchy -check -top br_pred; synth -top br_pred; check; stat; write_json $(YOSYS_DIR)/br-pred-p$(PHT_ENTRIES)-r$(RAS_ENTRIES).json'

synth-frontend:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/frontend-f$(FETCH_WIDTH)-d$(DISPATCH_WIDTH).log -p 'read_verilog -sv $(FRONTEND_RTL); chparam -set FETCH_WIDTH $(FETCH_WIDTH) -set DISPATCH_WIDTH $(DISPATCH_WIDTH) frontend; hierarchy -check -top frontend; synth -top frontend; check; stat; write_json $(YOSYS_DIR)/frontend-f$(FETCH_WIDTH)-d$(DISPATCH_WIDTH).json'

synth-frontend-decode:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/frontend-decode-f$(FETCH_WIDTH)-d$(DECODE_WIDTH).log -p 'read_verilog -sv $(FRONTEND_DECODE_RTL); chparam -set FETCH_WIDTH $(FETCH_WIDTH) -set DECODE_WIDTH $(DECODE_WIDTH) -set ENABLE_RV32M $(ENABLE_RV32M) frontend_decode; hierarchy -check -top frontend_decode; synth -top frontend_decode; check; stat; write_json $(YOSYS_DIR)/frontend-decode-f$(FETCH_WIDTH)-d$(DECODE_WIDTH).json'

synth-rename:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/rename-p$(NUM_PHYS_REGS)-w$(RENAME_WIDTH).log -p 'read_verilog -sv $(RENAME_RTL); chparam -set NUM_PHYS_REGS $(NUM_PHYS_REGS) -set RENAME_WIDTH $(RENAME_WIDTH) rename; hierarchy -check -top rename; synth -top rename; check; stat; write_json $(YOSYS_DIR)/rename-p$(NUM_PHYS_REGS)-w$(RENAME_WIDTH).json'

synth-rob:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/rob-d$(ROB_DEPTH).log -p 'read_verilog -sv $(ROB_RTL); chparam -set DEPTH $(ROB_DEPTH) rob; hierarchy -check -top rob; synth -top rob; check; stat; write_json $(YOSYS_DIR)/rob-d$(ROB_DEPTH).json'

synth-dispatch:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/dispatch-buffer-d$(DISPATCH_BUFFER_DEPTH).log -p 'read_verilog -sv $(MULDIV_TYPES) rtl/backend/dispatch_buffer.sv; chparam -set DEPTH $(DISPATCH_BUFFER_DEPTH) dispatch_buffer; hierarchy -check -top dispatch_buffer; synth -top dispatch_buffer; check; stat; write_json $(YOSYS_DIR)/dispatch-buffer-d$(DISPATCH_BUFFER_DEPTH).json'
	$(YOSYS) -q -l $(YOSYS_DIR)/dispatch-router-w$(DISPATCH_WIDTH).log -p 'read_verilog -sv $(MULDIV_TYPES) rtl/backend/dispatch_router.sv; chparam -set DISPATCH_WIDTH $(DISPATCH_WIDTH) dispatch_router; hierarchy -check -top dispatch_router; synth -top dispatch_router; check; stat; write_json $(YOSYS_DIR)/dispatch-router-w$(DISPATCH_WIDTH).json'

synth-commit:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/commit-control.log -p 'read_verilog -sv $(COMMIT_RTL); hierarchy -check -top commit_control; synth -top commit_control; check; stat; write_json $(YOSYS_DIR)/commit-control.json'

synth-exec:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/alu-exec.log -p 'read_verilog -sv $(ALU_EXEC_RTL); hierarchy -check -top alu_exec; synth -top alu_exec; check; stat; write_json $(YOSYS_DIR)/alu-exec.json'
	$(YOSYS) -q -l $(YOSYS_DIR)/branch-unit.log -p 'read_verilog -sv $(BRANCH_UNIT_RTL); hierarchy -check -top branch_unit; synth -top branch_unit; check; stat; write_json $(YOSYS_DIR)/branch-unit.json'

synth-lsu:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/lsu.log -p 'read_verilog -sv $(LSU_RTL); hierarchy -check -top lsu; synth -top lsu; check; stat; write_json $(YOSYS_DIR)/lsu.json'

synth-backend:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/backend-core.log -p 'read_verilog -sv $(BACKEND_CORE_RTL); chparam -set NUM_PHYS_REGS $(NUM_PHYS_REGS) -set ROB_DEPTH $(ROB_DEPTH) -set DISPATCH_BUFFER_DEPTH $(DISPATCH_BUFFER_DEPTH) -set ENABLE_RV32M $(ENABLE_RV32M) backend_core; hierarchy -check -top backend_core; synth -top backend_core; check; stat; write_json $(YOSYS_DIR)/backend-core.json'

synth-cpu:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/rv32i-cpu.log -p 'read_verilog -sv $(CPU_RTL); chparam -set NUM_PHYS_REGS $(NUM_PHYS_REGS) -set ROB_DEPTH $(ROB_DEPTH) -set DISPATCH_BUFFER_DEPTH $(DISPATCH_BUFFER_DEPTH) -set DECODE_BUFFER_DEPTH $(DECODE_BUFFER_DEPTH) -set ENABLE_RV32M $(ENABLE_RV32M) rv32i_cpu; hierarchy -check -top rv32i_cpu; synth -top rv32i_cpu; check; stat; write_json $(YOSYS_DIR)/rv32i-cpu.json'

synth-mul:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/mul-w$(WIDTH)-s$(MUL_STAGES).log -p 'read_verilog -sv $(MUL_RTL); chparam -set WIDTH $(WIDTH) -set NUM_STAGES $(MUL_STAGES) mul_pipe; hierarchy -check -top mul_pipe; synth -top mul_pipe; check; stat; write_json $(YOSYS_DIR)/mul-w$(WIDTH)-s$(MUL_STAGES).json'

synth-div:
	@mkdir -p $(YOSYS_DIR)
	$(YOSYS) -q -l $(YOSYS_DIR)/div-w$(WIDTH)-c$(DIV_CYC).log -p 'read_verilog -sv $(DIV_RTL); chparam -set WIDTH $(WIDTH) -set DIV_CYC $(DIV_CYC) div_iterative; hierarchy -check -top div_iterative; synth -top div_iterative; check; stat; write_json $(YOSYS_DIR)/div-w$(WIDTH)-c$(DIV_CYC).json'

sweep-muldiv:
	@set -e; for stages in $(MUL_STAGE_MATRIX); do \
		$(MAKE) --no-print-directory synth-mul WIDTH=32 MUL_STAGES=$$stages; \
	done
	@set -e; for cycles in $(DIV_CYCLE_MATRIX); do \
		$(MAKE) --no-print-directory synth-div WIDTH=32 DIV_CYC=$$cycles; \
	done

ppa-asap7:
	@command -v docker >/dev/null 2>&1 || { echo "error: Docker is required for make ppa-asap7" >&2; exit 1; }
	@mkdir -p $(ORFS_BUILD_DIR)/results $(ORFS_BUILD_DIR)/logs \
		$(ORFS_BUILD_DIR)/reports $(ORFS_BUILD_DIR)/objects
	docker run --rm --platform $(ORFS_PLATFORM) \
		-v "$(CURDIR):/work:ro" \
		-v "$(ORFS_BUILD_DIR)/results:/OpenROAD-flow-scripts/flow/results" \
		-v "$(ORFS_BUILD_DIR)/logs:/OpenROAD-flow-scripts/flow/logs" \
		-v "$(ORFS_BUILD_DIR)/reports:/OpenROAD-flow-scripts/flow/reports" \
		-v "$(ORFS_BUILD_DIR)/objects:/OpenROAD-flow-scripts/flow/objects" \
		$(ORFS_IMAGE) bash -lc \
		'make -C flow DESIGN_CONFIG=/work/ppa/asap7/config.mk FLOW_VARIANT=$(ORFS_VARIANT) $(PPA_STAGE)'

check: doctor lint lint-sram lint-frontend lint-cache-adapter lint-lsu lint-rename lint-rob lint-dispatch lint-commit lint-exec lint-backend lint-cpu test test-sram \
	test-unit test-backend test-cpu test-frontend synth synth-sram synth-bp synth-frontend \
	synth-frontend-decode synth-rename synth-rob synth-dispatch synth-commit synth-exec synth-lsu synth-backend synth-cpu test-muldiv \
	synth-mul synth-div

ci: doctor-pinned
	@$(MAKE) --no-print-directory check

clean:
	rm -rf $(BUILD_DIR)
