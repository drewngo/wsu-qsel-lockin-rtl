// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Lock-in core at the decimated rate. Model: lockin_fixed.LockinFixed.process.
//
// Per input sample x (x_d, 18b):
//   DC blocker  dc = round(dc_ext >>> DC_K); dc_ext += x - dc; xh = x - dc
//   NCO         a1 = round(acc + off1), a2 = round(2*acc + off2) to LUT_ADDR_BITS
//               refs: ch0 sin(a1), ch1 cos(a1), ch2 sin(a2), ch3 cos(a2)
//               acc += nco_step
//   Mixer       m = sat(round(xh * ref >>> MIX_SHIFT)) to MIX_BITS
//   LPF         per stage: s += v - round(s >>> LPF_K); v = round(s >>> LPF_K)
//   Outputs     i1, q1 (1f) and x2, y2 (2f) = last stage of each channel
//
// One multiplier and one LUT port are shared across the four channels. Each
// LPF stage update is split over four clocks to meet 125 MHz, so a sample
// takes 66 clocks. Inputs must be at least 72 clocks apart (5000 in the real
// design). Outputs update together, one cycle before out_valid.

module lockin_core
  import lockin_pkg::*;
#(
  parameter int XW = DATA_BITS,
  parameter int MW = MIX_BITS
) (
  input  logic                  clk,
  input  logic                  rst_n,
  // Registers
  input  logic [NCO_BITS-1:0]   nco_step,     // phase advance per sample
  input  logic [NCO_BITS-1:0]   phase_off1,   // 1f reference phase
  input  logic [NCO_BITS-1:0]   phase_off2,   // 2f reference phase
  // Sample in
  input  logic                  in_valid,
  input  logic signed [XW-1:0]  in_data,
  // Results
  output logic                  out_valid,
  output logic signed [XW-1:0]  xd,           // last input
  output logic signed [XW-1:0]  dc,
  output logic signed [MW-1:0]  i1,
  output logic signed [MW-1:0]  q1,
  output logic signed [MW-1:0]  x2,
  output logic signed [MW-1:0]  y2
);

  localparam int AB  = LUT_ADDR_BITS;
  localparam int ASH = NCO_BITS - AB;
  localparam int HW  = XW + 2;                 // xh = x - dc, with margin
  localparam int DW  = XW + DC_K + 2;          // dc_ext
  localparam int PW  = HW + LUT_BITS;          // mixer product
  localparam int SW  = MW + LPF_K + 2;         // LPF stage state
  localparam int NCH = 4;
  localparam int NST = LPF_STAGES;

  localparam logic [NCO_BITS-1:0]  A_RND   = NCO_BITS'(1) << (ASH - 1);
  localparam logic [AB-1:0]        QUARTER = AB'(1) << (AB - 2);
  localparam logic signed [DW-1:0] DC_RND  = DW'(1) <<< (DC_K - 1);
  localparam logic signed [PW-1:0] M_RND   = PW'(1) <<< (MIX_SHIFT - 1);
  localparam logic signed [PW-1:0] M_HI    = PW'((1 << (MW - 1)) - 1);
  localparam logic signed [PW-1:0] M_LO    = -(PW'(1) <<< (MW - 1));
  localparam logic signed [SW-1:0] S_RND   = SW'(1) <<< (LPF_K - 1);

  typedef enum logic [2:0] {S_IDLE, S_RD, S_MUL, S_MIX, S_LPF, S_STORE, S_DONE} state_t;
  state_t state;

  logic [NCO_BITS-1:0]       acc;
  logic signed [DW-1:0]      dc_ext;
  logic signed [HW-1:0]      xh;
  logic [AB-1:0]             a1, a2;
  logic [1:0]                ch;
  logic [$clog2(NST)-1:0]    stg;
  logic signed [PW-1:0]      prod;
  logic signed [SW-1:0]      v;
  logic [1:0]                ph;               // LPF sub-step
  logic signed [SW-1:0]      s_q, r_q;
  logic signed [SW-1:0]      lpf [NCH][NST];
  logic signed [MW-1:0]      res [NCH];

  // ---------------- combinational helpers
  logic signed [DW-1:0] dc_now;
  assign dc_now = (dc_ext + DC_RND) >>> DC_K;

  logic [NCO_BITS-1:0] p1, p2;
  assign p1 = acc + phase_off1 + A_RND;
  assign p2 = (acc << 1) + phase_off2 + A_RND;

  logic [AB-1:0] rom_addr;
  logic signed [LUT_BITS-1:0] rom_q;
  always_comb begin
    case (ch)
      2'd0:    rom_addr = a1;
      2'd1:    rom_addr = a1 + QUARTER;
      2'd2:    rom_addr = a2;
      default: rom_addr = a2 + QUARTER;
    endcase
  end

  sine_rom u_rom (.clk(clk), .addr(rom_addr), .data(rom_q));

  logic signed [PW-1:0] m_rnd;
  assign m_rnd = (prod + M_RND) >>> MIX_SHIFT;


  // ---------------- sequencer
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state     <= S_IDLE;
      acc       <= '0;
      dc_ext    <= '0;
      xh        <= '0;
      a1        <= '0;
      a2        <= '0;
      ch        <= '0;
      stg       <= '0;
      prod      <= '0;
      v         <= '0;
      ph        <= '0;
      s_q       <= '0;
      r_q       <= '0;
      out_valid <= 1'b0;
      xd        <= '0;
      dc        <= '0;
      i1        <= '0;
      q1        <= '0;
      x2        <= '0;
      y2        <= '0;
      for (int c = 0; c < NCH; c++) begin
        res[c] <= '0;
        for (int s = 0; s < NST; s++) lpf[c][s] <= '0;
      end
    end else begin
      out_valid <= 1'b0;
      case (state)
        S_IDLE: if (in_valid) begin
          xd     <= in_data;
          xh     <= HW'(in_data) - HW'(dc_now);
          dc_ext <= dc_ext + DW'(in_data) - dc_now;
          a1     <= p1[NCO_BITS-1 -: AB];
          a2     <= p2[NCO_BITS-1 -: AB];
          acc    <= acc + nco_step;
          ch     <= '0;
          state  <= S_RD;
        end
        S_RD:  state <= S_MUL;                        // LUT read in flight
        S_MUL: begin
          prod  <= xh * rom_q;
          state <= S_MIX;
        end
        S_MIX: begin
          v     <= (m_rnd > M_HI) ? SW'(M_HI) : (m_rnd < M_LO) ? SW'(M_LO) : SW'(m_rnd);
          stg   <= '0;
          ph    <= '0;
          state <= S_LPF;
        end
        S_LPF: begin                                  // s += v - round(s >>> K); v = round(s >>> K)
          ph <= ph + 1'b1;
          case (ph)
            2'd0: s_q <= lpf[ch][stg];
            2'd1: r_q <= (s_q + S_RND) >>> LPF_K;
            2'd2: begin
              s_q          <= s_q + v - r_q;
              lpf[ch][stg] <= s_q + v - r_q;
            end
            default: begin
              v <= (s_q + S_RND) >>> LPF_K;
              if (stg == NST - 1) state <= S_STORE;
              else                stg   <= stg + 1'b1;
            end
          endcase
        end
        S_STORE: begin
          res[ch] <= v[MW-1:0];
          if (ch == NCH - 1) state <= S_DONE;
          else begin
            ch    <= ch + 1'b1;
            state <= S_RD;
          end
        end
        S_DONE: begin
          dc        <= dc_now[XW-1:0];
          i1        <= res[0];
          q1        <= res[1];
          x2        <= res[2];
          y2        <= res[3];
          out_valid <= 1'b1;
          state     <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end

  // synthesis translate_off
  always @(posedge clk) if (rst_n && in_valid && state != S_IDLE)
    $error("lockin_core: input arrived while busy; inputs must be >= 72 clocks apart");
  // synthesis translate_on

endmodule
