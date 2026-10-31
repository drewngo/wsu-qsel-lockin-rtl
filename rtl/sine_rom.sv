// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Full-wave sine LUT, one-cycle registered read (infers block RAM).
// Contents come from lockin_pkg::SINE_LUT (model: fixed_point.sine_lut).

module sine_rom
  import lockin_pkg::*;
(
  input  logic                            clk,
  input  logic [LUT_ADDR_BITS-1:0]        addr,
  output logic signed [LUT_BITS-1:0]      data
);

  always_ff @(posedge clk) data <= SINE_LUT[addr];

endmodule
