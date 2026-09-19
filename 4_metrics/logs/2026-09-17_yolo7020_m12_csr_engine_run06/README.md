# 2026-09-17 yolo7020 M12 CSR/engine 门 run06 — B0 迭代 10

## 结果

**TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1 csr=0**——与 run05/v23 逐一相同；
csr=0 = AXI-Lite 协议/读回/IRQ 零错。

各层完成时刻与 v23 逐拍相同（eng TB：layer0 @36250000 …
layer5 @43958220000）——requant V1.2e 零周期漂移。

## 本跑覆盖的变更（相对 run05 / v23）

| 模块 | 版本 | 变更 |
|---|---|---|
| requant | V1.2d→V1.2e | 窗口化 c3 解码（M5 v24 run03） |

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim_eng && bash run_m12csr_v24.sh
```

原始日志：eng_v24_{xvlog,xelab,xsim}.log。激励 = stim/m10 冻结集。

门链位置：B0 迭代 10——M5 run03 → M10 run09 → **M12 csr run06** →
OOC v24。
