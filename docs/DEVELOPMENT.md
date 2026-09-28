# Development setup

The project uses GNU Make, Verilator for lint and simulation, and Yosys for
synthesis. Run commands from the repository root.

## Canonical Linux environment

CI uses Ubuntu 24.04 with these package versions:

- Verilator `5.020` (`5.020-1` Ubuntu package)
- Yosys `0.33` (`0.33-5build2` Ubuntu package)

On Ubuntu 24.04 or WSL2:

```sh
sudo apt-get update
sudo apt-get install build-essential make verilator=5.020-1 yosys=0.33-5build2
make ci
```

`make ci` rejects different Verilator or Yosys versions so the canonical flow
matches GitHub Actions.

## macOS development

Install Xcode Command Line Tools and Homebrew, then run:

```sh
xcode-select --install
make setup
make doctor
make check
```

Homebrew is a rolling package manager and cannot reproduce arbitrary historical
formula versions. The `Brewfile` is therefore a convenient native setup, while
Ubuntu CI is the reproducible reference. The currently tested native versions
are Verilator `5.050` and Yosys `0.67`.

## First checkout

```sh
git clone git@github.com:UILPX/rv32im-ooo-cpu.git
cd rv32im-ooo-cpu
make doctor
make check
```

Use an HTTPS clone URL instead if SSH keys are not configured.

## Useful targets

```text
make doctor          show active tool versions
make lint            lint the basic reusable RTL
make test            run the environment smoke test
make test-sram       run the portable single-port SRAM test
make test-alu        run directed ALU tests
make test-regfile    run directed physical-register-file tests
make test-rs         run generic reservation-station tests
make test-rename     run rename, free-list, readiness, and recovery tests
make test-rob        run ROB allocation, completion, and commit tests
make test-dispatch   run dispatch buffer, routing, and operand tests
make test-exec       run integer and branch execution-adapter tests
make test-commit     run precise commit, recovery, and trap-control tests
make test-backend    run the integrated integer/branch backend test
make test-cpu        run the end-to-end machine-code RV32I smoke program
make perf-cpu        run the deterministic RV32I loop performance baseline
make test-cache-adapter  run OOO cache-adapter protocol tests
make lint-cache-adapter  lint the shared OOO cache adapter
make lint-sram       lint the SRAM primitive and cache-array wrappers
make lint-frontend   lint the predictor and fetch integration
make test-decode     test every RV32IM decode family and prefix backpressure
make test-frontend   test predictor, fetch/decode, and widths 1 and 2
make synth-bp        synthesize the parameterized branch predictor
make synth-frontend  synthesize a selected fetch/dispatch width
make synth-frontend-decode  synthesize fetch through decoded-uop delivery
make synth-rename    synthesize the parameterized rename state
make synth-rob       synthesize the parameterized reorder buffer
make synth-dispatch  synthesize the dispatch buffer and FU router
make synth-exec      synthesize the integer and branch execution units
make synth-commit    synthesize precise commit and recovery control
make synth-backend   synthesize the current integrated backend
make ppa-asap7       run the pinned ASAP7 flow through post-route finish
make synth-sram      synthesize the inferred single-port SRAM
make test-muldiv     run the multiply/divide parameter matrix
make check           run the normal local regression
make ci              verify pinned versions, then run make check
make sweep-muldiv    synthesize the multiply/divide parameter matrix
make clean           remove generated build files
```

Generated files are written below `build/` and are ignored by Git. If a build
behaves unexpectedly after a tool upgrade, run `make clean` once and retry.

## Reproducible ASAP7 physical flow

Docker is the only additional dependency for the open physical-design flow:

```sh
make ppa-asap7
```

The target pins the OpenROAD Flow Scripts image by digest, runs the strict
RV32I `rv32i_cpu_ppa` wrapper, and stores results under `build/orfs/`. The image
is currently amd64-only; Docker Desktop transparently emulates it on Apple
Silicon. Native Verilator/Yosys development remains arm64 and does not require
this emulation. Override `ORFS_VARIANT` to keep independent experiments, or
`PPA_STAGE=grt` when only a global-route estimate is needed.

The default CPU configuration enables RV32M. Use `ENABLE_RV32M=0` with
`lint-cpu`, `lint-backend`, `synth-cpu`, or `synth-backend` for the strict RV32I
configuration used by the initial PPA target. M-extension instructions then
remain precise illegal-instruction traps and the MulDiv execution cluster is
elaborated away.

Before opening a pull request, run `make check` and record the command and tool
versions in the PR description.
