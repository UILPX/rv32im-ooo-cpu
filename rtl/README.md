# RTL layout

The directory structure separates stable reusable blocks from the CPU top level.
Retained RTL keeps its existing module names; interfaces may change only when the
new personal package and integration code are designed.

- `common/`: storage primitives without CPU policy.
- `pkg/`: personal ISA constants, packed structures, and interface types.
- `frontend/`: fetch, prediction, and instruction delivery.
- `backend/`: register state, rename, scheduling, writeback, and retirement.
- `execute/`: functional units.
- `memory/`: memory ordering, caches, and external-memory adaptation.
- `core/`: top-level CPU composition.

The Makefile now provides a full cacheless CPU compile manifest. Instruction
and data memories remain external at this boundary so the execution pipeline can
be verified before a cache hierarchy is selected.

`common/sp_sram.sv` is the portable inferred-memory implementation. The cache
data and tag wrappers under `memory/` preserve the existing macro interfaces so
an ASIC flow can substitute technology-specific SRAMs later.

`execute/mul_pipe.sv` and `execute/div_iterative.sv` are standalone and do not
depend on the CPU package. `mul_pipe.NUM_STAGES` controls multiplier latency
(`NUM_STAGES - 1` cycles), while `div_iterative.DIV_CYC` sets the exact number
of cycles used for a nonzero unsigned division.

`frontend/frontend_decode.sv` is the current frontend integration boundary. It
combines parameterized fetch, prediction, an ordered queue, and combinational
RV32IM decode. Its decoded-uop interface is intentionally independent of rename,
ROB allocation, and reservation-station routing.

`frontend/decode_buffer.sv` registers decoded uops before backend rename. Its
registered occupancy controls frontend backpressure, cutting the previously
measured ROB-to-next-PC combinational timing path.

`backend/rename.sv` provides the speculative RAT, committed RRAT, free-list,
physical-register readiness, same-bundle dependency handling, and one-cycle
flush recovery. ROB allocation and dispatch remain separate modules.

`backend/rob.sv` provides parameterized circular allocation, explicit tagged
completion, in-order retirement, commit backpressure, and flush. Dispatch and
the precise redirect controller remain separate modules.

`backend/dispatch_buffer.sv` registers allocated uops before resource routing;
`backend/dispatch_router.sv` reads operands, forms shared reservation-station
records, and routes a two-wide ordered prefix by functional-unit class.

`execute/alu_exec.sv`, `execute/branch_unit.sv`, and `execute/muldiv_exec.sv`
preserve ROB tags through integer, control-flow, and RV32M execution and emit
completion only when any required register writeback is accepted.

`backend/commit_control.sv` performs in-order architectural commit and emits
registered recovery/trap state. `core/backend_core.sv` integrates integer,
branch, multiply/divide, and ordered memory execution with registered issue
boundaries and performance counters. `core/rv32i_cpu.sv` adds the frontend and
external memory interfaces.
