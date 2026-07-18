SHELL := /bin/sh

VERILATOR ?= verilator
YOSYS ?= yosys

CI_VERILATOR_VERSION ?= 5.020
CI_YOSYS_VERSION ?= 0.33

BUILD_DIR := build
VERILATOR_DIR := $(BUILD_DIR)/verilator
YOSYS_DIR := $(BUILD_DIR)/yosys

WIDTH ?= 32
MUL_STAGES ?= 2
DIV_CYC ?= 11

MUL_STAGE_MATRIX := 1 2 4
DIV_CYCLE_MATRIX := 1 2 4 8 11 16 32

SMOKE_RTL := rtl/common/sp_ff_array.sv
SMOKE_TB := tb/smoke/sp_ff_array_tb.sv
SMOKE_TOP := sp_ff_array_tb
SMOKE_BINARY := $(VERILATOR_DIR)/V$(SMOKE_TOP)

MUL_RTL := rtl/execute/mul_pipe.sv
DIV_RTL := rtl/execute/div_iterative.sv
MULDIV_RTL := $(MUL_RTL) $(DIV_RTL) rtl/execute/muldiv.sv
MULDIV_TYPES := rtl/pkg/rv32im_types.sv
ALU_RTL := $(MULDIV_TYPES) rtl/execute/alu.sv
REGFILE_RTL := rtl/backend/regfile.sv

MUL_TB := tb/execute/mul_pipe_tb.sv
DIV_TB := tb/execute/div_iterative_tb.sv
MULDIV_TB := tb/execute/muldiv_tb.sv
ALU_TB := tb/execute/alu_tb.sv
REGFILE_TB := tb/backend/regfile_tb.sv

MUL_TEST_DIR := $(VERILATOR_DIR)/mul-w$(WIDTH)-s$(MUL_STAGES)
DIV_TEST_DIR := $(VERILATOR_DIR)/div-w$(WIDTH)-c$(DIV_CYC)
MULDIV_TEST_DIR := $(VERILATOR_DIR)/muldiv-s$(MUL_STAGES)-c$(DIV_CYC)
ALU_TEST_DIR := $(VERILATOR_DIR)/alu
REGFILE_TEST_DIR := $(VERILATOR_DIR)/regfile

MUL_TEST_BINARY := $(MUL_TEST_DIR)/Vmul_pipe_tb
DIV_TEST_BINARY := $(DIV_TEST_DIR)/Vdiv_iterative_tb
MULDIV_TEST_BINARY := $(MULDIV_TEST_DIR)/Vmuldiv_tb
ALU_TEST_BINARY := $(ALU_TEST_DIR)/Valu_tb
REGFILE_TEST_BINARY := $(REGFILE_TEST_DIR)/Vregfile_tb

.PHONY: help setup doctor doctor-pinned lint lint-muldiv test test-alu \
	test-regfile test-unit test-mul test-div test-muldiv-wrapper test-muldiv \
	synth synth-mul synth-div \
	sweep-muldiv check ci clean

help:
	@echo "Available targets:"
	@echo "  setup   Install the macOS toolchain from Brewfile"
	@echo "  doctor  Show the active Verilator and Yosys versions"
	@echo "  doctor-pinned     Verify the canonical CI tool versions"
	@echo "  lint    Lint the standalone smoke-test RTL"
	@echo "  test    Build and run the Verilator smoke test"
	@echo "  test-alu           Run directed ALU tests"
	@echo "  test-regfile       Run directed physical-register-file tests"
	@echo "  test-unit          Run ALU and register-file tests"
	@echo "  synth   Synthesize the smoke-test RTL with Yosys"
	@echo "  lint-muldiv       Lint the open-source mul/div RTL and wrapper"
	@echo "  test-muldiv       Test mul stages 1/2/4 and div cycles 1/2/4/8/11/16/32"
	@echo "  synth-mul         Synthesize mul_pipe (WIDTH=32 MUL_STAGES=2)"
	@echo "  synth-div         Synthesize div_iterative (WIDTH=32 DIV_CYC=11)"
	@echo "  sweep-muldiv      Synthesize the standard mul/div parameter matrix"
	@echo "  check             Run the smoke flow and full mul/div simulation matrix"
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

lint-muldiv:
	$(VERILATOR) --lint-only --Wall --top-module mul_pipe \
		-GWIDTH=$(WIDTH) -GNUM_STAGES=$(MUL_STAGES) $(MUL_RTL)
	$(VERILATOR) --lint-only --Wall --top-module div_iterative \
		-GWIDTH=$(WIDTH) -GDIV_CYC=$(DIV_CYC) $(DIV_RTL)
	$(VERILATOR) --lint-only --Wall --top-module muldiv \
		-Wno-UNUSEDPARAM \
		-GMUL_STAGES=$(MUL_STAGES) -GDIV_CYC=$(DIV_CYC) \
		$(MULDIV_TYPES) $(MULDIV_RTL)

$(SMOKE_BINARY): $(SMOKE_RTL) $(SMOKE_TB)
	@mkdir -p $(VERILATOR_DIR)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ --timescale 1ns/1ps \
		--Mdir $(VERILATOR_DIR) --top-module $(SMOKE_TOP) \
		$(SMOKE_RTL) $(SMOKE_TB)

test: $(SMOKE_BINARY)
	$(SMOKE_BINARY)

$(ALU_TEST_BINARY): $(ALU_RTL) $(ALU_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM \
		--timescale 1ns/1ps --Mdir $(ALU_TEST_DIR) --top-module alu_tb \
		$(ALU_RTL) $(ALU_TB)

test-alu: $(ALU_TEST_BINARY)
	$(ALU_TEST_BINARY)

$(REGFILE_TEST_BINARY): $(REGFILE_RTL) $(REGFILE_TB)
	@mkdir -p $(@D)
	$(VERILATOR) --binary --timing --assert --Wall -Wno-BLKSEQ \
		--timescale 1ns/1ps --Mdir $(REGFILE_TEST_DIR) --top-module regfile_tb \
		$(REGFILE_RTL) $(REGFILE_TB)

test-regfile: $(REGFILE_TEST_BINARY)
	$(REGFILE_TEST_BINARY)

test-unit: test-alu test-regfile

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

check: doctor lint test test-unit synth test-muldiv synth-mul synth-div

ci: doctor-pinned
	@$(MAKE) --no-print-directory check

clean:
	rm -rf $(BUILD_DIR)
