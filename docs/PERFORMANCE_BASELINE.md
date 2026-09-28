# Initial performance baseline

This document records the first reproducible CPU-level microbenchmark result.
It is a regression baseline, not an application-performance claim.

## Configuration

- workload: `rv32i_loop` from `tb/core/rv32i_perf_tb.sv`;
- ISA: strict RV32I (`ENABLE_RV32M=0`);
- frontend/backend width: two instructions;
- decode buffer: four entries;
- ROB: 16 entries;
- branch predictor: 128-entry gshare PHT and four-entry RAS;
- instruction memory: combinational, zero wait states;
- data memory: unused;
- simulator: Verilator 5.050;
- measurement date: 2026-07-25.

This measurement is from the current working tree based on Git commit
`df192c5`; rerun it after committing before using it as a release-bound result.

The workload initializes a counter, executes 100 dependent increments and 100
conditional branches, then retires an ECALL through the precise trap path. It
checks the final architectural counter value before reporting performance.

## Result

| Metric | Value |
| --- | ---: |
| Cycles | 220 |
| Retired instructions | 203 |
| IPC | 0.922727 |
| CPI | 1.083744 |
| Retired branches | 100 |
| Branch mispredictions | 1 |
| Frontend-stall cycles | 0 |
| ROB-full cycles | 0 |
| RS-full dispatch-stall cycles | 0 |

Reproduce the result with:

```sh
make perf-cpu
```

The command emits a single machine-readable line beginning with `PERF`. Results
from a different RTL commit, tool version, memory-latency model, or workload are
not directly comparable. A compiler-generated benchmark and differential ISA
validation are still required before publishing broader performance claims.
