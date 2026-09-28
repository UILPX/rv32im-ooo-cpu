# Source boundary and porting status

## Selection rule

The source repository was reviewed at team baseline commit `3602bc3`. The
initial import retained files whose Git blame consisted entirely of commits
authored as `XP` and whose ownership did not conflict with the final team
report. A later mixed-file audit additionally accepts a block only when the
report assigns its area to XP and Git history contains an all-XP implementation
before another member's later edit. Mixed snapshots themselves are not copied.

The new repository has its own Git history. It does not copy the team repository
history, documentation, verification environment, benchmark artifacts, or build
system.

The course SRAM-generation scripts were also not copied. They called OpenRAM
through course-specific SCons infrastructure and commercial library tooling,
and their independent source-license provenance was not recorded in the team
repository. The current `sp_sram` and cache-array wrappers are clean project
implementations. A future ASIC flow may add OpenRAM separately with its BSD
attribution and the selected PDK's license terms.

The original team branch-predictor file remained excluded because a small part
of its tracked text had mixed authorship. The current `br_pred.sv` is a clean
project-owned implementation of XP's predictor design, with course-testbench
aliases and inherited package dependencies removed.

The same audit recovered two more usable blocks. The generic reservation
station was 98.9% XP at the baseline and is covered by XP's documented
reservation-station ownership; its three foreign initialization lines were not
copied. The cache adapter's final file was 88.9% XP, but commit `001893e^`
contains a 595-line, 100%-XP version. The current adapter is based on that
personal version and uses project-owned types and tests.

## Retained personal RTL

| Area | Files | Follow-up required |
| --- | --- | --- |
| Common | `sp_ff_array.sv` | Independent smoke test completed. |
| Execute | `alu.sv`, `muldiv.sv`, `mul_pipe.sv`, `div_iterative.sv` | Open-source mul/div IP and ROB-tagged backend integration completed; broader randomized checking remains. |
| Backend | `dispatch_buffer.sv`, `dispatch_router.sv`, `rob.sv`, `rename.sv`, `bus_controller.sv`, `regfile.sv`, `reservation_station.sv`, `reservation_station_branch.sv`, `reservation_station_simple.sv` | Project-owned dispatch, ROB, rename recovery, generic stations, precise commit, LSU, and RV32IM execution paths have directed tests. |
| Frontend | `frontend_decode.sv`, `decoder.sv`, `decode_stage.sv`, `frontend.sv`, `fetch_queue.sv`, `i_fetch_ooo.sv`, `br_pred.sv` | One- and two-wide fetch/decode, downstream backpressure, rename connection, and committed branch updates have directed tests. |
| Memory | `cacheline_adapter.sv`, `cache_ooo_bridge.sv`, `cache_adapter_ooo.sv`, `dcache.sv`, `icache.sv`, `icache_ooo.sv` | Portable inferred SRAM replacements are complete. Shared adapter has independent merge/burst/backpressure tests; flatten its struct-array boundary for Yosys, then select one I-cache path. |

The mixed-authorship type package was not copied. A new personal
`rtl/pkg/rv32im_types.sv` now defines the interfaces used by the retained RTL.
The clean project-owned pipeline now builds as a cacheless CPU baseline. Missing
privileged state, differential validation, and a selected cache path still
prevent describing it as a complete CPU.

## High-blame files that are not personal modules

| Original file | XP blame at `3602bc3` | Decision |
| --- | ---: | --- |
| `fetch/i_fetch.sv` | 84.3% | Excluded: the report assigns fetch to Xuantong Wang. |
| `rob.sv` | 77.6% | Excluded: the report assigns the ROB to Yuqi Lin. |
| `cpu.sv` | 61.7% | Excluded: top-level integration contains every member's module contracts. |

These percentages reflect later debugging and integration edits, not ownership
of the underlying module. They are recorded here so future imports do not use a
line-count threshold without the report and file history.

## Intentionally excluded

- Team-owned modules: fetch controller, dispatch, RAT/RRAT, branch functional
  unit, instruction queue, free list, decode, ROB, and LSQ. The current frontend
  and decoder are clean project replacements, not copies of those modules.
- Mixed-authorship integration files: the CPU top level, shared type package,
  original team branch-predictor snapshot, alternate fetch module, and the
  final mixed snapshots of the cache adapter and general reservation station.
- The final `icache_dm.sv` snapshot includes a later teammate power patch. Its
  1,035-line pre-patch version at `59078d9^` is fully XP-owned and eligible, but
  remains deferred until one maintained I-cache implementation is selected to
  replace the current duplicates.
- The extensionless `icache_noprefetch` legacy snapshot, even though its current
  lines were authored by XP, because it is an obsolete duplicate rather than a
  maintained source file.
- All course testbenches, course documents, benchmark images, reports, synthesis
  scripts, and simulator configuration.

## Completion gate

The project should not be described as a complete personal CPU until every
excluded CPU function has a new implementation, the retained modules use the new
interfaces, and an independent regression suite passes.
