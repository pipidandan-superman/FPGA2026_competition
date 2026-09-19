# 2026-09-17 yolo7020 M12 CSR/engine 门 run05 — B0 迭代 9

## 结果

**TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1 csr=0**——与 run02/03/04 逐一相同；
csr=0 = AXI-Lite 协议/读回/IRQ 零错。

## 本跑覆盖的变更（相对 run04 / v22）

| 模块 | 版本 | 变更 |
|---|---|---|
| dma | V1.2→V1.3 | 突发参数预计算拆沿（M9 run04） |
| dma_wr | V1.4→V1.5 | 同上（M9b run06） |

engine_top 级 CSR×engine 全链在迭代 9 批下全绿，计数与合同前完全一致。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim_eng && bash run_m12csr_v23.sh
```

原始日志：eng_v23_{xvlog,xelab,xsim}.log。激励 = stim/m10 冻结集。

门链位置：B0 迭代 9——M9 run04 → M9b run06 → **M12 csr run05** →
M10 run08 → OOC v23。
