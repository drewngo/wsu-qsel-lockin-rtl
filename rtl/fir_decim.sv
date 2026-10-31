// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// CIC-compensating FIR, decimate by D. Model: lockin_fixed.fir_decimate.
//
// y[n] = sum_k FIR_COEF[k] * x[n-k] for n = D-1, 2D-1, ...; out = sat(round(y >>> CW-1)).
// One multiplier, TAPS cycles per output. The sample buffer is a shift register
// (taps[0] = newest). To compute, it rotates once around (TAPS steps) so each
// tap passes taps[0], which is the only one the multiplier reads.
// Inputs must be at least TAPS + 4 clocks apart (5000 in the real design).

module fir_decim
  import lockin_pkg::*;
#(
  parameter int W    = DATA_BITS,
  parameter int TAPS = FIR_TAPS,
  parameter int D    = FIR_R,
  parameter int CW   = FIR_COEF_BITS
) (
  input  logic                clk,
  input  logic                rst_n,
  input  logic                in_valid,
  input  logic signed [W-1:0] in_data,
  output logic                out_valid,
  output logic signed [W-1:0] out_data
);

  localparam int PW = W + CW;                    // product
  localparam int AW = PW + $clog2(TAPS);         // accumulator
  localparam logic signed [AW-1:0] RND    = AW'(1) <<< (CW - 2);
  localparam logic signed [AW-1:0] OUT_HI = AW'((1 << (W - 1)) - 1);
  localparam logic signed [AW-1:0] OUT_LO = -(AW'(1) <<< (W - 1));

  logic signed [W-1:0]          taps [TAPS];
  logic [$clog2(D)-1:0]         phase;
  (* max_fanout = 64 *)        // busy steers every buffer register; replicate to keep routing short
  logic                         busy;
  logic [$clog2(TAPS)-1:0]      k;

  // ---------------- sample buffer and MAC sequencing
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < TAPS; i++) taps[i] <= '0;
      phase <= '0;
      busy  <= 1'b0;
      k     <= '0;
    end else if (busy) begin
      for (int i = 0; i < TAPS - 1; i++) taps[i] <= taps[i+1];
      taps[TAPS-1] <= taps[0];
      k <= k + 1'b1;
      if (k == TAPS - 1) busy <= 1'b0;
    end else if (in_valid) begin
      taps[0] <= in_data;
      for (int i = 1; i < TAPS; i++) taps[i] <= taps[i-1];
      if (phase == D - 1) begin
        phase <= '0;
        busy  <= 1'b1;
        k     <= '0;
      end else begin
        phase <= phase + 1'b1;
      end
    end
  end

  // synthesis translate_off
  always @(posedge clk) if (rst_n && busy && in_valid)
    $error("fir_decim: input arrived while busy; inputs must be >= TAPS+4 clocks apart");
  // synthesis translate_on

  // ---------------- multiply (registered, maps to one DSP48)
  logic signed [PW-1:0] prod;
  logic                 prod_v, prod_first, prod_last;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      prod       <= '0;
      prod_v     <= 1'b0;
      prod_first <= 1'b0;
      prod_last  <= 1'b0;
    end else begin
      prod       <= FIR_COEF[k] * taps[0];
      prod_v     <= busy;
      prod_first <= busy && (k == 0);
      prod_last  <= busy && (k == TAPS - 1);
    end
  end

  // ---------------- accumulate, round, saturate
  logic signed [AW-1:0] acc;
  logic                 done;
  logic signed [AW-1:0] rounded;
  assign rounded = (acc + RND) >>> (CW - 1);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      acc       <= '0;
      done      <= 1'b0;
      out_valid <= 1'b0;
      out_data  <= '0;
    end else begin
      if (prod_v) acc <= (prod_first ? AW'(0) : acc) + AW'(prod);
      done      <= prod_v && prod_last;
      out_valid <= done;
      if (done)
        out_data <= (rounded > OUT_HI) ? OUT_HI[W-1:0] :
                    (rounded < OUT_LO) ? OUT_LO[W-1:0] : rounded[W-1:0];
    end
  end

endmodule
