# Performance, frequency, and area target

The portfolio target is a functioning RV32I baseline core at 700 MHz with total
reported area below 500,000 square micrometres. The first post-route ASAP7
baseline meets those frequency and area thresholds. It is not yet a clean
sign-off result because extracted-RC STA reports residual maximum-transition
violations.

## Measured post-route baseline

The following result was measured on 2026-07-25 from the current working tree
based on Git commit `df192c5`. It must be rerun from a committed revision before
being attached to a release.

| Metric | Post-route result |
| --- | ---: |
| Clock constraint | 1,428 ps (700.28 MHz) |
| Core-clock minimum period | 1,285.72 ps |
| Core-clock estimated Fmax | 777.77 MHz |
| Setup worst slack | +142.28 ps |
| Hold worst slack | +25.85 ps |
| Setup / hold violations | 0 / 0 |
| Standard-cell area | 4,478.68 um^2 |
| Macro area | 0 um^2 |
| Die area | 11,277 um^2 |
| Detailed-route DRC violations | 0 |
| Antenna net / pin violations | 0 / 0 |
| Max capacitance / fanout violations | 0 / 0 |
| Maximum-transition violations | 59 |
| Worst maximum-transition excess | 33.16 ps over a 320 ps limit |
| Vectorless power estimate | 17.17 mW |

The frequency and area gates therefore pass, but the baseline is deliberately
labelled **not sign-off clean**. The next physical-design iteration must repair
the 59 transition violations without regressing setup, hold, DRC, or area.
Vectorless power is included only as a flow sanity check and is not workload
power.

## Reference configuration

- Strict RV32I correctness baseline with `ENABLE_RV32M=0`; the project-owned
  `rv32i_cpu_ppa` wrapper fixes this setting so MulDiv hardware is absent from
  the reference area and timing reports.
- Two-wide fetch, decode, rename, dispatch, and commit.
- 16-entry ROB, 64 physical integer registers, and a four-entry dispatch buffer.
- External instruction/data memory for the first CPU regression. Cache SRAM
  macros are reported separately when caches are enabled.

## Reproducible PPA gate

The open reference flow uses OpenROAD with the ASAP7 predictive FF NLDM
multi-VT standard-cell library. This is suitable for reproducible architectural
comparison, but it is not a claim about manufacturable silicon. The measured
run used OpenROAD `26Q3-771-g7cfb2105c9`, Yosys `0.67+post`, and the pinned
container below:

```text
openroad/orfs@sha256:3a07bd184d249fc95331e8ea55cdc6ca2ebec217c69a9b91154ad70225314cd1
```

Its reference settings are 40% core utilization, 0.60 placement density,
50 ps setup uncertainty, 20% input/output delay, and 25% slew-repair margin.
A later foundry flow may report a separate result without replacing the open
reference.

Reproduce a full run with:

```sh
make ppa-asap7 ORFS_VARIANT=slew25
```

Reports and layout artifacts are written below
`build/orfs/{reports,logs,results}/asap7/rv32i_cpu_ppa/slew25/` and are ignored by
Git.

The 700 MHz gate requires all of the following:

1. a 1.428 ns clock constraint;
2. non-negative post-route worst slack at the documented reference corner;
3. clock uncertainty, utilization, placement density, and routing settings
   recorded with the report;
4. no unconstrained register-to-register or input/output timing paths;
5. the exact RTL commit and tool/container versions recorded;
6. setup, hold, capacitance, fanout, transition, DRC, and antenna checks clean.

The area gate reports standard-cell area, macro area, and their sum. The stated
500,000 square-micrometre limit applies to the sum; a cacheless core must also
report that instruction and data memories are external. Gate-equivalent counts
may be included but are not substituted for mapped physical area.

Generic Yosys cell counts are useful for regression comparisons only. They do
not prove either the frequency or area target.

## Architectural performance evidence

The core exposes cycle, retired-instruction, branch, branch-miss,
frontend-stall, ROB-full, and RS-full counters. Reports must include:

- directed RV32I program completion and architectural commit trace;
- differential agreement with a reference ISA model;
- cycles, instructions, IPC, and branch-miss rate for each workload;
- a documented compiler, flags, program image, and memory-latency model.

No performance number is published as a CPU result until the full program-level
test passes. Unit-test latency and isolated synthesis statistics are not CPU
performance measurements.

`make perf-cpu` provides the initial deterministic microbenchmark: a strict
RV32I 100-iteration integer/branch loop with zero-wait-state instruction memory
and no data-memory traffic. Its `PERF` line reports all required counters; any
published value must also name the RTL commit and simulator version.
The current measured values and limitations are recorded in
`docs/PERFORMANCE_BASELINE.md`.

## Timing-oriented pipeline boundary

The dispatch buffer breaks reservation-station capacity feedback from
ROB/rename. The parameterized `decode_buffer` adds the registered boundary after
decode that was identified by the initial global-route report: backend ready no
longer propagates combinationally through decode/fetch into the next-PC state.
Unlike the backend dispatch buffer, it does not borrow capacity from a
same-cycle pop, specifically to keep this timing cut intact.

The integer and branch paths now also register reservation-station issue data
before execution and avoid same-cycle issue-to-dispatch capacity feedback. This
removes a previously detected combinational loop. The measured post-route
timing above validates the 700 MHz timing boundary for this cacheless strict
RV32I configuration; it does not validate caches, RV32M, or a foundry process.
