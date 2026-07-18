# RV32IM Out-of-Order CPU

An open, collaborative RISC-V CPU project initiated by XP Liu.

This repository is a new engineering workspace for completing and evolving an
RV32IM out-of-order core. It is intentionally separate from the original
three-person ECE 411 repository. The initial RTL import contains only files whose
tracked lines were authored entirely by XP Liu; team-owned and mixed-authorship
RTL was excluded. All new work in this repository is collaborative and credited
through its Git history and accepted pull requests.

## Current status

**Personal rebuild in progress.** The repository is not yet a complete or
buildable CPU. Pipeline control, the retirement path, top-level integration,
and a CPU-level testbench still need new implementations.
This status is explicit so future results are not confused with the earlier team
project.

Retained personal RTL currently covers:

- integer ALU and an open-source parameterized multiply/divide unit;
- physical register file and selected reservation stations;
- cacheline adaptation, cache bridge, and instruction/data cache variants;
- an out-of-order instruction-fetch queue;
- small common storage and writeback-control utilities.

The multiply/divide unit now uses local synthesizable SystemVerilog IP. The
multiplier pipeline depth and divider cycle count are configurable for synthesis
experiments without vendor libraries.

## Structure

```text
rtl/
  common/    Small reusable RTL primitives
  pkg/       Personal ISA and microarchitecture types
  frontend/  Fetch, prediction, and instruction delivery
  backend/   Rename, dispatch, scheduling, register state, and retirement
  execute/   Integer and multiply/divide execution units
  memory/    LSQ, caches, and memory adapters
  core/      CPU top-level integration (to be written)
tb/          Independent verification environment (to be written)
docs/        Architecture and source-boundary documentation
```

See [the porting status](docs/PORTING_STATUS.md) for the exact retained and
excluded modules, and [the architecture plan](docs/ARCHITECTURE_PLAN.md) for the
collaborative implementation sequence.

New contributors should start with [the development setup](docs/DEVELOPMENT.md)
and [the RTL interface conventions](docs/INTERFACES.md).
Current ALU and register-file follow-up ideas are recorded in
[the improvement proposals](docs/ALU_REGFILE_IMPROVEMENTS.md).

## Current priorities

The first milestone is a reproducible, buildable RV32I foundation:

1. define the new ISA and microarchitecture type package;
2. add a pinned Verilator lint and simulation flow;
3. add independent ALU and register-file unit tests;
4. replace the Synopsys DesignWare multiply/divide dependency;
5. document module interfaces before reconnecting the pipeline.

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
make synth-mul MUL_STAGES=2
make synth-div DIV_CYC=11
make sweep-muldiv
```

Generated files, synthesis logs, and JSON netlists are kept under `build/` and
can be removed with `make clean`.

The smoke flow exercises `rtl/common/sp_ff_array.sv`; the independent mul/div
flow also tests and synthesizes `mul_pipe` and `div_iterative`. The wrapper tests
use the production `rv32im_types` package. This does **not** imply that the
complete CPU builds: pipeline control and core integration are still missing.

## Public-release status

No course handouts, staff testbenches, benchmark binaries, reports, group-owned
RTL, or commercial tool scripts are included. A project license has not yet been
chosen. Contributors must submit only work they have the right to contribute;
the licensing decision is tracked as a project-governance Issue.
