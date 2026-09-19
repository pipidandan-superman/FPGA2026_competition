# M10 gemm_array 门 run08 — B0 迭代 9（dma V1.3 + dma_wr V1.5，2026-09-17）

## 结果：TB_GEMM_ARRAY_PASS（与 run06/v21、run07/v22 逐计数一致）

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
$finish : tb_yolo_gemm_array.v(802)  Time: 47770370 ns
```

各层完成时刻与 v21/v22 逐拍相同（layer0 @29896000 … finish
@47770370）——迭代 9 为零周期漂移的纯重定时的直接佐证。

## RTL 变更（相对 run07 / v22）

- `yolo_dma.v` V1.2→V1.3 / `yolo_dma_wr.v` V1.4→V1.5：突发参数预计算
  拆沿——want2_r=min(words_r,16) 与 addr_r 推进（+blen_r<<3）挪到上一
  突发末拍；AW/AR 发火沿只剩 min(bnd_r,want2_r) 10 位比较 + 一次 32 位
  减法（M9 run04 / M9b run06 证明）。

数值路径逐位不变，compared/dut_wr/gold_wr 完全一致。层 5 BMG
"Address 900" ×8 仍为 V1.7 冲排读已知良性警告。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m10_v23.sh
```

激励 = 冻结集 sim/stim/m10。原始日志：m10_v23_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 9——M9 run04 → M9b run06 → M12 csr run05 →
**M10 run08** → OOC v23。
