#!/bin/bash
# =====================================================================
# M11 full-network gate, B0 收敛/冻结批 (RTL v27) -- ModelSim 过夜
# ---------------------------------------------------------------------
# PRECONDITION: B0 OOC v27 收敛或冻结后启动 (2026-09-17 用户授权:
#   B0 收敛/冻结后 M11 过夜直接启动, 无需再问).
# RTL = xbuf V2.2 (BMG 输出寄存, 读延迟 2) + gemm_array V1.10
#   (W 预取 D+2 对齐 + 末拍 flush 读 + requant PIPE 适配:
#   迭代 11 d7/d8, 迭代 12 LUT en d8 / sideband d9 / 段化器读 d9;
#   迭代 13 行地址乘加拆分 -- cfg d1 快照 + 寄存积 d2 + d3 合并,
#   d9 呈现拍不变)
#   + ctrl V1.8 (S_DRAIN 4) + dma V1.3 / dma_wr V1.5 (迭代 9)
#   + requant V1.2g (迭代 12: sum_x_r/m_x_r 操作数直通重寄存,
#   PIPE 6->7, DSP 级联 AREG/BREG 吸收; 迭代 11 prod2_r PIPE 5->6)
#   + addrgen V1.3 (迭代 11: 两级输出寄存 + last_k 预测)
#   -- 数值字节不变 (延迟平移合同, 授权 2026-09-17; 迭代 9-11 均为
#   位精确纯重定时, 黄金全复用).
# 编译集: 12 rtl + xbuf BMG IP 仿真源 + tb_yolo_fullnet + glbl +
#         unisims DSP48E1 (pe_pack V1.2 直例原语, vsim-3033 规避).
# 判据  : TB_FULLNET_PASS convs=63 psops=65 compared=3553900
#         dut_wr=3553900 head_bytes=149100 ldone=63 adone=1
#       + python ../m11_headcheck.py head_dump.bin
#         (sha256 == run04 frame0 raw_head_sha256
#          9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad)
# 对照  : v13 run (msim_v13/v13_m11_run.log, TB_FULLNET_PASS 同
#   token 同计数) 是 B0 期唯一已执行的全网 M11 -- v14-v24 迭代期
#   M11 按授权延后到收敛/冻结批一次性重跑, 即本跑。延迟平移后数值合同不变承证;
#   逐拍 cycle 计数可随合同合法漂移 -- 迭代 11 requant vld +1 拍、
#   addrgen 呈现 +1 拍, 字节判决不变).
# 用法  : cd sim/msim_v19 && bash run_m11_v27.sh  (过夜, 数小时墙钟)
# =====================================================================
# M11 full-network gate, ⑤ timing-fix batch (RTL v19) -- ModelSim
# ---------------------------------------------------------------------
# PRECONDITION: B0 OOC v19 收敛或冻结后启动 (2026-09-17 用户授权:
#   B0 收敛/冻结后 M11 过夜直接启动, 无需再问).
# RTL = xbuf V2.2 (BMG 输出寄存, 读延迟 2) + gemm_array V1.6/V1.7
#   (W 预取 D+2 对齐 + 末拍 flush 读, 修复 BMG 两级 ENB 门控流水
#   滞留末字节) + ctrl V1.8 (S_DRAIN 4) -- 纯延迟平移合同, 数值字节
#   不变 (授权 2026-09-17).
# 编译集: 12 rtl + xbuf BMG IP 仿真源 + tb_yolo_fullnet + glbl +
#         unisims DSP48E1 (pe_pack V1.2 直例原语, vsim-3033 规避).
# 判据  : TB_FULLNET_PASS convs=63 psops=65 compared=3553900
#         dut_wr=3553900 head_bytes=149100 ldone=63 adone=1
#       + python ../m11_headcheck.py head_dump.bin
#         (sha256 == run04 frame0 raw_head_sha256
#          9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad)
# 对照  : v14 run (msim_v14) 同 token 同计数 (延迟平移后数值合同不变承证;
#   逐拍 cycle 计数可随合同合法漂移, 字节判决不变).
# 用法  : cd sim/msim_v14 && bash run_m11_v14.sh   (过夜, 数小时墙钟)
# =====================================================================
set -u
VLIB=/d/work/modelsim/win64/vlib.exe
VLOG=/d/work/modelsim/win64/vlog.exe
VSIM=/d/work/modelsim/win64/vsim.exe
R=../..
UNIS=/f/vivado2025/2025.2/Vivado/data/verilog/src/unisims/DSP48E1.v
GLBL=/f/vivado2025/2025.2/data/verilog/src/glbl.v

echo "[v27] compile -> work_v27"
# vlib first: vlog-19 if the library dir is absent (v19/v25/v26 scripts
# were never executed, so this latent gap surfaces only now)
[ -d work_v27 ] || "$VLIB" work_v27
"$VLOG" -work work_v27 \
    $R/rtl/yolo_gemm_array.v \
    $R/rtl/yolo_ctrl.v \
    $R/rtl/yolo_dma.v \
    $R/rtl/yolo_addrgen.v \
    $R/rtl/yolo_wbuf.v \
    $R/rtl/yolo_xbuf.v \
    $R/rtl/yolo_pe_pack.v \
    $R/rtl/yolo_acc.v \
    $R/rtl/yolo_requant.v \
    $R/rtl/yolo_silu_lut.v \
    $R/rtl/yolo_dma_wr.v \
    $R/rtl/yolo_conv_core.v \
    $R/ip/yolo_xbuf_bmg/sim/yolo_xbuf_bmg.v \
    $R/ip/yolo_xbuf_bmg/simulation/blk_mem_gen_v8_4.v \
    ../tb_yolo_fullnet.v \
    "$UNIS" \
    "$GLBL" \
    > v27_vlog.log 2>&1
grep -E "\*\* Error" v27_vlog.log && { echo "[v27] COMPILE FAIL"; exit 1; }
echo "[v27] compile clean"

echo "[v27] vsim fullnet (overnight)"
"$VSIM" -c -novopt +STIM=../stim/m11 +WDT_MS=3600000 \
    -do "run -all; quit -f" -l v27_m11_run.log \
    work_v27.tb_yolo_fullnet work_v27.glbl \
    > v27_vsim_stdout.log 2>&1

grep -E "TB_FULLNET_PASS|TB_FULLNET_FAIL" v27_m11_run.log
echo "[v27] headcheck vs run04 frame0 golden"
python ../m11_headcheck.py head_dump.bin
