# 2026-09-17 yolo7020 M10 gemm_array run12 — B0 迭代 13

## 结果

**TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1**——计数与 run09/run10/run11
（v24/v25/v26）逐一相同。

**与 v26（run11）逐拍相同**——六层完成时刻全部一致：

| 层 | v26 | v27 |
|---|---|---|
| 0 | 29936000 | 29936000 |
| 1 | 23305386000 | 23305386000 |
| 2 | 23696076000 | 23696076000 |
| 3 | 24122446000 | 24122446000 |
| 4 | 43156496000 | 43156496000 |
| 5 | 43927166000 | 43927166000 |

$finish 47771360 ns 亦与 v26 相同。V1.10 的 d9 呈现拍不变设计
得到实证（行地址腿 d3 完成后被移位链吸收，不改变任何可见节拍）。

## 本跑覆盖的变更（相对 run11 / v26）

| 模块 | 版本 | 变更 |
|---|---|---|
| gemm_array | V1.9→V1.10 | 行地址乘加拆分：cfg（n_total/ybase）d1 快照；16x16 乘法寄存积 row_prod_d2_r（单 DSP PREG）；ybase+n_base 并行布线加 row_sum_d2_r；d3 沿合并 row_addr_d3_r。mod-2^32 逐位等价 |

requant/addrgen/ctrl 不动（v26 单元门结果有效）。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m10_v27.sh
```

激励 = stim/m10 冻结集。原始日志：m10_v27_{xvlog,xelab,xsim}.log
（drv.log 为驱动输出）。

门链位置：B0 迭代 13——M10 run12（本跑）→ M12 csr v27 → OOC v27。
