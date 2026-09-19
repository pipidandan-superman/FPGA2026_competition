#!/bin/bash
# M12 csr engine gate v27 (engine_top level, iteration-13 RTL):
#   gemm_array V1.10 only -- row-address multiply split (registered
#   16x16 product row_prod_d2_r + parallel fabric adds, cfg terms
#   snapshotted at d1, address completes d3). d9 presentation
#   unchanged: expect cycle-identical to v26 (layer5 @43958550000).
#   Expected: TB_CSR_ENGINE_PASS, identical counts (layers=6
#   compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1 csr=0).
cd /e/competition/2_fpga/3_yolo_zynq/sim/xsim_eng
XV=/f/vivado2025/2025.2/Vivado/bin
$XV/xvlog.bat -work work \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_engine_top.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_gemm_array.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_csr.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_ctrl.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_dma.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_dma_wr.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_wbuf.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_xbuf.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_addrgen.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_acc.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_requant.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_silu_lut.v \
  /e/competition/2_fpga/3_yolo_zynq/rtl/yolo_conv_core.v \
  /e/competition/2_fpga/3_yolo_zynq/ip/yolo_xbuf_bmg/sim/yolo_xbuf_bmg.v \
  /e/competition/2_fpga/3_yolo_zynq/sim/tb_yolo_engine_top.v \
  /f/vivado2025/2025.2/data/verilog/src/glbl.v \
  -log eng_v27_xvlog.log || exit 1
$XV/xelab.bat work.tb_yolo_engine_top work.glbl \
  -s snap_eng_v27 -L blk_mem_gen_v8_4_12 -L unisim -L unisims_ver \
  -timescale 1ns/1ps -log eng_v27_xelab.log || exit 1
$XV/xsim.bat snap_eng_v27 -R -log eng_v27_xsim.log
