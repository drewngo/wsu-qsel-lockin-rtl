# Board bring-up: first light on the STEMlab 125-14

`rtl/board/rp_lockin_top.sv` runs the open-loop lock-in with fixed settings and
no processor. Loading it only replaces the FPGA contents until the next reboot
or until a Red Pitaya web app loads its own bitstream; nothing is written to the SD card.

## Build

```
vivado -mode batch -source vivado/build_bitstream.tcl
```

Writes `vivado/build/bitstream/rp_lockin.bit` and `rp_lockin.bit.bin`, and stops
before the bitstream if timing fails. To change a setting (frequency, coil
amplitude, which signal goes to OUT2, its gain), edit the parameters at the top
of `rp_lockin_top.sv` and rebuild (about 5 minutes).

| Parameter | Default | Meaning |
| --- | --- | --- |
| `NCO_INC_P` | `NCO_INC` (300.0023 Hz) | f_mod = NCO_INC_P x 125 MHz / 2^32; set by `F_MOD` in `model/params.py` |
| `COIL_AMP` | 13885 | OUT1 amplitude, 65535 = full scale; on this board 13885 measured as 0.5 Vpp (32768 gave 1.18 Vpp) |
| `OUT_SEL` | `SEL_I1` | OUT2 source: `SEL_I1`, `SEL_Q1`, `SEL_X2`, `SEL_Y2`, `SEL_DC`, `SEL_XD` |
| `OUT_GAIN`, `OUT_SHIFT` | 4, `IQ_FRAC_BITS` (12) | OUT2 = source x gain >> shift (DAC full scale = 8191). I/Q carry 12 fraction bits, so a shift of 12 means whole counts |
| `OUT_OFFSET` | 3470 | added after scaling, DAC codes (3470 is about +0.5 V on this board) |
| `PHASE_DEG` | 90 | reference phase rotation, degrees; set so the signal lands in I1 |

## Load

The board must run the stock Red Pitaya OS (tested on 1.07). `sw/load_lockin.sh`
stops the web server and Jupyter, detaches the kernel's XADC driver (it reads a
block that only exists in the stock FPGA image), then loads the bitstream.

1. Copy the bitstream and the script to the board (`169.254.x.x` on a direct
   cable, or `rp-xxxxxx.local`):
   ```
   scp vivado/build/bitstream/rp_lockin.bit sw/load_lockin.sh root@169.254.91.46:/tmp/
   ```
2. Load it:
   ```
   ssh root@169.254.91.46 sh /tmp/load_lockin.sh
   ```
   It prints `prog_done=1` on success. The SSH session stays up.
3. To get the stock image back, reboot or open any Red Pitaya web app.

Notes:
- The bitstream must include the Zynq processor block (`vivado/ps7_ip.tcl`).
  An earlier build without it took the board's Ethernet down on every load.
- Use the `.bit` file. Byte-swapping the `.bin` (`dd conv=swab`) produces a file
  the driver silently ignores.
- `/tmp` is cleared on reboot.

## Time constant

The output filter is 2 stages with a time constant of 2^`LPF_K` / 25 kHz each
(`LPF_K` = 15: 1.31 s, set in `model/params.py`). It sets the noise bandwidth
(about 0.1 Hz) and the response time: after any change in field, frequency or
input, wait about 5-10 s for OUT2 to settle. A field sweep needs a wait per
point of several time constants, or forward and reverse sweeps will shift
apart.

## What to look for

| Check | Expected | If not |
| --- | --- | --- |
| LED0 | blinks, about 1 Hz | bitstream did not load, or no ADC clock |
| LED1 | on (PLL locked) | ADC clock missing |
| OUT1 on a scope (high-Z) | 300 Hz sine, about 1 Vpp | if it appears on OUT2 instead, the DAC channels are swapped: tell me |
| OUT2, IN1 open | near 0 V, LEDs 4-7 off | |
| OUT2, OUT1 cabled to IN1 | steady DC level, up to about +/-0.9 V; LEDs 4-7 show its size | |
| Function generator, 300.05 Hz, 5 mV amplitude into IN1 | OUT2 swings slowly around 0.5 V, one cycle every 20 s (the 0.05 Hz beat) | Faster beats are filtered out: at 0.5 Hz the 1.31 s filter passes only 6% |

Notes:
- IN1 jumper on LV (+/-1 V). Stay inside that range.
- In loopback, how the signal splits between I1 and Q1 depends on cable and
  pipeline delay, so OUT2 = I1 can sit anywhere from 0 to full size. Rebuild with
  `OUT_SEL = SEL_Q1` to see the other half.
- The sign of IN1 and of the DAC outputs follows the red-pitaya-notes
  conventions; an overall sign flip is harmless (phase calibration absorbs it).

## Where things came from

Pin numbers, I/O standards, ADC/DAC data formats and the DAC clock phases are
taken from pavel-demin/red-pitaya-notes (`cfg/ports.xdc`, `cfg/clocks.xdc`,
`cores/axis_red_pitaya_adc.v`, `cores/axis_red_pitaya_dac.v`,
`projects/dac_test/block_design.tcl`). `tb/tb_rp_io.sv` checks the ADC and
DAC encodings against those formats with Xilinx's ODDR models.
