# Roadmap

## v0.1 — Reproducible RTL foundation

Goal: make the retained RTL lintable and selected modules independently
testable with an open-source toolchain.

- Decide the project license and contribution terms.
- Define coding, reset, ready/valid, and interface conventions.
- Implement the new `rv32im_types` package without copying mixed-authorship code.
- Add a pinned Verilator lint and simulation flow.
- Add ALU and register-file unit tests.
- Replace or isolate the Synopsys DesignWare multiply/divide implementation.

## v0.2 — Correct single-issue OoO RV32I core

Goal: execute and retire RV32I programs through a correctness-first OoO path.

- Implement decode, RAT/RRAT, free list, ROB, dispatch, and the missing general
  reservation station.
- Add precise commit and branch recovery.
- Use a simple memory model before introducing caches.
- Add architectural commit tracing and differential checking.

## v0.3 — RV32IM memory system

Goal: complete RV32IM and integrate an independently verified memory path.

- Add the open multiply/divide implementation.
- Implement LSQ ordering and store-to-load forwarding.
- Select one maintained I-cache implementation and integrate the D-cache.
- Run architectural and randomized regressions.

## v1.0 — Portfolio-quality superscalar core

Goal: publish reproducible correctness, performance, area, and timing evidence.

- Expand measured bottlenecks to a superscalar configuration.
- Add branch prediction and performance counters.
- Add formal properties and coverage reporting.
- Add Yosys/OpenROAD synthesis and timing flows.
- Publish architecture, verification, and PPA reports tied to release commits.
