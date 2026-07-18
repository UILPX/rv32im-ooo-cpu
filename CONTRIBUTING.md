# Contributing

Thank you for helping build the RV32IM out-of-order CPU. The project values
correctness, understandable RTL, reproducible evidence, and clear ownership over
feature count.

## Before starting

1. Read `README.md`, `docs/ARCHITECTURE_PLAN.md`, and
   `docs/PORTING_STATUS.md`.
2. Set up the toolchain with `docs/DEVELOPMENT.md` and follow the contracts in
   `docs/INTERFACES.md`.
3. Select an unassigned Issue labeled `status: ready`, or open a design proposal
   if an interface or architecture decision is missing.
4. Comment on the Issue before starting so a maintainer can assign it and avoid
   duplicate work.
5. Keep one Issue and one logical change per pull request whenever practical.

The CPU is not buildable yet. Until the initial tool flow lands, describe any
manual checks precisely and never report tests that were not run.

## Branches and commits

- `feature/<issue>-<short-name>` for new RTL or infrastructure.
- `fix/<issue>-<short-name>` for corrections.
- `docs/<issue>-<short-name>` for documentation-only work.
- Use short, imperative commit subjects.
- Do not rewrite another contributor's published history.

## RTL expectations

- Use synthesizable SystemVerilog and explicit signal widths.
- Use `always_ff` for sequential state and `always_comb` for combinational logic.
- Use nonblocking assignments in sequential logic and avoid inferred latches.
- Document reset state, backpressure, ordering, flush, and same-cycle behavior.
- Prefer ready/valid-style contracts at module boundaries where appropriate.
- Parameterize sizes only when multiple configurations will be tested.
- Add assertions for protocol invariants and directed tests for edge cases.
- Do not add proprietary or vendor-specific IP without an isolated replacement
  path and prior design approval.

## Pull requests

Every pull request should:

- link its Issue with `Closes #<number>` when it completes the task;
- explain the design and important alternatives;
- list exact tests and tool versions used;
- include before/after correctness, timing, area, or performance data when the
  change claims an improvement;
- update architecture or interface documentation when behavior changes;
- avoid unrelated formatting or refactoring.

At least one maintainer review is expected before merge. Authors should respond
to review comments themselves so design reasoning remains visible.

## Authorship and licensing

Submit only code and documentation you created or have permission to contribute.
Identify any adapted source in the pull request and preserve its license and
attribution. Unless explicitly stated otherwise, an intentionally submitted
contribution is provided under Apache-2.0, the same license as the project. Each
contributor retains copyright in their contribution. No contributor license
agreement is currently required.
