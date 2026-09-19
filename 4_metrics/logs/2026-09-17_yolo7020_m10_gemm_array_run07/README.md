# M10 gemm_array 门 run07 — B0 迭代 8（requant V1.2d + dma V1.2 + dma_wr V1.4，2026-09-17）

## 结果：TB_GEMM_ARRAY_PASS（与 run05/v19、run06/v21 逐计数一致）

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
$finish : tb_yolo_gemm_array.v(802)  Time: 47770370 ns
```

各层完成时刻与 v21 逐拍相同（layer0 @29896000 … finish @47770370）——
纯重定时的直接佐证。

## RTL 变更（相对 run06 / v21）

- `yolo_requant.v` V1.2c→V1.2d：sticky 改掩码 AND+OR 树（c2 沿预寄存
  mask_r，仅依赖 s_r1）；饱和改范围归约+9 位加（M5 run02 证明，含首版
  ovf 判据 bug 的拦截与修复记录）。
- `yolo_dma.v` V1.1→V1.2 / `yolo_dma_wr.v` V1.3→V1.4：bnd 结算移至
  突发末拍（blen_r 5 位），words_r 退出 bnd 更新链（M9 run03 / M9b
  run05 证明）。

数值路径逐位不变（PIPE=5、AXI 行为零变化），compared/dut_wr/gold_wr
完全一致。层 5 BMG "Address 900" ×8 仍为 V1.7 冲排读已知良性警告。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m10_v22.sh
```

激励 = 冻结集 sim/stim/m10。原始日志：m10_v22_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 8——M5 run02 → M9 run03 → M9b run05 → M12 csr
run04 → **M10 run07** → OOC v22。
