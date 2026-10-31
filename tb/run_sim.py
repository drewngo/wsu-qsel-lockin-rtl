# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
"""Run the RTL testbenches in Vivado xsim and report PASS/FAIL.

    python tb/run_sim.py              # all tests
    python tb/run_sim.py core top     # selected tests
    python tb/run_sim.py --regen      # regenerate rtl/lockin_pkg.sv and vectors first

Finds Vivado through $XILINX_VIVADO, then PATH, then the usual install folders.
Build products and logs go to tb/build/<test>/.
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TB = ROOT / "tb"
RTL = ROOT / "rtl"
VEC = ROOT / "vectors"
BUILD = TB / "build"

RTL_FILES = ["lockin_pkg.sv", "sine_rom.sv", "cic_decim.sv", "fir_decim.sv", "lockin_core.sv",
             "coil_nco.sv", "dac_out.sv", "lockin_top.sv"]
BOARD_FILES = ["board/rp_adc.sv", "board/rp_dac.sv", "board/rp_clocks.sv", "board/rp_lockin_top.sv"]
TESTS = {"cic": "tb_cic", "fir": "tb_fir", "core": "tb_core", "dac_out": "tb_dac_out",
         "coil": "tb_coil", "top": "tb_top", "rp_io": "tb_rp_io"}
UNISIM_TESTS = {"rp_io"}   # use Xilinx primitives: compile glbl, link unisims_ver


def vivado_bin():
    exe = ".bat" if os.name == "nt" else ""
    if os.environ.get("XILINX_VIVADO"):
        return Path(os.environ["XILINX_VIVADO"]) / "bin"
    found = shutil.which("xvlog" + exe)
    if found:
        return Path(found).parent
    pats = ["C:/AMDDesignTools/*/Vivado/bin", "C:/Xilinx/Vivado/*/bin", "C:/Xilinx/*/Vivado/bin",
            "/tools/Xilinx/Vivado/*/bin", "/opt/Xilinx/Vivado/*/bin", "/tools/Xilinx/*/Vivado/bin"]
    hits = sorted(h for p in pats for h in glob.glob(p) if Path(h, "xvlog" + exe).exists())
    return Path(hits[-1]) if hits else None


def tool(bin_dir, name):
    return str(bin_dir / (name + (".bat" if os.name == "nt" else "")))


def run_test(bin_dir, name):
    top = TESTS[name]
    work = BUILD / name
    work.mkdir(parents=True, exist_ok=True)
    srcs = [str(RTL / f) for f in RTL_FILES] + [str(TB / f"{top}.sv")]
    elab = [top]
    if name in UNISIM_TESTS:
        srcs = srcs[:-1] + [str(RTL / f) for f in BOARD_FILES] + srcs[-1:]
        elab = [top, "glbl", "-L", "unisims_ver"]
    steps = [[tool(bin_dir, "xvlog"), "-sv", "-i", str(TB), *srcs]]
    if name in UNISIM_TESTS:
        steps.append([tool(bin_dir, "xvlog"),
                      str(bin_dir.parent / "data" / "verilog" / "src" / "glbl.v")])
    steps += [
        [tool(bin_dir, "xelab"), *elab, "-s", f"{top}_snap", "-timescale", "1ns/1ps"],
        [tool(bin_dir, "xsim"), f"{top}_snap", "-R"],
    ]
    t0 = time.time()
    log = []
    for cmd in steps:
        p = subprocess.run(cmd, cwd=work, capture_output=True, text=True)
        log.append(p.stdout + p.stderr)
        if p.returncode != 0:
            break
    out = "\n".join(log)
    (work / "run.log").write_text(out)
    passed = "TEST PASSED" in out and "TEST FAILED" not in out
    lines = [l for l in out.splitlines()
             if l.startswith(("TEST ", "MISMATCH", "ERROR", "Error", "FATAL", "coil_nco latency",
                              "no latency", "  rtl="))]
    return passed, time.time() - t0, lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tests", nargs="*", choices=[*TESTS, []] and list(TESTS))
    ap.add_argument("--regen", action="store_true", help="run model/gen_vectors.py first")
    args = ap.parse_args()
    bin_dir = vivado_bin()
    if bin_dir is None:
        sys.exit("Vivado not found; set XILINX_VIVADO to the Vivado install folder")
    if args.regen or not (VEC / "top_out.txt").exists():
        subprocess.run([sys.executable, str(ROOT / "model" / "gen_vectors.py")], check=True,
                       cwd=ROOT / "model")
    results = []
    for name in args.tests or TESTS:
        ok, dt, lines = run_test(bin_dir, name)
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name:8s} {dt:6.1f}s")
        for l in lines:
            if not l.startswith("TEST PASSED"):
                print("      " + l)
        if not ok:
            print(f"      log: {BUILD / name / 'run.log'}")
    print(f"{sum(results)}/{len(results)} passed")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
