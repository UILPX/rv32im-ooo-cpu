# Type package

`rv32im_types.sv` is the central contract for retained RTL and future pipeline
work. It defines RV32IM micro-operations, register and tag widths, execution and
writeback records, fetch records, and cache request/response records.

The 6-bit `uop_t` is intentionally wide enough for the complete RV32IM operation
set. Queue depths remain module parameters; interface tag widths are centralized
here and should be changed only with all producers and consumers reviewed.
