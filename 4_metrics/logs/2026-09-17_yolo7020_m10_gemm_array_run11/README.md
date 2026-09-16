# M10 gemm_array 门 run11 — B0 迭代 12（requant V1.2g + gemm_array V1.9，2026-09-17）

## 结果：TB_GEMM_ARRAY_PASS（计数与 run09/run10 / v24/v25 逐一相同）

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
```

数值字节逐位不变；层完成时刻再 +2 拍漂移（layer0 @29936000，
v25 为 @29916000）——requant PIPE 7 的合法平移。

## RTL 变更（相对 run10 / v25）

- `yolo_requant.v` V1.2f→V1.2g：乘法操作数直通重寄存 sum_x_r/m_x_r
  （c1b 沿，PIPE 6→7，DSP 级联 AREG/BREG 吸收候选——v25 OOC 唯一
  owner sum_r→PCIN −0.079 的修复）（M5 v26 run04 承证）。
- `yolo_gemm_array.v` V1.8→V1.9：尾链再伸一级——LUT en
  rq_en_d8_r、sideband d9、SEG_IDLE 读 d9、在途计数峰值 8→9
  （仍 4 位）。ctrl/addrgen 不动。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m10_v26.sh
```

激励 = 冻结集 sim/stim/m10。原始日志：m10_v26_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 12——M5 run04 → **M10 run11** → M12 csr v26 →
OOC v26。
