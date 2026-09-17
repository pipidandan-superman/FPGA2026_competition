#!/bin/sh
# M13 stage E: drop page cache, run full M11 program via /dev/mem driver
set -e
cd /home/xilinx/m13
echo 3 > /proc/sys/vm/drop_caches
exec python3 -u pl_m11.py --stim ./m11 --ddr-base 0x30000000
