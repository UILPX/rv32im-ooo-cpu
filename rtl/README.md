# RTL layout

The directory structure separates stable reusable blocks from the CPU top level.
Retained RTL keeps its existing module names; interfaces may change only when the
new personal package and integration code are designed.

- `common/`: storage primitives without CPU policy.
- `pkg/`: personal ISA constants, packed structures, and interface types.
- `frontend/`: fetch, prediction, and instruction delivery.
- `backend/`: register state, rename, scheduling, writeback, and retirement.
- `execute/`: functional units.
- `memory/`: memory ordering, caches, and external-memory adaptation.
- `core/`: top-level CPU composition.

There is intentionally no full-CPU compile manifest yet because pipeline control,
memory macros, and top-level integration are still incomplete.

`execute/mul_pipe.sv` and `execute/div_iterative.sv` are standalone and do not
depend on the CPU package. `mul_pipe.NUM_STAGES` controls multiplier latency
(`NUM_STAGES - 1` cycles), while `div_iterative.DIV_CYC` sets the exact number
of cycles used for a nonzero unsigned division.
