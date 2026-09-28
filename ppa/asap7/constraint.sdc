current_design rv32i_cpu_ppa

set clk_name core_clock
set clk_period 1428
set clk_uncertainty 50
set io_delay [expr $clk_period * 0.20]

create_clock -name $clk_name -period $clk_period \
    -waveform [list 0 [expr $clk_period / 2]] [get_ports clk]
set_clock_uncertainty -setup $clk_uncertainty [get_clocks $clk_name]

set io_clock_name virtual_io_clock
create_clock -name $io_clock_name -period $clk_period
set_input_delay $io_delay -clock $io_clock_name [all_inputs -no_clocks]
set_output_delay $io_delay -clock $io_clock_name [all_outputs]

group_path -name in2reg -from [all_inputs -no_clocks] -to [all_registers]
group_path -name reg2reg -from [all_registers] -to [all_registers]
group_path -name reg2out -from [all_registers] -to [all_outputs]
