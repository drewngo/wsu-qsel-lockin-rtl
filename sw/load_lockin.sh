#!/bin/sh
# Copyright (c) 2026 Andrew Ngo
# Author: Andrew Ngo, Quantum Science and Engineering Lab
#
# Load the lock-in bitstream on a Red Pitaya running the stock OS (1.x).
#
#   sh load_lockin.sh [bitstream.bit]     (default: rp_lockin.bit next to this script)
#
# The stock OS expects its own FPGA image: the web server and Jupyter use it,
# and the kernel's XADC driver reads a monitor block inside it. None of that
# exists in the lock-in design, so stop them first. A reboot without the boot
# service (or opening a Red Pitaya web app) restores the stock image.
#
# At boot this runs from lockin_fpga.service. To turn that off without a
# network connection, put the SD card in a PC and create an empty file named
# DISABLE next to this script (the folder is on the FAT partition).

DIR=$(dirname "$0")
BIT=${1:-$DIR/rp_lockin.bit}

if [ -e "$DIR/DISABLE" ]; then
  echo "lock-in load disabled ($DIR/DISABLE exists)"
  exit 0
fi
[ -f "$BIT" ] || { echo "no bitstream at $BIT"; exit 1; }

# At boot, let Red Pitaya's startup script finish loading the stock image first
for i in $(seq 1 30); do
  pgrep -f /opt/redpitaya/sbin/startup.sh >/dev/null || break
  sleep 1
done

systemctl stop redpitaya_nginx jupyter 2>/dev/null
XADC=/sys/bus/platform/drivers/xadc
[ -e $XADC/83c00000.xadc_wiz ] && echo 83c00000.xadc_wiz > $XADC/unbind

cat "$BIT" > /dev/xdevcfg || { echo "load failed"; exit 1; }
echo "loaded $BIT, prog_done=$(cat /sys/devices/soc0/amba/f8007000.devcfg/prog_done)"
