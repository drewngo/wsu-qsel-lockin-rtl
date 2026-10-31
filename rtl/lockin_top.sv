// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Open-loop lock-in, one ADC channel:
//
//   adc (14b @ clk) -> cic_decim -> fir_decim -> lockin_core -> I1/Q1/X2/Y2/dc
//                                                            -> dac_out -> dac2
//   coil_nco -> dac1 (77 Hz coil drive, same NCO frequency as the core)
//
// Registers are plain ports for now; an AXI-Lite register block goes on top
// in Phase 4. The control loop (normalizer, lock detect, PI) is not here yet.

module lockin_top
  import lockin_pkg::*;
(
  input  logic                         clk,          // 125 MHz ADC clock
  input  logic                         rst_n,
  // ADC (two's complement, one sample per clock)
  input  logic signed [ADC_BITS-1:0]   adc,
  // Registers
  input  logic [NCO_BITS-1:0]          nco_inc,      // f_mod = nco_inc * f_clk / 2^NCO_BITS
  input  logic [NCO_BITS-1:0]          phase_off1,
  input  logic [NCO_BITS-1:0]          phase_off2,
  input  logic [COIL_AMP_BITS-1:0]     coil_amp,
  input  logic [2:0]                   out_sel,
  input  logic [OUT_GAIN_BITS-1:0]     out_gain,
  input  logic [4:0]                   out_shift,
  input  logic signed [DAC_BITS-1:0]   out_offset,
  // Status (for the ARM)
  output logic                         lia_valid,    // pulses when the outputs below update
  output logic signed [DATA_BITS-1:0]  lia_xd,
  output logic signed [DATA_BITS-1:0]  lia_dc,
  output logic signed [MIX_BITS-1:0]   lia_i1,
  output logic signed [MIX_BITS-1:0]   lia_q1,
  output logic signed [MIX_BITS-1:0]   lia_x2,
  output logic signed [MIX_BITS-1:0]   lia_y2,
  // DACs (two's complement)
  output logic signed [DAC_BITS-1:0]   dac1,         // coil
  output logic signed [DAC_BITS-1:0]   dac2          // selected lock-in output
);

  // Core NCO step per decimated sample (wraps mod 2^NCO_BITS like the model)
  logic [NCO_BITS-1:0] nco_step;
  always_ff @(posedge clk) nco_step <= NCO_BITS'(nco_inc * R_TOTAL);

  logic                         cic_v, fir_v;
  logic signed [DATA_BITS-1:0]  cic_d, fir_d;

  cic_decim u_cic (
    .clk, .rst_n,
    .in_valid (1'b1), .in_data (adc),
    .out_valid(cic_v), .out_data(cic_d)
  );

  fir_decim u_fir (
    .clk, .rst_n,
    .in_valid (cic_v), .in_data (cic_d),
    .out_valid(fir_v), .out_data(fir_d)
  );

  lockin_core u_core (
    .clk, .rst_n,
    .nco_step, .phase_off1, .phase_off2,
    .in_valid (fir_v), .in_data (fir_d),
    .out_valid(lia_valid),
    .xd(lia_xd), .dc(lia_dc), .i1(lia_i1), .q1(lia_q1), .x2(lia_x2), .y2(lia_y2)
  );

  dac_out u_dac2 (
    .clk, .rst_n,
    .sel(out_sel), .gain(out_gain), .shift(out_shift), .offset(out_offset),
    .i1(lia_i1), .q1(lia_q1), .x2(lia_x2), .y2(lia_y2), .dc(lia_dc), .xd(lia_xd),
    .dac(dac2)
  );

  coil_nco u_coil (
    .clk, .rst_n,
    .nco_inc, .amp(coil_amp),
    .dac(dac1)
  );

endmodule
