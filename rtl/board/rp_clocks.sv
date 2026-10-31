// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Clocks from the ADC's 125 MHz clock: 125 MHz fabric clock, plus the two
// 250 MHz DAC clocks (157.5 and 202.5 degrees, as in red-pitaya-notes).
// PLL: VCO = 125 MHz * 8 = 1000 MHz. Feedback goes through a BUFG so clk is
// phase-aligned with the ADC clock pin, which keeps ADC capture timing sane.
// rst_n deasserts 16 clocks after the PLL locks.

module rp_clocks (
  input  logic adc_clk_p,
  input  logic adc_clk_n,
  output logic clk,        // 125 MHz
  output logic ddr_clk,    // 250 MHz, 157.5 deg
  output logic wrt_clk,    // 250 MHz, 202.5 deg
  output logic locked,
  output logic rst_n
);

  logic clk_in, fb, fb_buf, c0, c1, c2;

  IBUFDS u_ibuf (.I(adc_clk_p), .IB(adc_clk_n), .O(clk_in));

  PLLE2_BASE #(
    .CLKIN1_PERIOD (8.0),
    .DIVCLK_DIVIDE (1),
    .CLKFBOUT_MULT (8),
    .CLKOUT0_DIVIDE(8),
    .CLKOUT1_DIVIDE(4), .CLKOUT1_PHASE(157.5),
    .CLKOUT2_DIVIDE(4), .CLKOUT2_PHASE(202.5)
  ) u_pll (
    .CLKIN1(clk_in), .CLKFBIN(fb_buf), .CLKFBOUT(fb),
    .CLKOUT0(c0), .CLKOUT1(c1), .CLKOUT2(c2), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
    .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0)
  );

  BUFG u_bfb (.I(fb), .O(fb_buf));
  BUFG u_b0  (.I(c0), .O(clk));
  BUFG u_b1  (.I(c1), .O(ddr_clk));
  BUFG u_b2  (.I(c2), .O(wrt_clk));

  logic [15:0] rst_sr = '0;
  always_ff @(posedge clk or negedge locked) begin
    if (!locked) rst_sr <= '0;
    else         rst_sr <= {rst_sr[14:0], 1'b1};
  end
  assign rst_n = rst_sr[15];

endmodule
