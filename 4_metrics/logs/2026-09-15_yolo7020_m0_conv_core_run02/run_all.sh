#!/bin/bash
# M0 conv_core 门重跑（run02）：RTL V1.2（oc 越界部分选择零扩展修复）回归
# 背景：M10 集成暴露 P_AW > OC_CW 时 oc[P_AW-1:0] 读 X（bias/m/shift 全 X）。
# 本回归验证 V1.2 对 M0 全部用例零行为变化（M0 用例均 P_AW == OC_CW）。
# run01（V1.1 首过门）日志冻结于 ../2026-09-15_yolo7020_m0_conv_core_run01/。
export MGLS_LICENSE_FILE=D:/work/modelsim/win64/LICENSE.TXT
VLOG=D:/work/modelsim/win64/vlog
VSIM=D:/work/modelsim/win64/vsim
LOGROOT=E:/competition/4_metrics/logs/2026-09-15_yolo7020_m0_conv_core_run02
cd /e/competition/2_fpga/3_yolo_zynq/sim/msim || exit 1

$VLOG -quiet ../../rtl/yolo_conv_core.v ../tb_yolo_conv_core.v || exit 1

run() { # name "gargs" stim wdt
  name=$1; gargs=$2; stim=$3; wdt=$4
  echo "=== RUN $name ($(date +%H:%M:%S)) ==="
  $VSIM -c -novopt $gargs +STIM=$stim +CASE=$name +WDT_MS=$wdt \
    -do "run -all; quit -f" -l $LOGROOT/sim_$name.log \
    work.tb_yolo_conv_core >/dev/null 2>&1
  grep -E "TB_CONVGEN" $LOGROOT/sim_$name.log | sed 's/^# //' | head -2
}

run genE     "-gIC=5 -gOC=5 -gIH=9 -gIW=9 -gSH=1 -gSW=1 -gPH=0 -gPW=0 -gPAD_VAL=0 -gHAS_ACT=1" ../stim/genE_k45_n49_rand 60
run genF     "-gIC=32 -gOC=3 -gKH=1 -gKW=1 -gIH=13 -gIW=13 -gSH=2 -gSW=2 -gPH=0 -gPW=0 -gPAD_VAL=0 -gHAS_ACT=1" ../stim/genF_k32_1x1_s2p0_ext 60
run genG     "-gIC=64 -gOC=2 -gKH=1 -gKW=1 -gIH=8 -gIW=8 -gSH=1 -gSW=1 -gPH=0 -gPW=0 -gPAD_VAL=0 -gHAS_ACT=1" ../stim/genG_k64_1x1_rand 60
run genCrand "-gIC=256 -gOC=7 -gKH=1 -gKW=1 -gIH=10 -gIW=10 -gSH=1 -gSW=1 -gPH=0 -gPW=0 -gPAD_VAL=0 -gHAS_ACT=0" ../stim/genC_k256_1x1_noact_rand 60
run genCzero "-gIC=256 -gOC=7 -gKH=1 -gKW=1 -gIH=10 -gIW=10 -gSH=1 -gSW=1 -gPH=0 -gPW=0 -gPAD_VAL=0 -gHAS_ACT=0" ../stim/genC_k256_1x1_noact_zero 60
run genArand "-gIC=3 -gOC=16 -gIH=96 -gIW=96 -gSH=2 -gSW=2 -gPH=1 -gPW=1 -gPAD_VAL=128 -gHAS_ACT=1" ../stim/genA_k27_s2p1_rand 90
run genAext  "-gIC=3 -gOC=16 -gIH=96 -gIW=96 -gSH=2 -gSW=2 -gPH=1 -gPW=1 -gPAD_VAL=128 -gHAS_ACT=1" ../stim/genA_k27_s2p1_ext 90
run genD     "-gIC=256 -gOC=4 -gIH=12 -gIW=12 -gSH=1 -gSW=1 -gPH=1 -gPW=1 -gPAD_VAL=0 -gHAS_ACT=1" ../stim/genD_k2304_s1p1_rand 90
run genB     "-gIC=64 -gOC=8 -gIH=40 -gIW=40 -gSH=1 -gSW=1 -gPH=1 -gPW=1 -gPAD_VAL=0 -gHAS_ACT=1" ../stim/genB_k576_s1p1_rand 200
run case0    "" ../stim/conv0_golden00 400
run case0b   "" ../stim/conv0_golden02 400
echo "=== ALL DONE $(date +%H:%M:%S)) ==="

# ---- M10 dbg6（conv_core V1.2 + 哨兵歧义规则后的阵列门重验）----
$VLOG -quiet ../../rtl/yolo_gemm_array.v ../tb_yolo_gemm_array.v || exit 1
$VSIM -c -novopt +STIM=../stim/m10 +WDT_MS=60000 \
  -do "run -all; quit -f" -l E:/competition/2_fpga/3_yolo_zynq/sim/msim/sim_m10_dbg6.log \
  work.tb_yolo_gemm_array >/dev/null 2>&1
grep -E "TB_GEMM_ARRAY|dbg-g0w1|dbg-cmp|first diff|dbg-sent" \
  E:/competition/2_fpga/3_yolo_zynq/sim/msim/sim_m10_dbg6.log | sed 's/^# //' | head -12
echo "=== DBG6 DONE ==="
