# 2026-09-17 yolo7020 M12 CSR/engine 门 run09 — B0 迭代 13

## 结果

**TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1 csr=0**——与 run06–run08（v24/v25/v26）
逐一相同；csr=0 = AXI-Lite 协议/读回/IRQ 零错。

**与 v26（run08）逐拍相同**——六层完成时刻全部一致
（layer0 @36370000 … layer5 @43958550000）。V1.10 拆分在 d9 呈现
拍之前完成，CSR 可见节拍零变化。

## 本跑覆盖的变更（相对 run08 / v26）

| 模块 | 版本 | 变更 |
|---|---|---|
| gemm_array | V1.9→V1.10 | 行地址乘加拆分（cfg d1 快照 + 寄存积 d2 + d3 合并）；d9 呈现拍不变 |

requant/addrgen/ctrl/csr 不动。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim_eng && bash run_m12csr_v27.sh
```

激励 = stim/m10 冻结集。原始日志：eng_v27_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 13——M10 run12 + **M12 csr run09（本跑）** →
OOC v27。
