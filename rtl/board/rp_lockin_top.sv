// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// First-light board top for the Red Pitaya STEMlab 125-14. No processor:
// registers are fixed by the parameters below; change them and rebuild.
//
//   IN1  -> lock-in
//   OUT1 <- coil sine at f_mod (COIL_AMP / 65535 of full scale, +/-1 V)
//   OUT2 <- selected lock-in output (OUT_SEL, scaled by OUT_GAIN >> OUT_SHIFT)
//   LED0 heartbeat (~1 Hz)     LED1 PLL locked
//   LED2 I1 < 0                LED3 Q1 < 0
//   LED4..7 |I1| bar: >= 1k, 4k, 8k, 16k whole counts (about 17, 69, 137,
//           275 mV of in-phase f_mod amplitude at IN1, LV jumper)
//
// I1/Q1/X2/Y2 carry IQ_FRAC_BITS (12) fraction bits below the whole count, so
// OUT_SHIFT includes them: OUT_SHIFT = IQ_FRAC_BITS + n divides whole counts
// by 2^n. On this board OUT2 moves 1 V per about 6940 DAC codes.
//
// PHASE_DEG rotates the demodulation reference. Rotating by +90 moves what was
// in Q1 into I1 (new I1 = old Q1, new Q1 = -old I1). Set it so the signal sits
// in I1: LED3 flickering around zero, LED2 steady, OUT2 largest when off
// resonance. The 2f reference follows automatically (2 x phase - 90).
//
// Loopback test: cable OUT1 to IN1. With COIL_AMP = 32768 (about 0.5 V) the
// demodulated amplitude sqrt(I1^2 + Q1^2) is about 30k whole counts, so with
// OUT_GAIN = 1, OUT_SHIFT = IQ_FRAC_BITS + 2 OUT2 sits within +/-0.9 V; how it
// splits between I1 and Q1 depends on the cable and pipeline phase. The
// filter time constant is LPF_STAGES x 2^LPF_K / 25 kHz, so allow ~5-10 s to
// settle after any change.

module rp_lockin_top
  import lockin_pkg::*;
#(
  parameter logic [NCO_BITS-1:0] NCO_INC_P  = NCO_INC,         // f_mod from params.py (300.0023 Hz)
  parameter int                  COIL_AMP   = 13885,           // OUT1 amplitude; 13885 = 0.5 Vpp measured on this board (32768 gave 1.18 Vpp)
  parameter int                  OUT_SEL    = SEL_I1,
  parameter int                  OUT_GAIN   = 4,               // OUT2 = I1 x OUT_GAIN >> OUT_SHIFT
  parameter int                  OUT_SHIFT  = IQ_FRAC_BITS,    // IQ_FRAC_BITS = whole counts x OUT_GAIN
  parameter int                  OUT_OFFSET = 3470,
  parameter int                  PHASE_DEG  = 90               // reference phase, whole degrees
) (
  input  logic        adc_clk_p_i,
  input  logic        adc_clk_n_i,
  input  logic [15:0] adc_dat_a_i,     // IN1
  output logic        adc_csn_o,       // ADC clock duty-cycle stabilizer, keep high
  output logic [13:0] dac_dat_o,
  output logic        dac_clk_o,
  output logic        dac_rst_o,
  output logic        dac_sel_o,
  output logic        dac_wrt_o,
  output logic [7:0]  led_o,
  // Zynq processor fixed pins (DDR and MIO); no constraints needed
  inout  wire [53:0]  FIXED_IO_mio,
  inout  wire         FIXED_IO_ps_clk,
  inout  wire         FIXED_IO_ps_porb,
  inout  wire         FIXED_IO_ps_srstb,
  inout  wire         FIXED_IO_ddr_vrn,
  inout  wire         FIXED_IO_ddr_vrp,
  inout  wire [14:0]  DDR_addr,
  inout  wire [2:0]   DDR_ba,
  inout  wire         DDR_cas_n,
  inout  wire         DDR_ck_n,
  inout  wire         DDR_ck_p,
  inout  wire         DDR_cke,
  inout  wire         DDR_cs_n,
  inout  wire [3:0]   DDR_dm,
  inout  wire [31:0]  DDR_dq,
  inout  wire [3:0]   DDR_dqs_n,
  inout  wire [3:0]   DDR_dqs_p,
  inout  wire         DDR_odt,
  inout  wire         DDR_ras_n,
  inout  wire         DDR_reset_n,
  inout  wire         DDR_we_n
);

  // ---------------- Zynq processing system
  // Present only so the bitstream carries the board's processor-side setup
  // (as in Red Pitaya's own examples). No PS-PL interfaces are used; loading
  // a bitstream without it took the board's Ethernet down.
  rp_ps7 u_ps (
    .MIO(FIXED_IO_mio), .PS_CLK(FIXED_IO_ps_clk), .PS_PORB(FIXED_IO_ps_porb),
    .PS_SRSTB(FIXED_IO_ps_srstb), .DDR_VRN(FIXED_IO_ddr_vrn), .DDR_VRP(FIXED_IO_ddr_vrp),
    .DDR_Addr(DDR_addr), .DDR_BankAddr(DDR_ba), .DDR_CAS_n(DDR_cas_n), .DDR_Clk_n(DDR_ck_n),
    .DDR_Clk(DDR_ck_p), .DDR_CKE(DDR_cke), .DDR_CS_n(DDR_cs_n), .DDR_DM(DDR_dm), .DDR_DQ(DDR_dq),
    .DDR_DQS_n(DDR_dqs_n), .DDR_DQS(DDR_dqs_p), .DDR_ODT(DDR_odt), .DDR_RAS_n(DDR_ras_n),
    .DDR_DRSTB(DDR_reset_n), .DDR_WEB(DDR_we_n),
    .ENET0_MDIO_MDC(), .ENET0_MDIO_O(), .ENET0_MDIO_T(), .ENET0_MDIO_I(1'b0),
    .SPI0_SCLK_I(1'b0), .SPI0_SCLK_O(), .SPI0_SCLK_T(),
    .SPI0_MOSI_I(1'b0), .SPI0_MOSI_O(), .SPI0_MOSI_T(),
    .SPI0_MISO_I(1'b0), .SPI0_MISO_O(), .SPI0_MISO_T(),
    .SPI0_SS_I(1'b1), .SPI0_SS_O(), .SPI0_SS1_O(), .SPI0_SS2_O(), .SPI0_SS_T(),
    .TTC0_WAVE0_OUT(), .TTC0_WAVE1_OUT(), .TTC0_WAVE2_OUT(),
    .USB0_PORT_INDCTL(), .USB0_VBUS_PWRSELECT(), .USB0_VBUS_PWRFAULT(1'b0)
  );

  // Reference phases in NCO units (full turn = 2^NCO_BITS). The 2f reference
  // follows the 1f one: off2 = 2 * off1 - quarter turn, which puts the 2f
  // signal in X2 with positive sign when the 1f signal is in I1.
  localparam longint TURN = 64'sd1 <<< NCO_BITS;
  localparam longint DEG  = ((PHASE_DEG % 360) + 360) % 360;
  localparam logic [NCO_BITS-1:0] PHASE_OFF1 = NCO_BITS'((DEG * TURN + 180) / 360);
  localparam logic [NCO_BITS-1:0] PHASE_OFF2 = NCO_BITS'(2 * longint'(PHASE_OFF1) - TURN / 4 + TURN);

  logic clk, ddr_clk, wrt_clk, locked, rst_n;

  rp_clocks u_clk (
    .adc_clk_p(adc_clk_p_i), .adc_clk_n(adc_clk_n_i),
    .clk, .ddr_clk, .wrt_clk, .locked, .rst_n
  );

  assign adc_csn_o = 1'b1;

  logic signed [ADC_BITS-1:0] adc;
  rp_adc u_adc (.clk, .pins(adc_dat_a_i), .data(adc));

  logic                        lia_valid;
  logic signed [DATA_BITS-1:0] lia_xd, lia_dc;
  logic signed [MIX_BITS-1:0]  lia_i1, lia_q1, lia_x2, lia_y2;
  logic signed [DAC_BITS-1:0]  dac1, dac2;

  lockin_top u_lia (
    .clk, .rst_n, .adc,
    .nco_inc   (NCO_INC_P),
    .phase_off1(PHASE_OFF1),
    .phase_off2(PHASE_OFF2),
    .coil_amp  (COIL_AMP_BITS'(COIL_AMP)),
    .out_sel   (3'(OUT_SEL)),
    .out_gain  (OUT_GAIN_BITS'(OUT_GAIN)),
    .out_shift (5'(OUT_SHIFT)),
    .out_offset(DAC_BITS'(OUT_OFFSET)),
    .lia_valid, .lia_xd, .lia_dc, .lia_i1, .lia_q1, .lia_x2, .lia_y2,
    .dac1, .dac2
  );

  rp_dac u_dac (
    .clk, .ddr_clk, .wrt_clk, .rst(!rst_n),
    .ch1(dac1), .ch2(dac2),
    .dac_dat(dac_dat_o), .dac_clk(dac_clk_o), .dac_rst(dac_rst_o),
    .dac_sel(dac_sel_o), .dac_wrt(dac_wrt_o)
  );

  // ---------------- LEDs
  localparam logic [MIX_BITS-1:0] LED_T1 = MIX_BITS'(1024)  << IQ_FRAC_BITS;
  localparam logic [MIX_BITS-1:0] LED_T2 = MIX_BITS'(4096)  << IQ_FRAC_BITS;
  localparam logic [MIX_BITS-1:0] LED_T3 = MIX_BITS'(8192)  << IQ_FRAC_BITS;
  localparam logic [MIX_BITS-1:0] LED_T4 = MIX_BITS'(16384) << IQ_FRAC_BITS;
  logic [26:0]         beat;
  logic [MIX_BITS-1:0] i1_abs;
  always_ff @(posedge clk) begin
    beat   <= beat + 1'b1;
    i1_abs <= lia_i1[MIX_BITS-1] ? -lia_i1 : lia_i1;
    led_o  <= {i1_abs >= LED_T4, i1_abs >= LED_T3, i1_abs >= LED_T2, i1_abs >= LED_T1,
               lia_q1[MIX_BITS-1], lia_i1[MIX_BITS-1], locked, beat[26]};
  end

endmodule
