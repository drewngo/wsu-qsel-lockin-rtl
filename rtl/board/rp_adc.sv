// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Red Pitaya STEMlab 125-14 ADC capture, one channel.
//
// The ADC drives 16 pins; the sample is in [15:2] with bits [14:2] inverted
// (same mapping as pavel-demin/red-pitaya-notes axis_red_pitaya_adc).
// Pins are registered in the IOB, then converted to two's complement.
// Latency 2 clocks.

module rp_adc (
  input  logic               clk,
  input  logic [15:0]        pins,
  output logic signed [13:0] data
);

  (* IOB = "TRUE" *) logic [15:0] raw;

  always_ff @(posedge clk) begin
    raw  <= pins;
    data <= {raw[15], ~raw[14:2]};
  end

endmodule
