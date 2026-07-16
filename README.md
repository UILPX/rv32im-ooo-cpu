# RV32IM Out-of-Order CPU

Personal RISC-V CPU implementation by XP Liu.

This repository is a new engineering workspace for independently completing and
evolving an RV32IM out-of-order core. It is intentionally separate from the
original three-person ECE 411 repository. Only RTL files whose current tracked
lines were authored entirely by XP Liu were retained; team-owned and mixed-
authorship RTL was excluded and will be reimplemented here.

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
personal rewrite sequence.

## Public-release status

No course handouts, staff testbenches, benchmark binaries, reports, group-owned
RTL, or commercial tool scripts are included. A license has not yet been chosen,
so no permission to copy or redistribute this repository is granted yet.
