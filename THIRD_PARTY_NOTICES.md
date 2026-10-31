# Third-party notices

## vivado/red_pitaya.xml

Zynq processing-system preset for the Red Pitaya, copied unmodified from
[RedPitaya/RedPitaya-FPGA](https://github.com/RedPitaya/RedPitaya-FPGA)
(`prj/Examples/Led_blink/cfg/red_pitaya.xml`). It is distributed under the
following license:

```
Copyright (c) 2014, Red Pitaya, d.o.o.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Red Pitaya nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Red Pitaya, d.o.o. BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Board interface references

The STEMlab 125-14 pin assignments, ADC/DAC data formats and DAC clock phases in
`vivado/rp_stemlab125_14.xdc`, `rtl/board/rp_adc.sv`, `rtl/board/rp_dac.sv` and
`rtl/board/rp_clocks.sv` follow
[pavel-demin/red-pitaya-notes](https://github.com/pavel-demin/red-pitaya-notes)
(MIT License). No files were copied from that project; the code here was
written independently to match the same hardware interface.
