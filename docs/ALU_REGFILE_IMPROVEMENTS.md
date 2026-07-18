# ALU and register-file improvement proposals

The directed tests preserve current behavior. The changes below are proposals
for later focused pull requests, not hidden behavior changes in the test work.

## ALU

### 1. Remove the grant-to-accept bubble

The current ALU accepts an issue only when its one-entry writeback buffer is
empty at the start of the cycle. Even when `wb_grant` consumes the old result,
the ALU waits until the following cycle before accepting another operation.

Proposed change:

```systemverilog
issue_ready = !flush && op_supported &&
              (!wb_buf_q.valid || wb_grant);
```

This can raise sustained throughput from one result every two cycles to one per
cycle under continuous grants. It also adds `wb_grant` to the issue-ready timing
path, so the change should follow an execution-cluster timing measurement and a
directed simultaneous dequeue/enqueue test.

### 2. Add protocol assertions

Assert that a blocked writeback remains stable, a supported operation is known
when accepted, and reset or flush clears validity. These properties protect the
module boundary without changing the datapath.

### 3. Keep control and memory operations separate

Do not expand this ALU into a branch or load/store unit merely to share adders.
Separate units keep flush, exception, and writeback behavior explicit. Share an
adder only if synthesis or timing evidence shows a meaningful benefit.

## Physical register file

### 1. Reject duplicate writes explicitly

The current loop gives the higher-numbered write port priority when two enabled
ports target the same nonzero physical register. That is deterministic, but a
correct rename/writeback pipeline should not produce the collision.

Add an assertion at integration time and treat a duplicate nonzero destination
as a pipeline bug. Keeping priority behavior as a simulation fallback is useful,
but downstream logic must not rely on it.

### 2. Add a separate physical-register readiness table

The data array does not track whether a newly allocated physical register is
ready. Rename should clear readiness on allocation; writeback should set it;
dispatch should read or bypass it. Keep readiness separate from register data so
the data array can later omit reset without losing deterministic control state.

### 3. Measure the multiport implementation

Four asynchronous reads, two writes, same-cycle bypass, and full data reset will
usually synthesize to flip-flops rather than a simple SRAM. This is reasonable
for the current 64-by-32 correctness-first core. Before increasing widths or
ports, compare:

- the current flop-based implementation;
- replicated memories with explicit bypass;
- banked registers with a defined conflict policy.

Use `RESET_DATA=0` only after readiness and architectural initialization make
uninitialized data unobservable.

### 4. Add parameter guards

Add elaboration checks for positive port counts, address width, and
`NUM_REGS <= 2**ADDR_WIDTH`. These make non-default synthesis experiments fail
early instead of silently indexing outside the implemented array.

## Recommended order

1. Add interface assertions and the readiness table as part of backend
   integration.
2. Measure the ALU grant path, then decide whether to enable same-cycle
   dequeue/enqueue.
3. Measure register-file area and timing before changing its physical structure.
