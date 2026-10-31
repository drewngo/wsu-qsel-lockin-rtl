// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// cic_decim vs model: ADC codes every clock (cic_in.txt) -> cic_out.txt.

`timescale 1ns / 1ps

module tb_cic;
  import lockin_pkg::*;
  `include "vec_io.svh"

  logic clk = 0, rst_n = 0;
  always #4 clk = ~clk;

  logic                        in_valid = 0;
  logic signed [ADC_BITS-1:0]  in_data  = '0;
  logic                        out_valid;
  logic signed [DATA_BITS-1:0] out_data;

  cic_decim dut (.*);

  int fexp;
  int n_out = 0;
  string line;

  always @(posedge clk) if (out_valid) begin
    longint e;
    if (!vec_next(fexp, line)) check("extra output", 1, 0, n_out);
    else begin
      void'($sscanf(line, "%d", e));
      check("cic", out_data, e, n_out);
    end
    n_out++;
  end

  initial begin
    int fin;
    longint v;
    fin  = vec_open("cic_in.txt");
    fexp = vec_open("cic_out.txt");
    repeat (4) @(posedge clk);
    rst_n <= 1;
    while (vec_next(fin, line)) begin
      void'($sscanf(line, "%d", v));
      @(posedge clk);
      in_valid <= 1;
      in_data  <= v;
    end
    @(posedge clk) in_valid <= 0;
    repeat (20) @(posedge clk);
    if (vec_next(fexp, line)) check("missing output", 0, 1, n_out);
    report("cic_decim");
    $finish;
  end
endmodule
