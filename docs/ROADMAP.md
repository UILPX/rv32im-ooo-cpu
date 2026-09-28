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

## v0.2 — Correct single-issue OoO RV32IM core

Goal: execute and retire RV32IM programs through a correctness-first OoO path.

- Connect the completed decoder, rename state, ROB, dispatch, and general
  reservation station through execution and precise-control integration.
- Add precise commit and branch recovery.
- Use a simple memory model before introducing caches.
- Add architectural commit tracing and differential checking.
- Integrate the open multiply/divide unit with ROB-tagged completion.

## v0.3 — RV32IM memory system

Goal: complete RV32IM and integrate an independently verified memory path.

- Implement LSQ ordering and store-to-load forwarding.
- Select one maintained I-cache implementation and integrate the D-cache.
- Run architectural and randomized regressions.

## v1.0 — Portfolio-quality superscalar core

Goal: publish reproducible correctness, performance, area, and timing evidence.

- Expand measured bottlenecks to a superscalar configuration.
- Add branch prediction and performance counters.
- Add formal properties and coverage reporting.
- Keep the Yosys/OpenROAD flow electrically clean after extracted-RC routing.
- Publish architecture, verification, and PPA reports tied to release commits.
