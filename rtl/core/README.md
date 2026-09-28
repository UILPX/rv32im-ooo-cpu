# Core integration work

`backend_core.sv` connects the integer, branch, multiply/divide, and ordered
load/store execution paths to rename, ROB completion, precise retirement,
recovery, commit trace, and basic performance counters. Each execution class has
its own scheduling boundary; two result slots arbitrate completion and physical
register writeback. The counters include cycles, retirement, branch behavior,
frontend backpressure, ROB-full cycles, and demand-specific RS-full stalls.

`rv32i_cpu.sv` composes that backend with the project frontend and external
instruction/data memory interfaces. The name is retained for API stability even
though the decoder and backend now accept RV32M operations. The mixed-authorship
course top level was intentionally not copied.
