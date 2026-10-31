// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// CIC decimator. Model: lockin_fixed.cic_decimate.
//
// Integrators run at the input rate and wrap at W bits (modular arithmetic is
// exact for a CIC). Every stage carries its own valid bit, so pipeline latency
// never changes which samples are kept. Combs run at the output rate.
// Output = sat(round(comb >>> SHIFT)) to OUT_W bits.

module cic_decim
  import lockin_pkg::*;
#(
  parameter int IN_W  = ADC_BITS,
  parameter int OUT_W = DATA_BITS,
  parameter int N     = CIC_ORDER,
  parameter int R     = CIC_R,
  parameter int W     = CIC_WIDTH,
  parameter int SHIFT = CIC_SHIFT
) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    in_valid,
  input  logic signed [IN_W-1:0]  in_data,
  output logic                    out_valid,
  output logic signed [OUT_W-1:0] out_data
);

  localparam logic signed [W:0] RND    = (W+1)'(1) <<< (SHIFT - 1);
  localparam logic signed [W:0] OUT_HI = ((W+1)'(1) <<< (OUT_W - 1)) - (W+1)'(1);
  localparam logic signed [W:0] OUT_LO = -((W+1)'(1) <<< (OUT_W - 1));

  // ---------------- integrators (input rate)
  logic signed [W-1:0] integ [N];
  logic [N-1:0]        integ_v;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < N; i++) integ[i] <= '0;
      integ_v <= '0;
    end else begin
      integ_v[0] <= in_valid;
      if (in_valid) integ[0] <= integ[0] + W'(in_data);
      for (int i = 1; i < N; i++) begin
        integ_v[i] <= integ_v[i-1];
        if (integ_v[i-1]) integ[i] <= integ[i] + integ[i-1];
      end
    end
  end

  // ---------------- decimate: keep integrator samples R-1, 2R-1, ...
  logic [$clog2(R)-1:0] cnt;
  logic                 dec_v;
  logic signed [W-1:0]  dec;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cnt   <= '0;
      dec_v <= 1'b0;
      dec   <= '0;
    end else begin
      dec_v <= 1'b0;
      if (integ_v[N-1]) begin
        if (cnt == R - 1) begin
          cnt   <= '0;
          dec   <= integ[N-1];
          dec_v <= 1'b1;
        end else begin
          cnt <= cnt + 1'b1;
        end
      end
    end
  end

  // ---------------- combs (output rate), delay 1
  logic signed [W-1:0] comb [N];
  logic signed [W-1:0] prev [N];
  logic [N-1:0]        comb_v;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < N; i++) begin
        comb[i] <= '0;
        prev[i] <= '0;
      end
      comb_v <= '0;
    end else begin
      comb_v[0] <= dec_v;
      if (dec_v) begin
        comb[0] <= dec - prev[0];
        prev[0] <= dec;
      end
      for (int i = 1; i < N; i++) begin
        comb_v[i] <= comb_v[i-1];
        if (comb_v[i-1]) begin
          comb[i] <= comb[i-1] - prev[i];
          prev[i] <= comb[i-1];
        end
      end
    end
  end

  // ---------------- round, saturate
  logic signed [W:0] rounded;
  assign rounded = (W+1)'(comb[N-1]) + RND >>> SHIFT;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
      out_data  <= '0;
    end else begin
      out_valid <= comb_v[N-1];
      if (comb_v[N-1])
        out_data <= (rounded > OUT_HI) ? OUT_HI[OUT_W-1:0] :
                    (rounded < OUT_LO) ? OUT_LO[OUT_W-1:0] : rounded[OUT_W-1:0];
    end
  end

endmodule
