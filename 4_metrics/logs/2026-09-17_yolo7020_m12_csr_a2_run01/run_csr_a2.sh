#!/bin/bash
# =====================================================================
# M12 CSR/engine gate, A2 loader V2 batch -- ModelSim
# ---------------------------------------------------------------------
# PRECONDITION: OOC v28 (A2) + M11 run05. TB = tb_yolo_engine_top V1.1:
#   X 组合口退役 -> x_m_axi_* 4 深突发队列 BFM (xbfmer 判据);
#   FLDS 29 (walk@28), DESC1 walk@19, VER 0x0002_0000.
# RTL = engine_top V1.1 + csr V1.2 (DESC1[19] walk, VER A2) +
#   gemm_array V2.0c closure (xrowgen V1.3a) + yolo_conv_core 黄金 (4 例).
# 判据  : TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
#         gold_wr=3247 ldone=6 adone=1 csr=0 xbfmerr=0 xost=2
#         (与 v27 csr 门 v24 判定行可比, 新增 xbfmerr/xost 尾巴)
# 用法  : cd sim/msim_a2 && bash run_csr_a2.sh
# =====================================================================
set -u
VLIB=/d/work/modelsim/win64/vlib.exe
VLOG=/d/work/modelsim/win64/vlog.exe
VSIM=/d/work/modelsim/win64/vsim.exe
R=../..
UNIS=/f/vivado2025/2025.2/Vivado/data/verilog/src/unisims/DSP48E1.v
GLBL=/f/vivado2025/2025.2/data/verilog/src/glbl.v

echo "[csr] compile -> work_csr"
[ -d work_csr ] || "$VLIB" work_csr
"$VLOG" -work work_csr \
    $R/rtl/yolo_engine_top.v \
    $R/rtl/yolo_gemm_array.v \
    $R/rtl/yolo_csr.v \
    $R/rtl/yolo_ctrl.v \
    $R/rtl/yolo_dma.v \
    $R/rtl/yolo_xrowgen.v \
    $R/rtl/yolo_wbuf.v \
    $R/rtl/yolo_xbuf.v \
    $R/rtl/yolo_pe_pack.v \
    $R/rtl/yolo_acc.v \
    $R/rtl/yolo_requant.v \
    $R/rtl/yolo_silu_lut.v \
    $R/rtl/yolo_dma_wr.v \
    $R/rtl/yolo_conv_core.v \
    $R/ip/yolo_wbuf_bmg/sim/yolo_wbuf_bmg.v \
    $R/ip/yolo_xbuf_bmg/sim/yolo_xbuf_bmg.v \
    $R/ip/yolo_xbuf_bmg/simulation/blk_mem_gen_v8_4.v \
    ../tb_yolo_engine_top.v \
    "$UNIS" \
    "$GLBL" \
    > csr_vlog.log 2>&1
grep -E "\*\* Error" csr_vlog.log && { echo "[csr] COMPILE FAIL"; exit 1; }
echo "[csr] compile clean"

echo "[csr] vsim engine gate"
"$VSIM" -c -novopt +STIM=../stim/m10 +WDT_MS=900000 \
    -do "run -all; quit -f" -l csr_a2_run.log \
    work_csr.tb_yolo_engine_top work_csr.glbl \
    > csr_vsim_stdout.log 2>&1

grep -E "TB_CSR_ENGINE_PASS|TB_CSR_ENGINE_FAIL" csr_a2_run.log
