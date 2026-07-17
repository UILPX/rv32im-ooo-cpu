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
buildable CPU. The shared type package, pipeline control, retirement path,
top-level integration, and independent testbench still need new implementations.
This status is explicit so future results are not confused with the earlier team
project.

Retained personal RTL currently covers:

- integer ALU and the existing multiply/divide unit;
- physical register file and selected reservation stations;
- cacheline adaptation, cache bridge, and instruction/data cache variants;
- an out-of-order instruction-fetch queue;
- small common storage and writeback-control utilities.

The existing multiply/divide unit instantiates Synopsys DesignWare and must be
replaced or isolated before an open-source build is possible.

## Structure

```text
rtl/
  common/    Small reusable RTL primitives
  pkg/       New personal ISA and microarchitecture types (to be written)
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

## Public-release status

No course handouts, staff testbenches, benchmark binaries, reports, group-owned
RTL, or commercial tool scripts are included. A project license has not yet been
chosen. Contributors must submit only work they have the right to contribute;
the licensing decision is tracked as a project-governance Issue.
