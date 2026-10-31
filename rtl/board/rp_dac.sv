// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Red Pitaya STEMlab 125-14 DAC driver (AD9767, interleaved mode).
//
// One 14-bit bus carries both channels: ch2 while clk is high, ch1 while it
// is low (dac_sel follows), so the DAC runs at 250 MS/s. Pin data is the
// two's complement value with bits [12:0] inverted. ddr_clk and wrt_clk are 250 MHz at 157.5
// and 202.5 degrees. Same scheme as pavel-demin/red-pitaya-notes
// axis_red_pitaya_dac. While rst is high the DAC is held in reset and the
// data is zero. Latency 1 clock to the ODDR inputs.

module rp_dac (
  input  logic               clk,       // 125 MHz
  input  logic               ddr_clk,   // 250 MHz, 157.5 deg
  input  logic               wrt_clk,   // 250 MHz, 202.5 deg
  input  logic               rst,
  input  logic signed [13:0] ch1,       // OUT1
  input  logic signed [13:0] ch2,       // OUT2
  output logic [13:0]        dac_dat,
  output logic               dac_clk,
  output logic               dac_rst,
  output logic               dac_sel,
  output logic               dac_wrt
);

  localparam logic [13:0] ZERO = {1'b0, 13'h1FFF};   // encoding of 0

  logic [13:0] a, b;
  logic [1:0]  rst_q;

  always_ff @(posedge clk) begin
    a     <= rst ? ZERO : {ch1[13], ~ch1[12:0]};
    b     <= rst ? ZERO : {ch2[13], ~ch2[12:0]};
    rst_q <= {rst_q[0], rst};
  end

  ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0)) u_rst (
    .Q(dac_rst), .D1(rst_q[1]), .D2(rst_q[1]), .C(clk), .CE(1'b1), .R(1'b0), .S(1'b0));

  ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0)) u_sel (
    .Q(dac_sel), .D1(1'b1), .D2(1'b0), .C(clk), .CE(1'b1), .R(1'b0), .S(1'b0));

  ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0)) u_wrt (
    .Q(dac_wrt), .D1(1'b1), .D2(1'b0), .C(wrt_clk), .CE(1'b1), .R(1'b0), .S(1'b0));

  ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0)) u_clk (
    .Q(dac_clk), .D1(1'b1), .D2(1'b0), .C(ddr_clk), .CE(1'b1), .R(1'b0), .S(1'b0));

  for (genvar j = 0; j < 14; j++) begin : g_dat
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0)) u_dat (
      .Q(dac_dat[j]), .D1(b[j]), .D2(a[j]), .C(clk), .CE(1'b1), .R(1'b0), .S(1'b0));
  end

endmodule
