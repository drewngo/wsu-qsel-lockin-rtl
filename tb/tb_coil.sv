// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// coil_nco vs model: DAC1 sequence from reset (coil.txt). The NCO runs at
// 1 MHz here so the test sweeps the whole LUT. Finds the pipeline latency,
// then requires every sample to match.

`timescale 1ns / 1ps

module tb_coil;
  import lockin_pkg::*;
  `include "vec_io.svh"

  localparam int MAX_LAT = 8;

  logic clk = 0, rst_n = 0;
  always #4 clk = ~clk;

  logic [NCO_BITS-1:0]        nco_inc = '0;
  logic [COIL_AMP_BITS-1:0]   amp = '0;
  logic signed [DAC_BITS-1:0] dac;

  coil_nco dut (.*);

  longint exp_q[$];
  longint got_q[$];

  initial begin
    int fin, freg, lat;
    string line;
    longint v, r0, r1;
    bit ok;
    freg = vec_open("coil_regs.txt");
    void'(vec_next(freg, line));
    void'($sscanf(line, "%d %d", r0, r1));
    nco_inc = r0;
    amp     = r1;
    fin = vec_open("coil.txt");
    while (vec_next(fin, line)) begin
      void'($sscanf(line, "%d", v));
      exp_q.push_back(v);
    end
    repeat (4) @(posedge clk);
    rst_n <= 1;
    // got_q[k] = dac after the k-th clock out of reset
    repeat (exp_q.size() + MAX_LAT) begin
      @(posedge clk);
      #1 got_q.push_back(dac);
    end
    lat = -1;
    for (int l = 0; l <= MAX_LAT && lat < 0; l++) begin
      ok = 1;
      for (int k = 0; k < exp_q.size() && ok; k++) ok = (got_q[k + l] == exp_q[k]);
      if (ok) lat = l;
    end
    if (lat < 0) begin
      $display("no latency 0..%0d lines up; first samples:", MAX_LAT);
      for (int k = 0; k < 8; k++) $display("  rtl=%0d model=%0d", got_q[k], exp_q[k]);
      check("coil alignment", 0, 1, 0);
    end else begin
      $display("coil_nco latency: %0d clocks", lat);
      for (int k = 0; k < exp_q.size(); k++) check("dac1", got_q[k + lat], exp_q[k], k);
    end
    report("coil_nco");
    $finish;
  end
endmodule
