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
make test-alu        run directed ALU tests
make test-regfile    run directed physical-register-file tests
make test-muldiv     run the multiply/divide parameter matrix
make check           run the normal local regression
make ci              verify pinned versions, then run make check
make sweep-muldiv    synthesize the multiply/divide parameter matrix
make clean           remove generated build files
```

Generated files are written below `build/` and are ignored by Git. If a build
behaves unexpectedly after a tool upgrade, run `make clean` once and retry.

## Source manifests and diagnostics

`filelists/smoke.f` is the version-controlled source manifest for the standalone
smoke flow. Both `make lint` and `make test` pass this manifest to Verilator, so
local development and CI compile the same RTL sources. Manifest paths are
relative to the repository root; add production smoke RTL there instead of
duplicating source lists in the Makefile.

Verilator diagnostics are written directly to the terminal and include the
source path and line number. A lint or compile error returns a nonzero status,
which causes both Make and GitHub Actions to fail at the offending command.

Before opening a pull request, run `make check` and record the command and tool
versions in the PR description.
