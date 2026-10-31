# wsu-qsel-lockin-rtl

FPGA lock-in amplifier for a quantum magnetometer, running on a Red Pitaya
STEMlab 125-14 (Zynq-7010). SystemVerilog RTL, bit-exact against a Python
fixed-point model.

## Signal chain

```
IN1 (ADC, 14 b, 125 MS/s)
 -> CIC, order 3, /1250            18 b @ 100 kS/s
 -> 63-tap compensating FIR, /4    18 b @ 25 kS/s
 -> DC blocker
 -> 1f / 2f mixers (sine LUT, 1024 x 16 b)
 -> 3-stage one-pole low-pass (~3.9 Hz)
 -> I1, Q1 (1f) and X2, Y2 (2f)
 -> OUT2: selected output, scaled and offset

NCO at f_mod (300.0023 Hz) -> OUT1: coil modulation
```

## Layout

| Path | Contents |
| --- | --- |
| `rtl/` | Lock-in RTL: `cic_decim`, `fir_decim`, `lockin_core`, `sine_rom`, `coil_nco`, `dac_out`, `lockin_top` |
| `rtl/lockin_pkg.sv` | Generated constants, FIR taps, sine table. Do not edit; regenerate from `model/` |
| `rtl/board/` | STEMlab 125-14 top: Zynq PS7, PLL, ADC capture, DAC driver, LEDs |
| `tb/` | Self-checking testbenches (Vivado xsim) and `run_sim.py` |
| `model/` | Fixed-point model and vector generator; source of `lockin_pkg.sv` and all test vectors |
| `vivado/` | Pin constraints, PS7 preset, bitstream, out-of-context and GUI-project scripts |
| `sw/` | Board-side load script and boot service |
| `docs/board_bringup.md` | Loading the bitstream and what to check on the bench |

## Requirements

- Vivado 2025.2 with Zynq-7000 device support (simulation, synthesis)
- Python 3.12 with `numpy` and `scipy` (`pip install -r requirements.txt`)

## Use

```
python model/gen_vectors.py                               # regenerate rtl/lockin_pkg.sv and vectors/
python tb/run_sim.py                                      # all testbenches, PASS/FAIL per block
vivado -mode batch -source vivado/build_bitstream.tcl     # bitstream -> vivado/build/bitstream/
vivado -mode batch -source vivado/create_project.tcl      # GUI project -> vivado/project/
python -m pytest tests                                    # package-in-sync check + all testbenches
```

Design parameters (rates, widths, f_mod) live in `model/params.py`; after
changing them, rerun `gen_vectors.py`. Board settings (coil amplitude, OUT2
source, gain, offset, reference phase) are parameters at the top of
`rtl/board/rp_lockin_top.sv`.

## Verification

Each block is compared sample for sample against `model/lockin_fixed.py`:

| Testbench | Checks |
| --- | --- |
| `tb_cic` | CIC output, 256 samples |
| `tb_fir` | FIR output, 64 samples |
| `tb_core` | DC, I1, Q1, X2, Y2 after every sample, 12,500 samples |
| `tb_dac_out` | OUT2 scaling, 3,000 random cases |
| `tb_coil` | OUT1 NCO, 50,000 samples |
| `tb_top` | ADC to DAC end to end at 125 MHz, 576 checks |
| `tb_rp_io` | Board ADC/DAC pin encodings with Xilinx ODDR models, 10,001 checks |

## Implementation (xc7z010clg400-1, 125 MHz)

| Resource | Used | Available |
| --- | --- | --- |
| LUTs | 1,671 (9.5%) | 17,600 |
| Flip-flops | 2,555 (7.3%) | 35,200 |
| DSP48 | 4 (5%) | 80 |
| Block RAM | 0.5 (0.8%) | 60 |

Setup slack +0.87 ns, hold slack +0.02 ns.

## Acknowledgements

Developed at the Quantum Science and Engineering Lab, Wichita State University.

The Zynq preset (`vivado/red_pitaya.xml`) comes from Red Pitaya's
[RedPitaya-FPGA](https://github.com/RedPitaya/RedPitaya-FPGA) (BSD), and the
board interface follows Pavel Demin's
[red-pitaya-notes](https://github.com/pavel-demin/red-pitaya-notes) (MIT).
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Copyright (c) 2026 Andrew Ngo. Released under the BSD 3-Clause License; see
[LICENSE](LICENSE).
