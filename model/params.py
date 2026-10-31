# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
"""Rates, bit widths, and registers shared by every model and the RTL.

LockinConfig holds synthesis-time parameters (become SystemVerilog
parameters/localparams). Regs holds run-time registers the ARM writes over
AXI-Lite. All integer formats are two's complement.

Signal chain (one ADC channel):

  ADC 14b @125 MS/s
   -> CIC (order 3, R=1250)      -> 18b @100 kS/s
   -> FIR comp + decimate by 4   -> 18b @25 kS/s      ("x_d", decimated rate)
   -> DC blocker (1-pole HP)     -> 19b
   -> mixers vs NCO 1f/2f LUT    -> 24b  I1, Q1, X2, Y2
   -> 3-stage 1-pole IIR LPF     -> 24b
   -> every PI_DECIM samples (loop rate 1 kHz):
        lock detect, normalize (I1/X2), kappa scale, PI -> synth command
   -> CORDIC on (I1, Q1) for magnitude/phase status
"""

import math
from dataclasses import dataclass, replace

F_MOD = 300.0  # coil modulation frequency, Hz (design value)
OUT_SEL = ("I1", "Q1", "X2", "Y2", "dc", "xd")  # DAC2 source select codes


@dataclass(frozen=True)
class LockinConfig:
    # --- Rates ---
    fs_adc: float = 125e6       # ADC / fabric clock, Hz
    f_mod: float = F_MOD        # modulation frequency, Hz
    cic_order: int = 3
    cic_r: int = 1250           # CIC decimation
    fir_r: int = 4              # FIR decimation
    pi_decim: int = 25          # decimated samples per loop update
    sim_scale: int = 1          # simulation-only time scale; must be 1 for synthesis

    # --- Widths ---
    adc_bits: int = 14
    data_bits: int = 18         # CIC out, FIR out, x_d
    fir_taps: int = 63
    fir_coef_bits: int = 18     # Q1.17, DC gain = 2^17
    nco_bits: int = 32          # phase accumulator
    lut_addr_bits: int = 10     # full-wave sine LUT, 1024 entries
    lut_bits: int = 16          # LUT amplitude 2^15 - 1
    mix_shift: int = 15         # mixer product >> mix_shift
    mix_bits: int = 24          # mixer output (saturated)
    dc_k: int = 10              # DC blocker pole: alpha = 2^-dc_k
    lpf_k: int = 10             # LPF pole: alpha = 2^-lpf_k (~3.9 Hz at 25 kS/s)
    lpf_stages: int = 3
    cordic_iters: int = 16
    cordic_guard: int = 2       # extra LSBs inside the CORDIC
    phase_bits: int = 16        # CORDIC phase output, full turn = 2^phase_bits
    norm_shift: int = 16        # ratio = (I1 << norm_shift) / X2
    ratio_bits: int = 32
    kappa_bits: int = 24        # unsigned
    kappa_shift: int = 16       # err = (ratio * kappa) >> kappa_shift
    err_bits: int = 32
    gain_bits: int = 24         # kp, ki unsigned
    kp_shift: int = 16
    ki_shift: int = 24
    integ_bits: int = 56
    cmd_bits: int = 32          # synthesizer frequency command (signed offset)
    dac_bits: int = 14          # Red Pitaya DAC, two's complement
    coil_amp_bits: int = 16     # coil amplitude register, unsigned
    out_gain_bits: int = 16     # DAC2 gain register, unsigned

    # --- Plant (outside the FPGA) ---
    freq_lsb: float = 2.0 ** -16  # synthesizer command LSB, in linewidths
    synth_delay: int = 1          # loop updates before a command reaches the sensor

    # --- Derived ---
    @property
    def cic_growth(self):
        return math.ceil(self.cic_order * math.log2(self.cic_r) - 1e-9)

    @property
    def cic_width(self):
        return self.adc_bits + self.cic_growth

    @property
    def cic_shift(self):
        return self.cic_width - self.data_bits

    @property
    def cic_gain(self):
        return self.cic_r ** self.cic_order / 2 ** self.cic_shift

    @property
    def r_total(self):
        return self.cic_r * self.fir_r

    @property
    def fs_cic(self):
        return self.fs_adc / self.cic_r

    @property
    def fs_dec(self):
        return self.fs_adc / self.r_total

    @property
    def fs_loop(self):
        return self.fs_dec / self.pi_decim

    @property
    def nco_inc(self):
        """Phase increment per fabric clock."""
        return round(self.f_mod / self.fs_adc * 2 ** self.nco_bits)

    @property
    def f_mod_actual(self):
        """Frequency the NCO really makes (also drives the coil DAC)."""
        return self.nco_inc * self.fs_adc / 2 ** self.nco_bits

    @property
    def nco_step(self):
        """Phase advance per decimated sample (NCO is sampled on the decimation strobe)."""
        return (self.nco_inc * self.r_total) % 2 ** self.nco_bits

    def scaled(self, s):
        """Simulation-only: cut decimation and raise f_mod by s, keeping samples per period."""
        if self.cic_r % s:
            raise ValueError(f"cic_r={self.cic_r} not divisible by {s}")
        return replace(self, cic_r=self.cic_r // s, f_mod=self.f_mod * s,
                       sim_scale=self.sim_scale * s)


@dataclass
class Regs:
    """Run-time registers (ARM <-> FPGA over AXI-Lite)."""
    phase_off1: int = 0              # 1f reference phase, nco_bits turns
    phase_off2: int = 3 << 30        # 2f reference phase; ARM sets 2*off1 - quarter turn
    norm_en: bool = True             # 2f slope normalization on/off
    kappa_norm: int = 1 << 16        # err scale with normalization on
    kappa_raw: int = 1 << 16         # err scale with normalization off
    kp: int = round(0.10 * 2 ** 16)
    ki: int = round(0.002 * 2 ** 24)
    out_min: int = -(16 << 16)       # command limits (+/-16 linewidths)
    out_max: int = 16 << 16
    x2_min: int = 0                  # lost-lock threshold on X2
    lock_hold: int = 50              # loop updates X2 must stay low to flag lost lock
    loop_en: bool = False            # False: PI holds, command = preload
    coil_amp: int = 0                # DAC1 coil sine amplitude, full scale = 2^16 - 1
    out_sel: int = 0                 # DAC2 source, index into OUT_SEL
    out_gain: int = 1                # DAC2 = sat(((src * gain) >> shift) + offset)
    out_shift: int = 0
    out_offset: int = 0
