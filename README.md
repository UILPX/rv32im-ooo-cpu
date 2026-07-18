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
flow also tests and synthesizes `mul_pipe` and `div_iterative`. A test-only type
package verifies the retained `muldiv` wrapper. This does **not** imply that the
complete CPU builds: the production `rv32im_types` package and core integration
are still missing.

## Public-release status

No course handouts, staff testbenches, benchmark binaries, reports, group-owned
RTL, or commercial tool scripts are included. A license has not yet been chosen,
so no permission to copy or redistribute this repository is granted yet.
