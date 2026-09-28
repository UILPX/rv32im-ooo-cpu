# Verification work

Build a new independent verification environment here. It should use
redistributable tests and an open-source simulator, and should not depend on the
ECE 411 staff testbench or benchmark artifacts.

`smoke/sp_ff_array_tb.sv` is the first environment smoke test. Run it with
`make test`; it exists to verify the Verilator setup before the CPU-level
testbench is implemented.

`common/sp_sram_tb.sv` verifies the portable single-port SRAM's synchronous
read, masked write, and disabled-output-hold behavior. Run it with
`make test-sram`.

The `execute/` tests cover the standalone multiplier and divider across their
standard parameter matrix. They also verify the RV32M wrapper with the production
type package in `rtl/pkg/`. Run the full directed regression with `make
test-muldiv`.

`execute/alu_tb.sv` covers every currently supported ALU operation plus invalid
operations, output backpressure, grant behavior, and flush. `backend/regfile_tb.sv`
covers reset, the physical zero register, independent reads and writes, same-cycle
bypass, and same-address write priority. Run both with `make test-unit`.

`frontend/br_pred_tb.sv` covers conditional-direction training, dual-lane direct
targets, RAS push/pop, AUIPC/JALR pairing, and predecode flush. The fetch test
checks that prediction metadata and a taken redirect reach `i_fetch_ooo`.
`frontend/fetch_queue_tb.sv` covers ordered dual enqueue, prefix dispatch,
backpressure, simultaneous enqueue/dequeue, and flush. `frontend/frontend_tb.sv`
runs the integrated frontend with fetch widths one and two and verifies that
younger fetch bundles wait behind blocked dispatch data. `frontend/decoder_tb.sv`
covers every RV32IM operation family and reserved encodings;
`frontend/decode_stage_tb.sv` checks two-lane prefix flow control; and
`frontend/frontend_decode_tb.sv` verifies fetch-through-decode integration at
widths one and two. `frontend/decode_buffer_tb.sv` verifies the registered
frontend/backend boundary, including its no-pop-credit timing contract. Run
them with `make test-frontend`.

`backend/reservation_station_tb.sv` checks dual dispatch, oldest-ready issue,
same-cycle CDB wakeup, compaction, and flush. `memory/cache_adapter_ooo_tb.sv`
checks line reads, response backpressure, I/D same-line merging, request
priority, and four-beat writeback. Run them with `make test-rs` and
`make test-cache-adapter`.

`backend/rename_tb.sv` checks reset mappings, dual allocation, same-bundle RAW
and WAW dependencies, writeback readiness, commit reclamation, x0 behavior,
free-list exhaustion, and RRAT-based flush recovery. Run it with
`make test-rename`.

`backend/rob_tb.sv` checks blocked and dual allocation, out-of-order completion,
ordered and partially blocked commit, full-queue simultaneous retire/allocate,
tag wraparound, illegal instructions, and flush. Run it with `make test-rob`.

`backend/dispatch_buffer_tb.sv` checks registered ordering, backpressure,
simultaneous replace, and flush. `backend/dispatch_router_tb.sv` checks mixed and
same-class routing, station capacity, operand formation, system completion, and
the no-bypass rule. Run them with `make test-dispatch`.

`execute/alu_exec_tb.sv` checks ROB-tag preservation, writeback backpressure,
physical-register-zero completion, and flush. `execute/branch_unit_tb.sv`
checks conditional direction and targets, signed comparisons, JAL/JALR links,
misprediction reporting, writeback backpressure, unsupported operations, and
flush. Run both with `make test-exec`.

`backend/commit_control_tb.sv` checks dual retirement, predictor-port
serialization, commit-before-flush recovery, and held trap reporting. Run it
with `make test-commit`.

`core/backend_core_tb.sv` drives decoded integer, branch, memory, dependent
MUL-to-DIV, wrong-path, redirect-target, and ECALL operations through the
integrated backend. It checks RAW wakeup, result-bearing retirement records,
wrong-path suppression, predictor training, precise trap state, and performance
counters. Run it with `make test-backend`.

`core/rv32i_cpu_tb.sv` supplies real machine-code instruction words and a small
data-memory model to the cacheless CPU top. It covers integer dependencies,
load/store traffic, branch recovery, JAL, wrong-path suppression, and ECALL.
Run it with `make test-cpu`. These short sequences are correctness smoke tests,
not whole-program performance benchmarks. Both integration tests print cycles,
retired instructions, CPI, frontend-stall cycles, ROB-full cycles, and RS-full
cycles to make later baseline comparisons reproducible.

`core/rv32i_perf_tb.sv` is the first deterministic performance workload. It
runs a strict-RV32I 100-iteration integer/conditional-branch loop, checks the
architectural result, and emits one machine-readable `PERF` line with cycles,
IPC/CPI, branch misses, and stall counters. Run it with `make perf-cpu`; it is a
microbenchmark baseline, not a general application score.
