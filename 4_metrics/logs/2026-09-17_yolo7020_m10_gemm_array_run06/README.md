# M10 gemm_array 门 run06 — B0 迭代 7（dma V1.1 + dma_wr V1.3，2026-09-17）

## 结果：TB_GEMM_ARRAY_PASS（与 run05/v19、v20 逐计数一致）

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
$finish : tb_yolo_gemm_array.v(802)  Time: 47770370 ns
```

## RTL 变更（相对 run05 / v20）

- `yolo_dma.v` V1.0→V1.1：4KB 边界拍数改增量寄存器 bnd_r（接受沿
  512−addr[11:3] 装载、AR 发火沿 −beats），删每拍 (4096−addr[11:0])>>3
  重算；addr_r 变纯累加器。突发序列逐拍不变（M9 run02 逐计数一致证明）。
- `yolo_dma_wr.v` V1.2→V1.3：同款镜像（AW 侧）。M9b run04 证明。
- requant V1.2c / xbuf V2.2 / gemm_array V1.6/V1.7 / ctrl V1.8 不变
  （v19/v20 已过）。

数值路径零变化（重定时/AXI 行为零变化），compared/dut_wr/gold_wr 与
v19/v20 完全一致。层 5 期间 BMG "Address 900 outside range" ×8 为
V1.7 冲排读的已知良性过读（BMG 行为模型警告，值不参与比较，v19/v20
同在）。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m10_v21.sh
```

激励 = 冻结集 sim/stim/m10（stim_manifest.json / stim_sha256.txt）。
原始日志：m10_v21_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 7——M9 run02 → M9b run04 → M12 csr run03
→ **M10 run06** → OOC v21。
