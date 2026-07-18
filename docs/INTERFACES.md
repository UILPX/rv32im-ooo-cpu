# RTL interface conventions

These rules define the project-owned contracts used when retained blocks are
connected to new pipeline logic. They do not inherit behavior from the excluded
course package.

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
