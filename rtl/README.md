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

There is intentionally no compile manifest yet because the mixed-authorship type
package was excluded and the retained modules cannot currently elaborate.
