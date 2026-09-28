# RTL interface conventions

These rules define the project-owned contracts used when retained blocks are
connected to new pipeline logic. They do not inherit behavior from the excluded
course package.

## Inferred single-port SRAM

`sp_sram` is the portable simulation and synthesis implementation used behind
the cache-array wrappers. Its port follows the active-low OpenRAM convention:

- `csb0 == 0` selects the memory;
- `web0 == 0` performs a synchronous masked write;
- `web0 == 1` performs a synchronous read and updates `dout0` after the rising
  edge;
- an unselected memory holds its previous `dout0` value.

The data storage is intentionally not reset. Cache valid bits are held in
separate resettable arrays, so unwritten tag and data values must never be
observed as valid cache entries. `mp_cache_data_array` provides the existing
16-by-256-bit cache data interface with byte write enables, while
`mp_cache_tag_array` provides the 16-by-23-bit tag interface.

These modules infer memory or registers in a generic RTL flow. An ASIC flow may
replace the two wrappers with technology-specific SRAM macros while preserving
their cycle-level interface.

## Clock and reset

- Sequential state uses `always_ff @(posedge clk)`.
- `rst` is active-high and synchronous to `clk`.
- State with externally visible validity resets to empty or invalid. Data fields
  may reset to zero for deterministic simulation but must not be consumed while
  their valid bit is clear.
- For modules with both signals, priority is `rst`, then `flush`, then normal
  transfers.

## Ready/valid transfers

A transfer occurs on a rising clock edge when both `valid` and `ready` are high:

```systemverilog
assign fire = valid && ready;
```

- A producer holds `valid` and its payload stable until `fire`.
- A consumer may change `ready` combinationally, but combinational ready/valid
  loops across modules are not allowed.
- Inputs are meaningful only while `valid` is high. Outputs are meaningful only
  while their corresponding valid signal is high.
- A buffered unit may deliberately reject a new input while its old output is
  granted. Such a throughput bubble must be documented by that module.

Writeback interfaces use the same rule with `grant` in place of `ready`:

```systemverilog
assign wb_fire = wb.valid && wb_grant;
```

The producer keeps the complete `wb_bus_t` stable until `wb_fire`.

## Flush behavior

- `flush` is active-high and synchronous.
- No new dispatch or issue transfer is accepted while `flush` is high.
- Speculative queued, executing, and buffered writeback state is discarded at
  the flush edge unless a module explicitly documents non-speculative state.
- A reset or flush wins over a same-cycle ready/valid or grant transfer.

## Ordering and lanes

- In an instruction bundle, lane 0 is older than lane 1; lane indices increase
  from older to younger instructions.
- Writeback lanes are unordered broadcasts. Consumers must not infer instruction
  age from the writeback lane number.
- When two register-file write ports target the same physical register, the
  current implementation gives the higher-numbered port priority. Producers
  should avoid this condition; an assertion is proposed before integration.

## Branch prediction

- `br_pred` accepts two already-fetched instructions. Lane 0 is older; a taken
  lane-0 prediction prevents lane 1 from being delivered by `i_fetch_ooo`.
- Conditional direction uses a parameterized gshare table initialized weakly
  taken. Direct immediates supply branch and JAL targets, and the RAS supplies
  return targets. Adjacent or consecutive link-register AUIPC/JALR pairs are
  recognized without a BTB.
- Predictor updates are intended to come only from committed control-flow
  instructions. `predecode_flush` clears only pending AUIPC pairing state;
  committed PHT and RAS state is not speculative and therefore survives a
  frontend flush.
- `PHT_ENTRIES` and `RAS_ENTRIES` must each be a power of two and at least two.
  The `update_is_jalr` and `update_target` ports are reserved for a future
  indirect-target structure and do not currently change predictor state.

## Frontend to dispatch

`frontend` combines `i_fetch_ooo`, branch prediction, and an ordered fetch FIFO.
The current instruction-cache and predictor boundary has two physical lanes, so
`FETCH_WIDTH` may be 1 or 2. `DISPATCH_WIDTH` may independently be 1 or 2, and
`QUEUE_DEPTH` controls how many fetched instructions can wait for dispatch.

- `dispatch_valid[0]` describes the oldest queued instruction;
- lane 1 is valid only when lane 0 is valid and a second instruction is queued;
- dispatch accepts lane 0 when `dispatch_valid[0] && dispatch_ready[0]`;
- lane 1 can be accepted only in the same cycle as lane 0, with both ready bits
  asserted;
- any valid lane that is not accepted remains stable;
- `flush` immediately suppresses dispatch outputs and clears the FIFO on the
  next rising edge.

This prefix rule preserves program order while still allowing a one-wide
dispatch stage to consume instructions from a two-wide fetch configuration.

## Decode to rename

`frontend_decode` adds the combinational RV32IM `decode_stage` to the ordered
fetch frontend. `DECODE_WIDTH` may be one or two. It emits `decoded_uop_t`
records without adding a pipeline register, so a future rename stage may choose
where to register this timing path.

- `fu_class` routes a valid operation toward integer, branch, multiply/divide,
  load, store, or system handling;
- `uses_rs1`, `uses_rs2`, and `writes_rd` describe encoded dependencies. A
  rename stage must still treat architectural register `x0` as a constant and
  must not allocate a physical destination for it;
- `imm` is the sign-extended I/S/B/J immediate or the aligned U immediate.
  Shift-immediate operations retain their complete I-format immediate; execute
  logic selects the low five shift-amount bits;
- branch-prediction metadata and `rvfi_order` are preserved in the nested
  `fetch` record. `bp_is_call` and `bp_is_return` use the standard `x1`/`x5`
  link-register hints;
- unsupported or reserved encodings remain valid pipeline entries with
  `OP_INVALID`, `FU_INVALID`, and `illegal` asserted. They are not discarded,
  allowing the ROB to retire a precise illegal-instruction exception;
- lane 1 never transfers without lane 0. `flush` suppresses both valid and ready
  in the combinational decode boundary.

The decoder intentionally does not allocate ROB entries, rename registers, or
route reservation stations. Those policies belong to independently testable
backend stages.

`decode_buffer` is a parameterized one- or two-wide FIFO between combinational
decode and backend rename. It preserves lane-prefix order and clears on flush.
Its upstream ready depends only on registered occupancy, not a same-cycle
backend pop; this creates a hard timing boundary at the cost of a possible
one-cycle recovery bubble when a completely full queue starts draining.

## Rename to ROB and dispatch

`rename` owns the speculative RAT, committed RRAT, physical-register free mask,
and readiness scoreboard. It accepts one or two decoded instructions and emits
`renamed_uop_t` records for the ROB/dispatch boundary.

- reset maps architectural `x0..x31` to physical `p0..p31`; remaining physical
  registers start free;
- architectural `x0` always maps to `p0`, is always ready, and never allocates a
  destination;
- lane 1 observes lane 0's new mapping for same-bundle RAW and WAW dependencies;
- a newly allocated destination is not ready until a matching writeback bus is
  observed. Same-cycle writeback is visible in the rename output;
- each destination carries `stale_phy_rd`, which the ROB returns on commit;
- commit updates the RRAT and releases the stale physical mapping in program
  order. If both commit lanes write the same architectural register, lane 1 is
  younger and its mapping wins;
- `flush` has priority over commit and rename. It restores the RAT from the RRAT,
  rebuilds the free mask from committed mappings, and marks committed sources
  ready in one cycle;
- commit-released registers are not reused by rename in the same cycle. The
  configured physical-register surplus must therefore cover the maximum number
  of in-flight destinations. The planned 64-register/16-entry-ROB baseline has
  sufficient headroom.

The rename outputs are combinational. A short registered dispatch bundle will
be inserted after ROB allocation so the eventual timing path does not combine
decode, rename, reservation-station routing, and issue selection in one cycle.

## Reorder buffer

`rob` is a parameterized circular queue with one- or two-wide allocation and
in-order commit. It assigns `rob_tag` values before dispatch and stores the
corresponding `rob_uop_t` until retirement.

- ROB allocation and dispatch are one atomic ready/valid transfer; an entry is
  never allocated unless the downstream dispatch boundary accepts it;
- completion uses explicit ROB tags rather than physical destinations. Its
  payload also carries the architectural destination value, branch
  outcome/target/mispredict, and a precise exception cause, so retirement can
  produce a commit trace even when an operation has no register write;
- `exception_cause_t` uses the standard synchronous RISC-V `mcause` values;
  `EXC_NONE=15` is an internal invalid sentinel and is never reported with a
  valid trap;
- out-of-order completion is recorded, but commit exposes only the oldest
  contiguous completed prefix;
- commit backpressure is supported. A full ROB may retire and reuse up to two
  slots in the same cycle;
- decoded illegal instructions are complete immediately after allocation so a
  future trap controller can handle them precisely at the head;
- `flush` suppresses allocation and commit and clears all uncommitted entries.
  Execution and memory producers must receive the same flush so stale
  completion tags cannot reach a reused ROB slot.

The initial correctness path will redirect mispredicted control flow at commit,
then flush younger state. This deliberately sacrifices branch latency until a
checkpointed or selective recovery mechanism is added.

## Dispatch buffering and routing

`dispatch_buffer` is a short parameterized FIFO placed between ROB allocation
and reservation-station capacity checks. It permits simultaneous two-wide pop
and push, preserves the lane-prefix order, and prevents RS backpressure from
forming a direct combinational path through ROB, rename, decode, and fetch.

`dispatch_router` is stateless. It reads four physical-register operands and
formats two shared `res_stat_t` records, then routes accepted lanes toward the
integer, branch, multiply/divide, or memory station.

Because a renamed uop may wait after its producer writes back, the registered
dispatch buffer snoops both writeback buses and updates the stored source-ready
bits. New pushes receive the same-cycle bypass. This prevents stale readiness
snapshots without placing a dynamic scoreboard lookup on the dispatch-to-RS
timing path.

- each station exposes the existing capacity convention: `port_ready[0]`
  means at least one insertion slot and `port_ready[1]` means at least two;
- two lanes targeting the same station consume insertion slots zero and one;
  a lane-1 instruction targeting a different station uses that station's slot
  zero and selects shared bus lane 1;
- lane 1 never bypasses a blocked lane 0;
- immediate integer operations receive `imm` as operand two, and AUIPC receives
  `pc + imm` operands without special handling in the ALU;
- system instructions use a separate, single-issue completion sink. The
  backend accepts them only at the ROB head after the LSU has drained, making
  `FENCE` an ordering boundary and keeping traps precise; illegal instructions
  require no station because the ROB already marks them complete;
- `flush` suppresses all router transfers and clears the registered buffer.

The router does not choose issue candidates or arbitrate writeback. Those remain
owned by reservation stations and the writeback controller.

## Integer and branch execution

`alu_exec` adapts the existing buffered integer `alu` to the ROB protocol. It
keeps the ROB tag beside the ALU result and sends completion only when the
writeback bus accepts that result. Writes to physical register zero consume no
writeback bandwidth and complete directly.

`branch_unit` handles RV32I conditional branches, JAL, and JALR. It buffers one
result, clears JALR target bit zero, and reports the resolved target, direction,
and misprediction in `rob_complete_t`. A link-register branch completes after
its `pc + 4` writeback is granted; a branch without a destination completes
without using the writeback bus. Taken targets that are not four-byte aligned
produce a precise `EXC_INST_MISALIGNED`; a faulting jump neither writes its link
register nor reports a simultaneous misprediction. `flush` cancels buffered
results in both units.

One-entry `issue_buffer` instances register integer, branch, and multiply/divide candidates
between reservation-station selection and execution. They allow simultaneous
consume/replace, preserving one-per-cycle steady-state issue while preventing
FU readiness from feeding back through dispatch selection.

`muldiv_exec` preserves the standalone `muldiv` interface while adapting it to
ROB completion. A small tag FIFO follows the pipelined multiplier, and a single
tag register follows the iterative divider. Multiply and divide may be in flight
at the same time; flush clears both execution state and their completion tags.
`ENABLE_RV32M=0` propagates from the CPU top through decode and backend
elaboration: M encodings remain illegal uops and the entire execution cluster is
removed rather than left idle in the synthesized design.

## Commit and backend integration

`commit_control` converts the oldest completed ROB prefix into RRAT/free-list
updates, predictor training, retirement records, recovery, and trap reporting.
A mispredicted branch or exception retires normally; the following cycle emits
one `flush` pulse after the committed mapping has reached the RRAT. Lane 1 is
held when lane 0 triggers recovery. Two control-flow instructions retire over
two cycles because the predictor has one update port.

`backend_core` connects rename, ROB, dispatch, integer/branch/multiply-divide
reservation stations, the ordered LSU, issue buffers, execution,
physical-register writeback, and commit. Its two result slots currently use a
fixed priority of memory, branch, divide, multiply, then integer. Counters report
cycles, retired instructions, retired branches, retired branch mispredictions,
frontend backpressure, ROB-full cycles, and RS-full dispatch stalls.

- `perf_frontend_stall_count` increments when decode lane 0 is valid but the
  backend does not accept it;
- `perf_rob_full_count` increments for every sampled cycle with a full ROB;
- `perf_rs_full_count` increments when the oldest buffered dispatch operation
  targets an integer, branch, or enabled MulDiv station with no free entry.

Counters stop while a trap is held for the external host, matching the existing
cycle and instruction-retirement measurement interval.

## Types, widths, and naming

- Shared ISA and pipeline records live in `rtl/pkg/rv32im_types.sv`.
- Use `uop_t`, `phys_reg_t`, `rob_tag_t`, and the packed interface structures
  instead of duplicating raw widths at module boundaries.
- Queue depths remain module parameters. A shared interface width changes only
  after every producer and consumer has been reviewed.
- Parameters and local parameters use upper snake case. Types end in `_t`;
  registered state ends in `_q`, next state in `_d` or `_n`, and transfer events
  end in `_fire`.

## Assertions and unknown values

- Testbenches and integration wrappers should assert that control inputs are not
  unknown when sampled.
- Payload unknown checks are required only when the associated valid signal is
  high.
- Protocol assertions belong near the interface they protect. They must not
  change synthesized behavior.

These conventions favor explicit one-cycle contracts and simple verification.
More aggressive combinational bypassing is allowed only when its timing path and
same-cycle behavior are documented and tested.
