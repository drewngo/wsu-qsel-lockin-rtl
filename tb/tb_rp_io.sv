// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Board I/O formats, with Xilinx unisim models of the ODDRs:
//   rp_adc: random codes driven onto the pins in the ADC's encoding come out
//           as the same two's complement values.
//   rp_dac: random ch1/ch2 values come back out of the double-rate bus
//           (ch2 while clk is high with dac_sel = 1, ch1 while low).

`timescale 1ns / 1ps

module tb_rp_io;
  `include "vec_io.svh"

  localparam int N = 2000;

  logic clk = 0, ddr_clk = 0, wrt_clk = 0;
  always #4 clk = ~clk;
  initial begin
    #1.75 forever #2 ddr_clk = ~ddr_clk;      // 250 MHz, 157.5 deg of 125 MHz
  end
  initial begin
    #2.25 forever #2 wrt_clk = ~wrt_clk;      // 250 MHz, 202.5 deg
  end

  // ---------------- ADC
  logic [15:0]        pins = '0;
  logic signed [13:0] adc_data;
  rp_adc u_adc (.clk, .pins, .data(adc_data));

  // ---------------- DAC
  logic               rst = 1;
  logic signed [13:0] ch1 = '0, ch2 = '0;
  logic [13:0]        dac_dat;
  logic               dac_clk, dac_rst, dac_sel, dac_wrt;
  rp_dac u_dac (.clk, .ddr_clk, .wrt_clk, .rst, .ch1, .ch2,
                .dac_dat, .dac_clk, .dac_rst, .dac_sel, .dac_wrt);

  function automatic logic signed [13:0] dac_decode(logic [13:0] d);
    return {d[13], ~d[12:0]};
  endfunction

  logic signed [13:0] adc_sent [N];
  logic signed [13:0] ch1_sent [N], ch2_sent [N];

  initial begin
    repeat (10) @(posedge clk);
    rst <= 0;
    repeat (4) @(posedge clk);
    for (int i = 0; i < N; i++) begin
      logic signed [13:0] code;
      code        = $urandom;
      adc_sent[i] = code;
      ch1_sent[i] = $urandom;
      ch2_sent[i] = $urandom;
      @(posedge clk);
      pins <= {code[13], ~code[12:0], 2'($urandom)};     // ADC pin encoding, low bits unused
      ch1  <= ch1_sent[i];
      ch2  <= ch2_sent[i];
    end
  end

  // Checks: driven at edge k, ADC data valid after edge k+2; DAC ODDR inputs
  // load at k+1 and drive the pins from edge k+2.
  initial begin
    repeat (14) @(posedge clk);
    for (int i = 0; i < N; i++) begin
      @(posedge clk);                               // edge k
      fork
        automatic int k = i;                        // each thread keeps its own index
        begin
          repeat (2) @(posedge clk);
          #1 check("adc", adc_data, adc_sent[k], k);
        end
        begin
          repeat (2) @(posedge clk);
          #2 begin
            check("dac_sel high", dac_sel, 1, k);
            check("OUT2", dac_decode(dac_dat), ch2_sent[k], k);
          end
          @(negedge clk);
          #2 begin
            check("dac_sel low", dac_sel, 0, k);
            check("OUT1", dac_decode(dac_dat), ch1_sent[k], k);
          end
        end
      join_none
    end
    repeat (8) @(posedge clk);
    check("dac_rst released", dac_rst, 0, 0);
    report("rp_io");
    $finish;
  end

endmodule
