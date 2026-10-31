# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
"""Bit-accurate fixed-point lock-in. The RTL must match this sample for sample.

Blocks map to rtl/: cic_decimate -> cic_decim.sv, fir_decimate -> fir_decim.sv,
LockinFixed.process -> lockin_core.sv (DC blocker, NCO, mixers, LPF),
coil_dac -> coil_nco.sv, dac_out -> dac_out.sv. Not in RTL yet:
LockinFixed.update_loop (lock detect, normalizer, PI) and cordic_vector.
See params.py for the chain and widths.
"""

from functools import lru_cache

import numpy as np

from fixed_point import cordic_vector, rshift_round, sat, sdiv_trunc, sine_lut, wrap
from params import LockinConfig, Regs


# ---------------------------------------------------------------- decimation

@lru_cache(maxsize=None)
def fir_coeffs(taps, r, cic_order, coef_bits):
    """CIC-compensating lowpass for decimate-by-r, quantized to Q1.(coef_bits-1).

    Frequencies normalized to the CIC output Nyquist. Passband to 0.6 of the
    output Nyquist with inverse-sinc droop correction, stopband from the
    output Nyquist up.
    """
    from scipy.signal import firwin2

    f_pass = np.linspace(0.0, 0.6 / r, 32)
    droop = np.sinc(f_pass / 2) ** cic_order      # CIC response, large-R limit
    freqs = np.concatenate([f_pass, [1.0 / r, 1.0]])
    gains = np.concatenate([1.0 / droop, [0.0, 0.0]])
    h = firwin2(taps, freqs, gains, window=("kaiser", 6.0))
    q = np.round(h / h.sum() * 2 ** (coef_bits - 1)).astype(np.int64)
    return tuple(int(c) for c in q)


def fir_dc_gain(cfg):
    return sum(fir_coeffs(cfg.fir_taps, cfg.fir_r, cfg.cic_order, cfg.fir_coef_bits)) \
        / 2 ** (cfg.fir_coef_bits - 1)


def chain_gain(cfg):
    """DC gain from ADC codes to x_d."""
    return cfg.cic_gain * fir_dc_gain(cfg)


def cic_decimate(codes, cfg, prune=True):
    """CIC decimator on one burst (state starts at zero).

    Integrators wrap at cic_width (modular arithmetic is exact for CIC).
    prune=False returns the unshifted register value (for the float reference).
    """
    w = cfg.cic_width
    x = np.asarray(codes, dtype=np.int64)
    for _ in range(cfg.cic_order):
        x = wrap(np.cumsum(x), w)              # int64 cumsum wraps mod 2^64, consistent
    x = x[cfg.cic_r - 1::cfg.cic_r]
    for _ in range(cfg.cic_order):
        x = wrap(np.diff(x, prepend=0), w)
    if not prune:
        return x
    return sat(rshift_round(x, cfg.cic_shift), cfg.data_bits)


def fir_decimate(x, cfg):
    """Direct-form FIR, keep every fir_r-th output (phase fir_r-1)."""
    h = np.array(fir_coeffs(cfg.fir_taps, cfg.fir_r, cfg.cic_order, cfg.fir_coef_bits),
                 dtype=np.int64)
    y = np.convolve(np.asarray(x, dtype=np.int64), h)[:len(x)]
    y = y[cfg.fir_r - 1::cfg.fir_r]
    return sat(rshift_round(y, cfg.fir_coef_bits - 1), cfg.data_bits)


def decimate_chain(codes, cfg):
    """ADC codes at fs_adc -> x_d at fs_dec."""
    return fir_decimate(cic_decimate(codes, cfg), cfg)


def codes_to_xd(codes, cfg):
    """Shortcut for post-decimation sims: ADC codes sampled at fs_dec -> x_d units."""
    g = chain_gain(cfg)
    return sat(np.round(np.asarray(codes, dtype=float) * g).astype(np.int64), cfg.data_bits)


# ---------------------------------------------------------------- DAC outputs

def coil_dac(n, cfg, amp):
    """DAC1 coil drive at fabric clock n (vectorized): full-rate NCO, same LUT.

    acc = n * nco_inc; value = sat(round(lut[addr] * amp >> (amp_bits + lut_bits - dac_bits))).
    """
    lut = np.array(sine_lut(cfg.lut_addr_bits, cfg.lut_bits), dtype=np.int64)
    ash = cfg.nco_bits - cfg.lut_addr_bits
    acc = (np.asarray(n, dtype=np.int64) * cfg.nco_inc) % (1 << cfg.nco_bits)
    addr = ((acc + (1 << (ash - 1))) % (1 << cfg.nco_bits)) >> ash
    shift = cfg.coil_amp_bits + cfg.lut_bits - cfg.dac_bits
    return sat(rshift_round(lut[addr] * int(amp), shift), cfg.dac_bits)


def dac_out(val, gain, shift, offset, cfg):
    """DAC2: sat(((val * gain) >> shift, rounded) + offset) to dac_bits."""
    y = val * gain
    if shift:
        y = rshift_round(y, shift)
    return sat(y + offset, cfg.dac_bits)


# ---------------------------------------------------------------- PI

class PiFixed:
    """PI with output limits, integrator clamp, and conditional-integration anti-windup.

    out = sat_lim(((e*kp) >> kp_shift) + (integ >> ki_shift))
    integ += e*ki, unless the output is pinned at a limit and e pushes further.
    """

    def __init__(self, cfg: LockinConfig, regs: Regs):
        self.cfg, self.regs = cfg, regs
        self.integ = 0
        self.out = 0

    def preload(self, cmd):
        self.integ = cmd << self.cfg.ki_shift
        self.out = cmd

    def update(self, e):
        c, r = self.cfg, self.regs
        p = rshift_round(e * r.kp, c.kp_shift)
        inc = e * r.ki
        integ = sat(self.integ + inc, c.integ_bits)
        lo_i, hi_i = r.out_min << c.ki_shift, r.out_max << c.ki_shift
        integ = min(max(integ, lo_i), hi_i)
        u = p + rshift_round(integ, c.ki_shift)
        if u > r.out_max:
            u = r.out_max
            if inc > 0:
                integ = self.integ
        elif u < r.out_min:
            u = r.out_min
            if inc < 0:
                integ = self.integ
        self.integ = integ
        self.out = u
        return u


# ---------------------------------------------------------------- core

class LockinFixed:
    """Everything after decimation: DC blocker, NCO, mixers, LPFs, loop."""

    def __init__(self, cfg: LockinConfig = None, regs: Regs = None):
        self.cfg = cfg or LockinConfig()
        self.regs = regs or Regs()
        c = self.cfg
        self.lut = sine_lut(c.lut_addr_bits, c.lut_bits)
        self.pi = PiFixed(c, self.regs)
        self.acc = 0                                     # NCO phase at next sample
        self.dc_ext = 0
        self.lpf = [[0] * c.lpf_stages for _ in range(4)]  # I1, Q1, X2, Y2
        self.I1 = self.Q1 = self.X2 = self.Y2 = 0
        self.dc = 0
        self.xd = 0                                      # last input sample
        self.ratio_norm = self.ratio_raw = 0
        self.err = 0
        self.low_cnt = 0
        self.lost = False                                # sticky until ARM clears

    @property
    def cmd(self):
        return self.pi.out

    def process(self, xd):
        """Run decimated samples x_d through DC blocker, mixers, and LPFs."""
        c, r = self.cfg, self.regs
        lut = self.lut
        amask = (1 << c.lut_addr_bits) - 1
        quarter = 1 << (c.lut_addr_bits - 2)
        ash = c.nco_bits - c.lut_addr_bits
        rnd = 1 << (ash - 1)                             # round LUT address, not truncate
        pmask = (1 << c.nco_bits) - 1
        step, off1, off2 = c.nco_step, r.phase_off1, r.phase_off2
        dck, dch = c.dc_k, 1 << (c.dc_k - 1)
        K, kh = c.lpf_k, 1 << (c.lpf_k - 1)
        msh, mh = c.mix_shift, 1 << (c.mix_shift - 1)
        mhi, mlo = (1 << (c.mix_bits - 1)) - 1, -(1 << (c.mix_bits - 1))
        nst = c.lpf_stages
        acc, dc_ext, lpf = self.acc, self.dc_ext, self.lpf

        for x in np.asarray(xd).tolist():
            # DC blocker: x_h = x - LPF(x)
            dc = (dc_ext + dch) >> dck
            dc_ext += x - dc
            xh = x - dc
            # NCO: 1f at acc + off1, 2f at 2*acc + off2; sin = in-phase, cos = quadrature
            a1 = ((acc + off1 + rnd) & pmask) >> ash
            a2 = ((2 * acc + off2 + rnd) & pmask) >> ash
            refs = (lut[a1], lut[(a1 + quarter) & amask], lut[a2], lut[(a2 + quarter) & amask])
            for ch in range(4):
                m = (xh * refs[ch] + mh) >> msh
                m = mhi if m > mhi else mlo if m < mlo else m
                s = lpf[ch]
                for k in range(nst):       # stage k sees stage k-1's updated output
                    s[k] += m - ((s[k] + kh) >> K)
                    m = (s[k] + kh) >> K
            acc = (acc + step) & pmask

        self.acc, self.dc_ext = acc, dc_ext
        self.dc = (dc_ext + dch) >> dck
        if len(xd):
            self.xd = int(xd[-1])
        self.I1, self.Q1, self.X2, self.Y2 = (
            (s[-1] + kh) >> K for s in lpf)

    def update_loop(self):
        """Loop-rate update: lock detect, error, PI. Returns the new command."""
        c, r = self.cfg, self.regs
        if self.X2 < r.x2_min:
            self.low_cnt += 1
        else:
            self.low_cnt = 0
        if self.low_cnt >= r.lock_hold:
            self.lost = True

        self.ratio_raw = self.I1
        if self.X2 > max(r.x2_min, 0):
            self.ratio_norm = sat(sdiv_trunc(self.I1 << c.norm_shift, self.X2), c.ratio_bits)
        else:
            self.ratio_norm = 0
        ratio, kappa = ((self.ratio_norm, r.kappa_norm) if r.norm_en
                        else (self.ratio_raw, r.kappa_raw))
        self.err = sat(rshift_round(ratio * kappa, c.kappa_shift), c.err_bits)

        if r.loop_en and not self.lost:
            self.pi.update(self.err)
        return self.pi.out

    def clear_lost(self):
        self.lost = False
        self.low_cnt = 0

    def cordic(self):
        """(magnitude, phase) of (I1, Q1)."""
        c = self.cfg
        return cordic_vector(self.I1, self.Q1, c.cordic_iters, c.phase_bits, c.cordic_guard)
