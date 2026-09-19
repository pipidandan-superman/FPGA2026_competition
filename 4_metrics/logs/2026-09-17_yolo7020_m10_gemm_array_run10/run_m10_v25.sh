#!/bin/bash
# M10 v25 gate: iteration-11 (requant V1.2f PIPE 5->6 + addrgen V1.3 decode split)
cd /e/competition/2_fpga/3_yolo_zynq/sim/xsim
XV=/f/vivado2025/2025.2/Vivado/bin
$XV/xvlog.bat -work work_m10v25 \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_gemm_array.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_ctrl.v /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_dma.v /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_addrgen.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_wbuf.v /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_xbuf.v /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_acc.v /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_requant.v /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_silu_lut.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_dma_wr.v /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_conv_core.v \
  /e/competition/2_fpga/3_yolo_zynq/ip/yolo_xbuf_bmg/sim/yolo_xbuf_bmg.v \
  /e/competition/2_fpga/3_yolo_zynq/ip/yolo_xbuf_bmg/simulation/blk_mem_gen_v8_4.v \
  /e/competition/2_fpga/3_yolo_zynq/sim/tb_yolo_gemm_array.v \
  /f/vivado2025/2025.2/data/verilog/src/glbl.v \
  -log m10_v25_xvlog.log || exit 1
$XV/xelab.bat work_m10v25.tb_yolo_gemm_array work_m10v25.glbl \
  -s snap_m10v25 -L unisim -L unisims_ver -timescale 1ns/1ps \
  -log m10_v25_xelab.log || exit 1
$XV/xsim.bat snap_m10v25 -R -log m10_v25_xsim.log
