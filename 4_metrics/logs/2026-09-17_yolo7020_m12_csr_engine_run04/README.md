# 2026-09-17 yolo7020 M12 CSR/engine 门 run04 — B0 迭代 8

## 结果

**TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1 csr=0**——与 run02/run03 逐一相同；
csr=0 = AXI-Lite 协议/读回/IRQ 零错。

## 本跑覆盖的变更（相对 run03 / v21）

| 模块 | 版本 | 变更 |
|---|---|---|
| requant | V1.2c→V1.2d | 掩码 sticky + 范围归约饱和（M5 run02 证明；首版 ovf 判据 bug 被 M5 门拦截后修复，本跑为修复后 RTL） |
| dma | V1.1→V1.2 | 突发末拍 bnd 结算（M9 run03） |
| dma_wr | V1.3→V1.4 | 突发末拍 bnd 结算（M9b run05） |

engine_top 级 CSR×engine 全链在迭代 8 批下全绿，计数与合同前完全一致。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim_eng && bash run_m12csr_v22.sh
```

原始日志：eng_v22_{xvlog,xelab,xsim}.log。激励 = stim/m10 冻结集。

门链位置：B0 迭代 8——M5 run02 → M9 run03 → M9b run05 → **M12 csr
run04** → M10 run07 → OOC v22。
