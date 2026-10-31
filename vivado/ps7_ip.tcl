# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
#
# Zynq processing system (PS7) IP for the Red Pitaya, configured from Red
# Pitaya's own board preset (vivado/red_pitaya.xml, from RedPitaya-FPGA
# prj/Examples/Led_blink/cfg). Sourced by build_bitstream.tcl and
# create_project.tcl with $root and $ipdir set.
#
# The design does not use the processor from the FPGA side yet, but the PS7
# instance must be present. On a STEMlab 125-14 running Red Pitaya OS 1.07, a
# bitstream built without it took the Ethernet down the moment it loaded; the
# same design with this instance loads cleanly. All PS-PL interfaces are
# disabled, so the instance only exposes the fixed DDR and MIO pins.

file mkdir $ipdir
create_ip -name processing_system7 -vendor xilinx.com -library ip -module_name rp_ps7 -dir $ipdir
set ps [get_ips rp_ps7]
set_property CONFIG.PCW_IMPORT_BOARD_PRESET $root/vivado/red_pitaya.xml $ps
set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0    {0} \
  CONFIG.PCW_USE_M_AXI_GP1    {0} \
  CONFIG.PCW_USE_S_AXI_HP0    {0} \
  CONFIG.PCW_EN_CLK0_PORT     {0} \
  CONFIG.PCW_EN_RST0_PORT     {0} \
  CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
] $ps
# Synthesize with the design (no separate out-of-context run)
set_property GENERATE_SYNTH_CHECKPOINT false [get_files rp_ps7.xci]
generate_target all [get_files rp_ps7.xci]
