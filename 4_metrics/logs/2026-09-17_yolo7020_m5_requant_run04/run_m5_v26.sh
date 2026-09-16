#!/bin/bash
# M5 v26 gate: requant V1.2f (prod2_r fabric re-register, PIPE 5->6,
# bit-exact output retiming; TB PIPE shadow 6, golden stim reused).
# Expected: TB_REQUANT_PASS compared=21465 (same counts as v18/v20/v22/v24).
cd /e/competition/2_fpga/3_yolo_zynq/sim/xsim
XV=/f/vivado2025/2025.2/Vivado/bin
$XV/xvlog.bat -work work_m5v26 \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_requant.v \
  /e/competition/2_fpga/3_yolo_zynq/sim/tb_yolo_requant.v \
  /f/vivado2025/2025.2/data/verilog/src/glbl.v \
  -log m5_v26_xvlog.log || exit 1
$XV/xelab.bat work_m5v26.tb_yolo_requant work_m5v26.glbl \
  -s snap_m5_v26 -L unisim -L unisims_ver -timescale 1ns/1ps \
  -log m5_v26_xelab.log || exit 1
$XV/xsim.bat snap_m5_v26 -R -log m5_v26_xsim.log
