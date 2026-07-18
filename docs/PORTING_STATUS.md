# Source boundary and porting status

## Selection rule

The source repository was reviewed at team baseline commit `3602bc3`. A file was
retained only when its current Git blame consisted entirely of commits authored
as `XP` and the final team report did not assign that module to another member.
This deliberately conservative rule excludes files that XP later rewrote or
integrated when they still contain, derive from, or were assigned to another
team member's implementation.

The new repository has its own Git history. It does not copy the team repository
history, documentation, verification environment, benchmark artifacts, or build
system.

## Retained personal RTL

| Area | Files | Follow-up required |
| --- | --- | --- |
| Common | `sp_ff_array.sv` | Add independent tests. |
| Execute | `alu.sv`, `muldiv.sv`, `mul_pipe.sv`, `div_iterative.sv` | Open-source mul/div IP and production type integration completed; add ALU integration tests. |
| Backend | `bus_controller.sv`, `regfile.sv`, `reservation_station_branch.sv`, `reservation_station_simple.sv` | Production types defined; add independent unit and integration tests. |
| Frontend | `i_fetch_ooo.sv` | Reconnect to a new fetch controller and predictor. |
| Memory | `cacheline_adapter.sv`, `cache_ooo_bridge.sv`, `dcache.sv`, `icache.sv`, `icache_ooo.sv` | Memory interfaces defined; select one maintained I-cache path and replace missing SRAM macros. |

The mixed-authorship type package was not copied. A new personal
`rtl/pkg/rv32im_types.sv` now defines the interfaces used by the retained RTL;
missing pipeline modules and memory macros still prevent a complete CPU build.

## Intentionally excluded

- Team-owned modules: fetch controller, dispatch, RAT/RRAT, branch functional
  unit, instruction queue, free list, decode, ROB, and LSQ.
- Mixed-authorship integration files: the CPU top level, shared type package,
  branch predictor, shared cache adapter, direct-mapped I-cache, alternate fetch
  module, and general reservation station.
- The extensionless `icache_noprefetch` legacy snapshot, even though its current
  lines were authored by XP, because it is an obsolete duplicate rather than a
  maintained source file.
- All course testbenches, course documents, benchmark images, reports, synthesis
  scripts, and simulator configuration.

## Completion gate

The project should not be described as a complete personal CPU until every
excluded CPU function has a new implementation, the retained modules use the new
interfaces, and an independent regression suite passes.
