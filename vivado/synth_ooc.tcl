# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
#
# Out-of-context build of lockin_top for the Red Pitaya's Zynq-7010:
# synth, place, route at 125 MHz, then utilization and timing reports.
#
#   vivado -mode batch -source vivado/synth_ooc.tcl                 (from the repo root)
#   vivado -mode batch -source vivado/synth_ooc.tcl -tclargs <part>  (other part)
#
# Needs Zynq-7000 device support in Vivado. Without it, pass a 7-series stand-in
# with the same fabric and speed grade, e.g. xc7a35tcpg236-1.
#
# Reports go to vivado/build/. Fails if the generated package was built with
# the simulation-only time scale.

set root  [file normalize [file dirname [info script]]/..]
set build $root/vivado/build
file mkdir $build

set pkg $root/rtl/lockin_pkg.sv
set fh [open $pkg r]; set txt [read $fh]; close $fh
if {![regexp {SIM_SCALE = 1;} $txt]} {
  error "rtl/lockin_pkg.sv was generated with SIM_SCALE != 1; regenerate with --scale 1"
}

set part xc7z010clg400-1
if {$argc > 0} { set part [lindex $argv 0] }
if {[llength [get_parts -quiet $part]] == 0} {
  error "part $part is not installed; add Zynq-7000 support or pass a stand-in part"
}
puts "Building for $part"
foreach f {lockin_pkg sine_rom cic_decim fir_decim lockin_core coil_nco dac_out lockin_top} {
  read_verilog -sv $root/rtl/$f.sv
}

synth_design -top lockin_top -part $part -mode out_of_context
create_clock -name clk -period 8.000 [get_ports clk]
opt_design
place_design
route_design

report_utilization    -file $build/utilization.rpt
report_timing_summary -file $build/timing.rpt -max_paths 10
report_utilization -hierarchical -file $build/utilization_hier.rpt

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "RESULT: WNS = $wns ns at 125 MHz"
