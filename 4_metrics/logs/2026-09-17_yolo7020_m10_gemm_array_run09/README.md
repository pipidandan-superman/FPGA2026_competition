# M10 gemm_array 门 run09 — B0 迭代 10（requant V1.2e，2026-09-17）

## 结果：TB_GEMM_ARRAY_PASS（与 run06/v21、run07/v22、run08/v23 逐计数一致）

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
$finish : Time: 47770370 ns
```

各层完成时刻与 v21/v22/v23 逐拍相同（layer0 @29896000 … finish
@47770370）——迭代 10 同为零周期漂移的纯重定时。

## RTL 变更（相对 run08 / v23）

- `yolo_requant.v` V1.2d→V1.2e：64 位桶形消失，q8/qneg/ir 窗口化解码
  （M5 v24 run03 证明，含 himask 反转 bug 修复）。

数值路径逐位不变，compared/dut_wr/gold_wr 完全一致。层 5 BMG
"Address 900" ×8 仍为 V1.7 冲排读已知良性警告。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m10_v24.sh
```

激励 = 冻结集 sim/stim/m10。原始日志：m10_v24_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 10——M5 run03 → **M10 run09** → M12 csr run06 →
OOC v24。
