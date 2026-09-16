# 2026-09-17 yolo7020 M12 CSR/engine 门 run07 — B0 迭代 11

## 结果

**TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1 csr=0**——与 run06/v24 逐一相同；
csr=0 = AXI-Lite 协议/读回/IRQ 零错。

各层完成时刻与 v24 逐拍相同（layer0 @36250000 …
layer5 @43958220000）——引擎内部 +2 拍（addrgen 呈现 +1、requant
尾 +1）被 CSR 轮询粒度吸收，对外零漂移。

## 首跑 v25a FAIL（transcript 留档 eng_v25a_xsim_fail.log）

err=134307——与 M10 v25a 同根因（gemm_array Y 尾固定延迟链挂
requant PIPE=5），M10 run10 README 详述；gemm_array V1.8 修复后
本轮全绿。

## 本跑覆盖的变更（相对 run06 / v24）

| 模块 | 版本 | 变更 |
|---|---|---|
| requant | V1.2e→V1.2f | prod2_r fabric 重寄存，PIPE 5→6（M5 v25） |
| addrgen | V1.2→V1.3 | 两级输出寄存 + last_k 预测（M7 v25） |
| gemm_array | V1.7→V1.8 | Y 尾延迟链适配 PIPE=6（LUT en d7 / sideband d8 / 段化器读 d8） |

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim_eng && bash run_m12csr_v25.sh
```

激励 = stim/m10 冻结集。原始日志：eng_v25_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 11——M5 v25 + M7 v25 → M10 run10 →
**M12 csr run07** → OOC v25。
