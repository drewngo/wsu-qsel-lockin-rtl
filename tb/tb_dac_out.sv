// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// dac_out vs model: random sources, select, gain, shift, offset (dac_out.txt).

`timescale 1ns / 1ps

module tb_dac_out;
  import lockin_pkg::*;
  `include "vec_io.svh"

  logic clk = 0, rst_n = 0;
  always #4 clk = ~clk;

  logic [2:0]                  sel = '0;
  logic [OUT_GAIN_BITS-1:0]    gain = '0;
  logic [4:0]                  shift = '0;
  logic signed [DAC_BITS-1:0]  offset = '0;
  logic signed [MIX_BITS-1:0]  i1 = '0, q1 = '0, x2 = '0, y2 = '0;
  logic signed [DATA_BITS-1:0] dc = '0, xd = '0;
  logic signed [DAC_BITS-1:0]  dac;

  dac_out dut (.*);

  initial begin
    int fin, n = 0;
    string line;
    longint a, b, c, d, e, f, s, g, sh, off, exp;
    fin = vec_open("dac_out.txt");
    repeat (4) @(posedge clk);
    rst_n <= 1;
    while (vec_next(fin, line)) begin
      void'($sscanf(line, "%d %d %d %d %d %d %d %d %d %d %d", a, b, c, d, e, f, s, g, sh, off, exp));
      @(posedge clk);
      i1 <= a; q1 <= b; x2 <= c; y2 <= d; dc <= e; xd <= f;
      sel <= s; gain <= g; shift <= sh; offset <= off;
      repeat (7) @(posedge clk);
      check("dac", dac, exp, n++);
    end
    report("dac_out");
    $finish;
  end
endmodule
