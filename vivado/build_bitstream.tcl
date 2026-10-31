# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
#
# Full build of rp_lockin_top for the Red Pitaya STEMlab 125-14 (xc7z010clg400-1):
# synth, place, route, bitstream. Run from the repo root:
#
#   vivado -mode batch -source vivado/build_bitstream.tcl
#
# Outputs in vivado/build/bitstream/:
#   rp_lockin.bit       for older Red Pitaya OS:  cat rp_lockin.bit > /dev/xdevcfg
#   rp_lockin.bit.bin   for Red Pitaya OS 2.x:    fpgautil -b rp_lockin.bit.bin
#   timing.rpt, utilization.rpt
#
# Stops before writing a bitstream if timing fails or the package was
# generated with the simulation-only time scale.

set root [file normalize [file dirname [info script]]/..]
set out  $root/vivado/build/bitstream
file mkdir $out

set fh [open $root/rtl/lockin_pkg.sv r]; set txt [read $fh]; close $fh
if {![regexp {SIM_SCALE = 1;} $txt]} {
  error "rtl/lockin_pkg.sv was generated with SIM_SCALE != 1; regenerate with --scale 1"
}

set part xc7z010clg400-1
create_project -in_memory -part $part
set ipdir $root/vivado/build/ip
file delete -force $ipdir/rp_ps7
source $root/vivado/ps7_ip.tcl

foreach f {lockin_pkg sine_rom cic_decim fir_decim lockin_core coil_nco dac_out lockin_top} {
  read_verilog -sv $root/rtl/$f.sv
}
foreach f {rp_adc rp_dac rp_clocks rp_lockin_top} {
  read_verilog -sv $root/rtl/board/$f.sv
}
read_xdc $root/vivado/rp_stemlab125_14.xdc

synth_design -top rp_lockin_top -part $part
opt_design
place_design
phys_opt_design
route_design

report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing.rpt -max_paths 10
report_drc            -file $out/drc.rpt

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "RESULT: WNS = $wns ns, WHS = $whs ns"
if {$wns < 0 || $whs < 0} {
  error "timing not met; see $out/timing.rpt (no bitstream written)"
}

write_bitstream -force $out/rp_lockin.bit

# .bit.bin for the Linux FPGA manager (fpgautil), via bootgen
set bif $out/rp_lockin.bif
set fh [open $bif w]; puts $fh "all:{ $out/rp_lockin.bit }"; close $fh
set bootgen [file join [file dirname [info nameofexecutable]] .. .. bootgen]
if {$::tcl_platform(platform) eq "windows"} { set bootgen [file normalize $::env(XILINX_VIVADO)/bin/bootgen.bat] }
if {[catch {exec $bootgen -image $bif -arch zynq -process_bitstream bin -o $out/rp_lockin.bit.bin -w} msg]} {
  puts "WARNING: bootgen failed, no .bit.bin written: $msg"
} else {
  puts "RESULT: wrote $out/rp_lockin.bit and rp_lockin.bit.bin"
}
