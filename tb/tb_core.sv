// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// lockin_core vs model: 0.5 s of x_d (lockin_in.txt), one sample every GAP
// clocks -> dc, I1, Q1, X2, Y2 after every sample (lockin_out.txt).

`timescale 1ns / 1ps

module tb_core;
  import lockin_pkg::*;
  `include "vec_io.svh"

  localparam int GAP = 80;    // real design: R_TOTAL = 5000

  logic clk = 0, rst_n = 0;
  always #4 clk = ~clk;

  logic [NCO_BITS-1:0]         nco_step = '0, phase_off1 = '0, phase_off2 = '0;
  logic                        in_valid = 0;
  logic signed [DATA_BITS-1:0] in_data  = '0;
  logic                        out_valid;
  logic signed [DATA_BITS-1:0] xd, dc;
  logic signed [MIX_BITS-1:0]  i1, q1, x2, y2;

  lockin_core dut (.*);

  int fexp;
  int n_out = 0;
  string line;

  always @(posedge clk) if (out_valid) begin
    longint e_dc, e_i1, e_q1, e_x2, e_y2;
    if (!vec_next(fexp, line)) check("extra output", 1, 0, n_out);
    else begin
      void'($sscanf(line, "%d %d %d %d %d", e_dc, e_i1, e_q1, e_x2, e_y2));
      check("dc", dc, e_dc, n_out);
      check("I1", i1, e_i1, n_out);
      check("Q1", q1, e_q1, n_out);
      check("X2", x2, e_x2, n_out);
      check("Y2", y2, e_y2, n_out);
    end
    n_out++;
  end

  initial begin
    int fin, freg;
    longint v, r0, r1, r2;
    freg = vec_open("lockin_regs.txt");
    void'(vec_next(freg, line));
    void'($sscanf(line, "%d %d %d", r0, r1, r2));
    nco_step   = r0;
    phase_off1 = r1;
    phase_off2 = r2;
    fin  = vec_open("lockin_in.txt");
    fexp = vec_open("lockin_out.txt");
    repeat (4) @(posedge clk);
    rst_n <= 1;
    while (vec_next(fin, line)) begin
      void'($sscanf(line, "%d", v));
      @(posedge clk);
      in_valid <= 1;
      in_data  <= v;
      @(posedge clk) in_valid <= 0;
      repeat (GAP - 2) @(posedge clk);
    end
    repeat (GAP) @(posedge clk);
    if (vec_next(fexp, line)) check("missing output", 0, 1, n_out);
    report("lockin_core");
    $finish;
  end
endmodule
