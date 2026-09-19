#!/bin/sh
# M13 stage C+D: fpga_manager download + CSR identity read
# (download success != AXI alive; identity read is the gate)
set -e
cd /home/xilinx/m13
cp yolo_a2.bit /lib/firmware/
echo 0 > /sys/class/fpga_manager/fpga0/flags
echo yolo_a2.bit > /sys/class/fpga_manager/fpga0/firmware
sleep 2
echo "STATE=$(cat /sys/class/fpga_manager/fpga0/state)"
echo "CSR_ID=$(devmem 0x43C10000 32)"
echo "CSR_VER=$(devmem 0x43C10004 32)"
