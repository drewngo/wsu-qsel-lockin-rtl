# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
"""RTL testbenches in Vivado xsim, bit-exact against the fixed-point model.

Skipped when Vivado is not installed.
"""

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tb"))
import run_sim  # noqa: E402

BIN = run_sim.vivado_bin()
pytestmark = pytest.mark.skipif(BIN is None, reason="Vivado not found")


@pytest.fixture(scope="module", autouse=True)
def vectors():
    subprocess.run([sys.executable, str(ROOT / "model" / "gen_vectors.py")], check=True,
                   cwd=ROOT / "model", capture_output=True)


@pytest.mark.parametrize("name", list(run_sim.TESTS))
def test_rtl(name):
    ok, _, lines = run_sim.run_test(BIN, name)
    assert ok, "\n".join(lines)
