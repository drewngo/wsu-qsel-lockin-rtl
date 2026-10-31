// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// lockin_top end to end at the real rates: ADC codes every clock
// (top_adc.txt) through CIC, FIR, core and DAC2 -> top_out.txt, checked after
// every decimated sample.

`timescale 1ns / 1ps

module tb_top;
  import lockin_pkg::*;
  `include "vec_io.svh"

  localparam int DAC_LAT = 7;

  logic clk = 0, rst_n = 0;
  always #4 clk = ~clk;

  logic signed [ADC_BITS-1:0]  adc = '0;
  logic [NCO_BITS-1:0]         nco_inc = '0, phase_off1 = '0, phase_off2 = '0;
  logic [COIL_AMP_BITS-1:0]    coil_amp = '0;
  logic [2:0]                  out_sel = '0;
  logic [OUT_GAIN_BITS-1:0]    out_gain = '0;
  logic [4:0]                  out_shift = '0;
  logic signed [DAC_BITS-1:0]  out_offset = '0;
  logic                        lia_valid;
  logic signed [DATA_BITS-1:0] lia_xd, lia_dc;
  logic signed [MIX_BITS-1:0]  lia_i1, lia_q1, lia_x2, lia_y2;
  logic signed [DAC_BITS-1:0]  dac1, dac2;

  lockin_top dut (.*);

  int fexp;
  int n_out = 0;
  string line;
  longint e_dac2;
  logic [DAC_LAT-1:0] lia_d = '0;   // lia_valid delayed to when dac2 has settled

  always @(posedge clk) begin
    string l;
    longint e_dc, e_i1, e_q1, e_x2, e_y2;
    lia_d <= {lia_d[DAC_LAT-2:0], lia_valid};
    if (lia_valid) begin
      if (!vec_next(fexp, l)) check("extra output", 1, 0, n_out);
      else begin
        void'($sscanf(l, "%d %d %d %d %d %d", e_dc, e_i1, e_q1, e_x2, e_y2, e_dac2));
        check("dc", lia_dc, e_dc, n_out);
        check("I1", lia_i1, e_i1, n_out);
        check("Q1", lia_q1, e_q1, n_out);
        check("X2", lia_x2, e_x2, n_out);
        check("Y2", lia_y2, e_y2, n_out);
      end
      n_out++;
    end
    if (lia_d[DAC_LAT-1]) check("dac2", dac2, e_dac2, n_out - 1);
  end

  initial begin
    int fin, freg;
    longint v, r[8];
    freg = vec_open("top_regs.txt");
    void'(vec_next(freg, line));
    void'($sscanf(line, "%d %d %d %d %d %d %d %d", r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]));
    nco_inc    = r[0];
    phase_off1 = r[1];
    phase_off2 = r[2];
    coil_amp   = r[3];
    out_sel    = r[4];
    out_gain   = r[5];
    out_shift  = r[6];
    out_offset = r[7];
    fin  = vec_open("top_adc.txt");
    fexp = vec_open("top_out.txt");
    repeat (3) @(posedge clk);
    // The CIC integrates every clock out of reset, so release reset together
    // with the first sample; otherwise it integrates one extra 0 and every
    // decimation instant shifts by a clock relative to the model.
    while (vec_next(fin, line)) begin
      void'($sscanf(line, "%d", v));
      @(posedge clk);
      adc   <= v;
      rst_n <= 1;
    end
    repeat (200) @(posedge clk);
    if (vec_next(fexp, line)) check("missing output", 0, 1, n_out);
    report("lockin_top");
    $finish;
  end
endmodule
