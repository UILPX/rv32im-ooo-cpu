# RV32IM Out-of-Order CPU

An open, collaborative RISC-V CPU project initiated by XP Liu.

This repository is a new engineering workspace for completing and evolving an
RV32IM out-of-order core. It is intentionally separate from the original
three-person ECE 411 repository. The initial RTL import contains only files whose
tracked lines were authored entirely by XP Liu; team-owned and mixed-authorship
RTL was excluded. All new work in this repository is collaborative and credited
through its Git history and accepted pull requests.

## Current status

**Personal rebuild in progress.** A buildable cacheless CPU baseline now connects
fetch/decode, rename, ROB, dispatch, integer/branch/multiply/divide execution,
an ordered LSU, and precise retirement. It passes directed project tests, but it
is not yet a complete privileged or independently validated RISC-V core.

Retained personal RTL currently covers:

- integer ALU and an open-source parameterized multiply/divide unit;
- physical register file and parameterized reservation stations;
- a parameterized two-wide rename stage with RAT/RRAT recovery, free-list, and
  physical-register readiness tracking;
- a parameterized reorder buffer with tagged completion and two-wide in-order
  retirement;
- a registered dispatch boundary and modular functional-unit router;
- ROB-tagged integer, RV32I branch, and RV32M execution adapters;
- precise commit/recovery control and an integrated integer/branch/mul-div/LSU
  backend;
- cacheline adaptation, a shared out-of-order cache adapter, cache bridge, and
  instruction/data cache variants;
- a one- or two-wide frontend with a parameterized queue, complete RV32IM
  decode, and a gshare/RAS branch predictor;
- small common storage and writeback-control utilities.

The multiply/divide unit now uses local synthesizable SystemVerilog IP. The
multiplier pipeline depth and divider cycle count are configurable for synthesis
experiments without vendor libraries. `ENABLE_RV32M=0` builds a strict RV32I
configuration: M-extension encodings trap as illegal instructions and the
multiply/divide scheduling and execution hardware is removed at elaboration.

## Structure

```text
rtl/
  common/    Small reusable RTL primitives
  pkg/       Personal ISA and microarchitecture types
  frontend/  Fetch, prediction, and instruction delivery
  backend/   Rename, dispatch, scheduling, register state, and retirement
  execute/   Integer and multiply/divide execution units
  memory/    LSQ, caches, and memory adapters
  core/      Cacheless CPU and backend integration
tb/          Directed unit and integration verification
docs/        Architecture and source-boundary documentation
```

See [the porting status](docs/PORTING_STATUS.md) for the exact retained and
excluded modules, and [the architecture plan](docs/ARCHITECTURE_PLAN.md) for the
collaborative implementation sequence.
The frequency, area, and performance acceptance criteria are defined in
[the PPA target](docs/PPA_TARGET.md). The initial cacheless strict-RV32I ASAP7
post-route baseline reaches 777.77 MHz at 4,478.68 um^2 of standard-cell area,
with clean setup, hold, DRC, and antenna checks. It still has 59
maximum-transition violations, so it is a measured engineering baseline rather
than a sign-off-clean silicon claim.
The reproducible 100-iteration RV32I loop result is recorded in
[the initial performance baseline](docs/PERFORMANCE_BASELINE.md).

New contributors should start with [the development setup](docs/DEVELOPMENT.md)
and [the RTL interface conventions](docs/INTERFACES.md).
Current ALU and register-file follow-up ideas are recorded in
[the improvement proposals](docs/ALU_REGFILE_IMPROVEMENTS.md).

## Current priorities

The current milestone is to turn the buildable cacheless CPU into a validated
portfolio core:

1. add differential RV32I ISA testing and compiler-generated programs;
2. eliminate the remaining post-route maximum-transition violations;
3. integrate and verify instruction/data caches without weakening precise state;
4. add CSR, interrupt, and privileged-execution support;
5. expand program-level RV32M validation and publish commit-bound results.

The live task list is maintained in GitHub Issues. Tasks marked `status: ready`
can be claimed without waiting for another design decision.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md), then select an unassigned Issue
from the current milestone. Comment that you want to own it before writing code,
keep the change focused, and open a pull request linked to the Issue. Larger
interface or architecture changes begin with a design-proposal Issue.

Project decisions and module ownership are described in
[GOVERNANCE.md](GOVERNANCE.md). All participants must follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Open-source toolchain

The current development flow uses Verilator for linting and simulation and
Yosys for synthesis. On macOS with Homebrew installed:

```sh
make setup
make check
```

Individual smoke commands are available through `make doctor`, `make lint`,
`make test`, and `make synth`. The multiply/divide flow adds:

```sh
make test-muldiv
make test-frontend
make test-decode
make test-rename
make test-rob
make test-dispatch
make test-exec
make test-commit
make test-backend
make test-cpu
make perf-cpu
make test-rs
make test-cache-adapter
make test-sram
make synth-sram
make synth-bp PHT_ENTRIES=128 RAS_ENTRIES=32
make synth-frontend FETCH_WIDTH=2 DISPATCH_WIDTH=2
make synth-frontend-decode FETCH_WIDTH=2 DECODE_WIDTH=2
make synth-rename NUM_PHYS_REGS=64 RENAME_WIDTH=2
make synth-rob ROB_DEPTH=16
make synth-dispatch DISPATCH_BUFFER_DEPTH=4 DISPATCH_WIDTH=2
make synth-exec
make synth-commit
make synth-backend
make lint-cpu ENABLE_RV32M=0
make synth-cpu ENABLE_RV32M=0
make ppa-asap7
make synth-mul MUL_STAGES=2
make synth-div DIV_CYC=11
make sweep-muldiv
```

Generated files, synthesis logs, and JSON netlists are kept under `build/` and
can be removed with `make clean`.

The smoke flow exercises `rtl/common/sp_ff_array.sv`; independent frontend and
mul/div flows test the branch predictor, fetch redirection, `mul_pipe`, and
`div_iterative`. The wrapper tests use the production `rv32im_types` package,
and `test-backend` covers a dependent MUL-to-DIV path through dispatch, wakeup,
writeback, and retirement. Privileged execution and differential ISA validation
remain future work.

## Public-release status

No course handouts, staff testbenches, benchmark binaries, reports, group-owned
RTL, or commercial tool scripts are included. Contributors must submit only work
they have the right to contribute and must preserve third-party attribution.

## License

Copyright 2026 XP Liu. This project is licensed under the
[Apache License 2.0](LICENSE). Commercial and non-commercial redistribution is
permitted under its terms. Distributions and derivative works must preserve the
applicable copyright, license, and [NOTICE](NOTICE) attribution required by
Section 4 of the license.
