# 2026-09-17 yolo7020 M12 CSR/engine 门 run08 — B0 迭代 12

## 结果

**TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1 csr=0**——与 run06/run07 / v24/v25 逐一
相同；csr=0 = AXI-Lite 协议/读回/IRQ 零错。

层完成时刻再 +2 拍漂移（layer5 @43958550000，v25 为 @43958220000）
——requant PIPE 7 合法平移，CSR 轮询粒度不再完全吸收。

## 本跑覆盖的变更（相对 run07 / v25）

| 模块 | 版本 | 变更 |
|---|---|---|
| requant | V1.2f→V1.2g | 乘法操作数直通重寄存 sum_x_r/m_x_r，PIPE 6→7（M5 v26 run04） |
| gemm_array | V1.8→V1.9 | 尾链 d8→d9（LUT en rq_en_d8_r / sideband d9 / 段化器读 d9） |

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim_eng && bash run_m12csr_v26.sh
```

激励 = stim/m10 冻结集。原始日志：eng_v26_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 12——M5 run04 + M10 run11 → **M12 csr run08** →
OOC v26。
