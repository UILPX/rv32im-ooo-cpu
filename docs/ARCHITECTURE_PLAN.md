# Personal architecture plan

The target is an RV32IM out-of-order core implemented and verified openly by the
project contributors. The initial retained RTL is attributed to XP Liu; all new
module ownership is recorded through Issues, reviews, and Git history. The exact
width and queue sizes should remain parameters or measured design choices rather
than copied course constraints.

## Planned dataflow

1. **Frontend:** next-PC selection, branch prediction, instruction memory access,
   and an ordered fetch queue.
2. **Decode and rename:** RV32IM decode, RAT/RRAT, physical-register allocation,
   and stale-mapping tracking.
3. **Dispatch and scheduling:** resource checks, ROB allocation, operand reads,
   reservation-station insertion, wakeup, and issue selection.
4. **Execution:** integer ALUs, multiply/divide, branch resolution, and result
   broadcast.
5. **Memory ordering:** load/store queue, forwarding, committed stores, cache
   requests, and memory responses.
6. **Retirement and recovery:** in-order ROB commit, precise architectural state,
   branch recovery, and exception-ready control boundaries.

## Implementation order

1. Write a new ISA and microarchitecture type package from the public RISC-V
   specification and personal interface decisions.
2. Add unit tests for the retained register file, ALU, queues, and cache adapters.
3. Connect the completed RV32IM decoder, rename state, and ROB through a precise
   commit/recovery controller.
4. Connect the completed dispatch buffer/router to the independently tested
   reservation stations and execution units.
5. Implement the LSQ and connect it through the tested shared cache adapter to
   the personal cache/memory RTL.
6. Extend the implemented fetch and branch predictor with committed ROB updates,
   then integrate the CPU top level.
7. Add an open-source simulation, lint, synthesis, and continuous-integration
   flow with pinned tool versions.

Each milestone should include directed tests and a short design note before
performance optimization begins.
