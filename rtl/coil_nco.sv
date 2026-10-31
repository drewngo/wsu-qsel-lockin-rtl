// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Coil drive for DAC1: full-rate NCO into the sine LUT, scaled by amp.
// Model: lockin_fixed.coil_dac.
//
//   acc += nco_inc every clock (acc = 0 out of reset)
//   dac = sat(round(SINE_LUT[round(acc)] * amp >>> AMP_BITS + LUT_BITS - DAC_BITS))
//
// The lock-in core's NCO advances nco_inc * R_TOTAL per decimated sample, so
// both run at exactly the same frequency with a fixed phase relation.
// Latency from acc to dac is 4 clocks.

module coil_nco
  import lockin_pkg::*;
(
  input  logic                        clk,
  input  logic                        rst_n,
  input  logic [NCO_BITS-1:0]         nco_inc,
  input  logic [COIL_AMP_BITS-1:0]    amp,
  output logic signed [DAC_BITS-1:0]  dac
);

  localparam int AB  = LUT_ADDR_BITS;
  localparam int ASH = NCO_BITS - AB;
  localparam int PW  = LUT_BITS + COIL_AMP_BITS + 1;
  localparam int SH  = COIL_AMP_BITS + LUT_BITS - DAC_BITS;
  localparam logic [NCO_BITS-1:0] A_RND = NCO_BITS'(1) << (ASH - 1);
  localparam logic signed [PW-1:0] P_RND = PW'(1) <<< (SH - 1);
  localparam logic signed [PW-1:0] D_HI  = (PW'(1) <<< (DAC_BITS - 1)) - PW'(1);
  localparam logic signed [PW-1:0] D_LO  = -(PW'(1) <<< (DAC_BITS - 1));

  logic [NCO_BITS-1:0]        acc, p;
  logic [AB-1:0]              addr;
  logic signed [LUT_BITS-1:0] s;
  logic signed [PW-1:0]       prod, r;

  assign p = acc + A_RND;
  assign r = (prod + P_RND) >>> SH;

  sine_rom u_rom (.clk(clk), .addr(addr), .data(s));

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      acc  <= '0;
      addr <= '0;
      prod <= '0;
      dac  <= '0;
    end else begin
      acc  <= acc + nco_inc;
      addr <= p[NCO_BITS-1 -: AB];
      prod <= s * $signed({1'b0, amp});
      dac  <= (r > D_HI) ? D_HI[DAC_BITS-1:0] : (r < D_LO) ? D_LO[DAC_BITS-1:0] : r[DAC_BITS-1:0];
    end
  end

endmodule
