# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
#
# Red Pitaya STEMlab 125-14 pins for rp_lockin_top.
# Pin numbers, I/O standards and the ADC input delay are taken from
# pavel-demin/red-pitaya-notes cfg/ports.xdc and cfg/clocks.xdc.

### ADC clock (125 MHz from the ADC)

set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports adc_clk_p_i]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports adc_clk_n_i]
set_property PACKAGE_PIN U18 [get_ports adc_clk_p_i]
set_property PACKAGE_PIN U19 [get_ports adc_clk_n_i]

create_clock -name adc_clk -period 8.000 [get_ports adc_clk_p_i]

### ADC data, channel A (IN1)

set_property IOSTANDARD LVCMOS18 [get_ports {adc_dat_a_i[*]}]
set_property IOB TRUE [get_ports {adc_dat_a_i[*]}]

set_property PACKAGE_PIN V17 [get_ports {adc_dat_a_i[0]}]
set_property PACKAGE_PIN U17 [get_ports {adc_dat_a_i[1]}]
set_property PACKAGE_PIN Y17 [get_ports {adc_dat_a_i[2]}]
set_property PACKAGE_PIN W16 [get_ports {adc_dat_a_i[3]}]
set_property PACKAGE_PIN Y16 [get_ports {adc_dat_a_i[4]}]
set_property PACKAGE_PIN W15 [get_ports {adc_dat_a_i[5]}]
set_property PACKAGE_PIN W14 [get_ports {adc_dat_a_i[6]}]
set_property PACKAGE_PIN Y14 [get_ports {adc_dat_a_i[7]}]
set_property PACKAGE_PIN W13 [get_ports {adc_dat_a_i[8]}]
set_property PACKAGE_PIN V12 [get_ports {adc_dat_a_i[9]}]
set_property PACKAGE_PIN V13 [get_ports {adc_dat_a_i[10]}]
set_property PACKAGE_PIN T14 [get_ports {adc_dat_a_i[11]}]
set_property PACKAGE_PIN T15 [get_ports {adc_dat_a_i[12]}]
set_property PACKAGE_PIN V15 [get_ports {adc_dat_a_i[13]}]
set_property PACKAGE_PIN T16 [get_ports {adc_dat_a_i[14]}]
set_property PACKAGE_PIN V16 [get_ports {adc_dat_a_i[15]}]

set_input_delay -max 1.000 -clock adc_clk [get_ports {adc_dat_a_i[*]}]

### ADC clock duty-cycle stabilizer

set_property IOSTANDARD LVCMOS18 [get_ports adc_csn_o]
set_property PACKAGE_PIN V18 [get_ports adc_csn_o]
set_property SLEW FAST [get_ports adc_csn_o]
set_property DRIVE 8 [get_ports adc_csn_o]

### DAC

set_property IOSTANDARD LVCMOS33 [get_ports {dac_dat_o[*]}]
set_property SLEW SLOW [get_ports {dac_dat_o[*]}]
set_property DRIVE 4 [get_ports {dac_dat_o[*]}]

set_property PACKAGE_PIN M19 [get_ports {dac_dat_o[0]}]
set_property PACKAGE_PIN M20 [get_ports {dac_dat_o[1]}]
set_property PACKAGE_PIN L19 [get_ports {dac_dat_o[2]}]
set_property PACKAGE_PIN L20 [get_ports {dac_dat_o[3]}]
set_property PACKAGE_PIN K19 [get_ports {dac_dat_o[4]}]
set_property PACKAGE_PIN J19 [get_ports {dac_dat_o[5]}]
set_property PACKAGE_PIN J20 [get_ports {dac_dat_o[6]}]
set_property PACKAGE_PIN H20 [get_ports {dac_dat_o[7]}]
set_property PACKAGE_PIN G19 [get_ports {dac_dat_o[8]}]
set_property PACKAGE_PIN G20 [get_ports {dac_dat_o[9]}]
set_property PACKAGE_PIN F19 [get_ports {dac_dat_o[10]}]
set_property PACKAGE_PIN F20 [get_ports {dac_dat_o[11]}]
set_property PACKAGE_PIN D20 [get_ports {dac_dat_o[12]}]
set_property PACKAGE_PIN D19 [get_ports {dac_dat_o[13]}]

set_property IOSTANDARD LVCMOS33 [get_ports {dac_wrt_o dac_sel_o dac_clk_o dac_rst_o}]
set_property SLEW FAST [get_ports {dac_wrt_o dac_sel_o dac_clk_o dac_rst_o}]
set_property DRIVE 8 [get_ports {dac_wrt_o dac_sel_o dac_clk_o dac_rst_o}]

set_property PACKAGE_PIN M17 [get_ports dac_wrt_o]
set_property PACKAGE_PIN N16 [get_ports dac_sel_o]
set_property PACKAGE_PIN M18 [get_ports dac_clk_o]
set_property PACKAGE_PIN N15 [get_ports dac_rst_o]

### LEDs

set_property IOSTANDARD LVCMOS33 [get_ports {led_o[*]}]
set_property SLEW SLOW [get_ports {led_o[*]}]
set_property DRIVE 4 [get_ports {led_o[*]}]

set_property PACKAGE_PIN F16 [get_ports {led_o[0]}]
set_property PACKAGE_PIN F17 [get_ports {led_o[1]}]
set_property PACKAGE_PIN G15 [get_ports {led_o[2]}]
set_property PACKAGE_PIN H15 [get_ports {led_o[3]}]
set_property PACKAGE_PIN K14 [get_ports {led_o[4]}]
set_property PACKAGE_PIN G14 [get_ports {led_o[5]}]
set_property PACKAGE_PIN J15 [get_ports {led_o[6]}]
set_property PACKAGE_PIN J14 [get_ports {led_o[7]}]

### Outputs and the LED path are slow or forwarded clocks; do not time them.

set_false_path -to [get_ports {led_o[*] dac_rst_o adc_csn_o}]
