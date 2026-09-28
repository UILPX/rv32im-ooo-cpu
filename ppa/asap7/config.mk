export PLATFORM = asap7
export NUM_CORES = 2

export DESIGN_NAME = rv32i_cpu_ppa
export DESIGN_NICKNAME = rv32i_cpu_ppa

export VERILOG_FILES = \
    /work/rtl/pkg/rv32im_types.sv \
    /work/rtl/frontend/br_pred.sv \
    /work/rtl/frontend/i_fetch_ooo.sv \
    /work/rtl/frontend/fetch_queue.sv \
    /work/rtl/frontend/frontend.sv \
    /work/rtl/frontend/decoder.sv \
    /work/rtl/frontend/decode_stage.sv \
    /work/rtl/frontend/frontend_decode.sv \
    /work/rtl/frontend/decode_buffer.sv \
    /work/rtl/backend/regfile.sv \
    /work/rtl/backend/rename.sv \
    /work/rtl/backend/rob.sv \
    /work/rtl/backend/dispatch_buffer.sv \
    /work/rtl/backend/dispatch_router.sv \
    /work/rtl/backend/reservation_station.sv \
    /work/rtl/backend/issue_buffer.sv \
    /work/rtl/backend/commit_control.sv \
    /work/rtl/execute/alu.sv \
    /work/rtl/execute/alu_exec.sv \
    /work/rtl/execute/branch_unit.sv \
    /work/rtl/execute/mul_pipe.sv \
    /work/rtl/execute/div_iterative.sv \
    /work/rtl/execute/muldiv.sv \
    /work/rtl/execute/muldiv_exec.sv \
    /work/rtl/memory/lsu.sv \
    /work/rtl/core/backend_core.sv \
    /work/rtl/core/rv32i_cpu.sv \
    /work/rtl/core/rv32i_cpu_ppa.sv

export SDC_FILE = /work/ppa/asap7/constraint.sdc

export ASAP7_USE_VT = RVT LVT SLVT
export CORE_UTILIZATION = 40
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.60
export TNS_END_PERCENT = 100
export SWAP_ARITH_OPERATORS = 1
# Add transition guardband before detailed routing. The first extracted-RC
# baseline still has residual slew violations, tracked in docs/PPA_TARGET.md.
export SLEW_MARGIN = 25
export OPENROAD_HIERARCHICAL = 1
# QEMU on Apple Silicon faults in the optional post-CTS detailed-placement
# pass. Global-route timing repair remains enabled and final STA is unchanged.
export SKIP_CTS_REPAIR_TIMING = 1
