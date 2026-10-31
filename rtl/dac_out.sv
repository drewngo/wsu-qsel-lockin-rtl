// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// DAC2 output stage: pick a lock-in signal and scale it to the DAC.
// Model: lockin_fixed.dac_out.
//
//   dac = sat(round((src[sel] * gain) >>> shift) + offset)   (no rounding when shift = 0)
//
// sel codes are lockin_pkg::SEL_*. The DAC holds the value between lock-in
// updates. Output is two's complement; the board wrapper converts to whatever
// format the Red Pitaya DAC interface expects. Latency 6 clocks.

module dac_out
  import lockin_pkg::*;
#(
  parameter int MW = MIX_BITS,
  parameter int XW = DATA_BITS
) (
  input  logic                         clk,
  input  logic                         rst_n,
  // Registers
  input  logic [2:0]                   sel,
  input  logic [OUT_GAIN_BITS-1:0]     gain,
  input  logic [4:0]                   shift,
  input  logic signed [DAC_BITS-1:0]   offset,
  // Sources
  input  logic signed [MW-1:0]         i1,
  input  logic signed [MW-1:0]         q1,
  input  logic signed [MW-1:0]         x2,
  input  logic signed [MW-1:0]         y2,
  input  logic signed [XW-1:0]         dc,
  input  logic signed [XW-1:0]         xd,
  // DAC
  output logic signed [DAC_BITS-1:0]   dac
);

  localparam int PW = MW + OUT_GAIN_BITS + 1;
  localparam logic signed [PW-1:0] D_HI = (PW'(1) <<< (DAC_BITS - 1)) - PW'(1);
  localparam logic signed [PW-1:0] D_LO = -(PW'(1) <<< (DAC_BITS - 1));

  // Pipeline, one operation per clock:
  //   0 select   1 multiply   2 + rounding   3 >>> shift   4 + offset   5 saturate
  logic signed [MW-1:0]          src, src0;
  logic [OUT_GAIN_BITS-1:0]      gain0;
  logic signed [PW-1:0]          prod1, sum2, scaled3, y4;
  logic signed [PW-1:0]          rnd0, rnd1;
  logic [4:0]                    sh0, sh1, sh2;
  logic signed [DAC_BITS-1:0]    off0, off1, off2, off3;

  always_comb begin
    case (sel)
      3'(SEL_I1): src = i1;
      3'(SEL_Q1): src = q1;
      3'(SEL_X2): src = x2;
      3'(SEL_Y2): src = y2;
      3'(SEL_DC): src = MW'(dc);
      3'(SEL_XD): src = MW'(xd);
      default:    src = '0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      src0 <= '0; gain0 <= '0; sh0 <= '0; off0 <= '0; rnd0 <= '0;
      prod1 <= '0; sh1 <= '0; off1 <= '0; rnd1 <= '0;
      sum2 <= '0; sh2 <= '0; off2 <= '0;
      scaled3 <= '0; off3 <= '0;
      y4 <= '0;
      dac <= '0;
    end else begin
      src0    <= src;
      gain0   <= gain;
      sh0     <= shift;
      off0    <= offset;
      rnd0    <= (shift == 0) ? '0 : (PW'(1) <<< (shift - 1));

      prod1   <= src0 * $signed({1'b0, gain0});
      sh1     <= sh0;
      off1    <= off0;
      rnd1    <= rnd0;

      sum2    <= prod1 + rnd1;
      sh2     <= sh1;
      off2    <= off1;

      scaled3 <= sum2 >>> sh2;
      off3    <= off2;

      y4      <= scaled3 + PW'(off3);

      dac     <= (y4 > D_HI) ? D_HI[DAC_BITS-1:0] : (y4 < D_LO) ? D_LO[DAC_BITS-1:0] : y4[DAC_BITS-1:0];
    end
  end

endmodule
