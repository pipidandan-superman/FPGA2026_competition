#!/bin/bash
# M7 v25 gate: addrgen V1.3 (window decode split across the output-register
# boundary + last_k one-beat prediction -- external stream VALUES AND TIMING
# identical -> v18 golden stim reused).
# Expected: TB_ADDRGEN_PASS compared=67918 beats across 145 tiles.
cd /e/competition/2_fpga/3_yolo_zynq/sim/xsim
XV=/f/vivado2025/2025.2/Vivado/bin
$XV/xvlog.bat -work work_m7v25 \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_addrgen.v \
  /e/competition/2_fpga/3_yolo_zynq/sim/tb_yolo_addrgen.v \
  /f/vivado2025/2025.2/data/verilog/src/glbl.v \
  -log m7_v25_xvlog.log || exit 1
$XV/xelab.bat work_m7v25.tb_yolo_addrgen work_m7v25.glbl \
  -s snap_m7_v25 -L unisim -L unisims_ver -timescale 1ns/1ps \
  -log m7_v25_xelab.log || exit 1
$XV/xsim.bat snap_m7_v25 -R -log m7_v25_xsim.log
