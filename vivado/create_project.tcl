# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
#
# Create the Vivado GUI project for the Red Pitaya STEMlab 125-14 lock-in:
#
#   vivado -mode batch -source vivado/create_project.tcl   (from the repo root)
#   vivado vivado/project/rp_lockin.xpr                     (open it)
#
# Sources are referenced in place (not copied), so edits in rtl/ and tb/ show
# up in the project. Re-running this script rebuilds the project from scratch.
#
#   Design top      rp_lockin_top (board) -- Run Synthesis / Generate Bitstream
#   Constraints     vivado/rp_stemlab125_14.xdc
#   Simulation sets one per testbench; right-click a set > Make Active, then
#                   Run Simulation. Each prints TEST PASSED / TEST FAILED in the
#                   Tcl console. Vectors come from model/gen_vectors.py.

set root [file normalize [file dirname [info script]]/..]
set name rp_lockin
set dir  $root/vivado/project

create_project $name $dir -part xc7z010clg400-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# ---------------- design sources
set rtl {}
foreach f {lockin_pkg sine_rom cic_decim fir_decim lockin_core coil_nco dac_out lockin_top} {
  lappend rtl $root/rtl/$f.sv
}
foreach f {rp_adc rp_dac rp_clocks rp_lockin_top} {
  lappend rtl $root/rtl/board/$f.sv
}
add_files -norecurse -fileset sources_1 $rtl
set_property file_type SystemVerilog [get_files $rtl]
set_property top rp_lockin_top [get_filesets sources_1]

# Zynq processing system IP (see ps7_ip.tcl)
set ipdir $dir/ip
source $root/vivado/ps7_ip.tcl

# ---------------- constraints
add_files -norecurse -fileset constrs_1 $root/vivado/rp_stemlab125_14.xdc
set_property target_constrs_file $root/vivado/rp_stemlab125_14.xdc [current_fileset -constrset]

# ---------------- implementation: same steps as build_bitstream.tcl
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]

# ---------------- simulation: one fileset per testbench
set tests {
  tb_top     "lockin_top end to end at 125 MHz (ADC codes in, I/Q and DAC2 out)"
  tb_core    "lockin_core: DC blocker, NCO, mixers, LPF"
  tb_cic     "CIC decimator"
  tb_fir     "FIR decimator"
  tb_dac_out "DAC2 output stage"
  tb_coil    "coil NCO (DAC1)"
  tb_rp_io   "board ADC/DAC pin formats (Xilinx ODDR models)"
}

foreach {tb desc} $tests {
  set fs [create_fileset -simset sim_$tb]
  add_files -norecurse -fileset $fs $root/tb/$tb.sv $root/tb/vec_io.svh
  set_property file_type SystemVerilog [get_files -of_objects $fs $root/tb/$tb.sv]
  set_property file_type {Verilog Header} [get_files -of_objects $fs $root/tb/vec_io.svh]
  set_property include_dirs [list $root/tb] $fs
  set_property top $tb $fs
  set_property top_lib xil_defaultlib $fs
  set_property source_set sources_1 $fs
  set_property -name {xsim.simulate.runtime} -value {-all} -objects $fs
  set_property -name {xsim.simulate.log_all_signals} -value {false} -objects $fs
  set_property DESCRIPTION $desc $fs
}
current_fileset -simset [get_filesets sim_tb_top]
delete_fileset [get_filesets sim_1]

update_compile_order -fileset sources_1
foreach fs [get_filesets -filter {FILESET_TYPE == SimulationSrcs}] {
  update_compile_order -fileset $fs
}

puts "RESULT: created $dir/$name.xpr"
close_project
