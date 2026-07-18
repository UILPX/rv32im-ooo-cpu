# Verification work

Build a new independent verification environment here. It should use
redistributable tests and an open-source simulator, and should not depend on the
ECE 411 staff testbench or benchmark artifacts.

`smoke/sp_ff_array_tb.sv` is the first environment smoke test. Run it with
`make test`; it exists to verify the Verilator setup before the CPU-level
testbench is implemented.

The `execute/` tests cover the standalone multiplier and divider across their
standard parameter matrix. They also verify the RV32M wrapper with the production
type package in `rtl/pkg/`. Run the full directed regression with `make
test-muldiv`.

`execute/alu_tb.sv` covers every currently supported ALU operation plus invalid
operations, output backpressure, grant behavior, and flush. `backend/regfile_tb.sv`
covers reset, the physical zero register, independent reads and writes, same-cycle
bypass, and same-address write priority. Run both with `make test-unit`.
