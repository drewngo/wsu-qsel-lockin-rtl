# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
"""Integer primitives that map one-to-one onto RTL operators.

Each works on Python ints or int64 NumPy arrays (widths up to 63 bits).
"""

import math

import numpy as np


def wrap(x, bits):
    """Two's complement wrap to `bits` (what a plain RTL register does)."""
    half = 1 << (bits - 1)
    return ((x + half) & ((1 << bits) - 1)) - half


def sat(x, bits):
    """Saturate to a signed `bits`-wide range."""
    hi = (1 << (bits - 1)) - 1
    lo = -(1 << (bits - 1))
    if isinstance(x, np.ndarray):
        return np.clip(x, lo, hi)
    return hi if x > hi else lo if x < lo else x


def rshift_round(x, s):
    """Arithmetic right shift with round-half-up: (x + 2^(s-1)) >>> s."""
    if s <= 0:
        return x << -s if not isinstance(x, np.ndarray) else x * (1 << -s)
    return (x + (1 << (s - 1))) >> s


def sdiv_trunc(a, b):
    """Signed division truncating toward zero (typical RTL divider)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def sine_lut(addr_bits, amp_bits):
    """Full-wave sine LUT, amplitude 2^(amp_bits-1) - 1."""
    n = 1 << addr_bits
    amp = (1 << (amp_bits - 1)) - 1
    return [int(round(amp * math.sin(2 * math.pi * i / n))) for i in range(n)]


def cordic_atan_table(iters, phase_bits):
    return [int(round(math.atan(2.0 ** -i) / (2 * math.pi) * 2 ** phase_bits))
            for i in range(iters)]


def cordic_gain(iters):
    return math.prod(math.sqrt(1 + 2.0 ** (-2 * i)) for i in range(iters))


def cordic_vector(x, y, iters, phase_bits, guard=2):
    """Vectoring CORDIC. Returns (magnitude, phase).

    magnitude: gain-compensated, same units as x/y
    phase    : signed, full turn = 2^phase_bits
    guard    : extra LSBs carried on x, y, and the angle accumulator
    """
    table = cordic_atan_table(iters, phase_bits + guard)
    kinv = int(round(2 ** 16 / cordic_gain(iters)))
    x, y, z = x << guard, y << guard, 0
    if x < 0:  # rotate by half a turn into the right half plane
        x, y, z = -x, -y, 1 << (phase_bits + guard - 1)
    for i in range(iters):
        if y > 0:
            x, y, z = x + (y >> i), y - (x >> i), z + table[i]
        else:
            x, y, z = x - (y >> i), y + (x >> i), z - table[i]
    return rshift_round(x * kinv, 16 + guard), wrap(rshift_round(z, guard), phase_bits)
