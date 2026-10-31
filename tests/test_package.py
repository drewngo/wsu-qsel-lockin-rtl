# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
"""rtl/lockin_pkg.sv must match model/params.py; rerun model/gen_vectors.py if this fails."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "model"))

import gen_vectors  # noqa: E402
from params import LockinConfig, Regs  # noqa: E402


def test_rtl_package_up_to_date(tmp_path):
    pkg = tmp_path / "lockin_pkg.sv"
    gen_vectors.write_pkg(pkg, LockinConfig(), Regs())
    assert pkg.read_text() == (ROOT / "rtl" / "lockin_pkg.sv").read_text()


def test_synthesis_build(tmp_path):
    """The committed package must not carry the simulation-only time scale."""
    assert "SIM_SCALE = 1;" in (ROOT / "rtl" / "lockin_pkg.sv").read_text()
