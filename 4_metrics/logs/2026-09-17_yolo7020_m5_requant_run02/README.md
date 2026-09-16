# M5 requant 门 run02 — V1.2d 掩码 sticky + 范围归约饱和（2026-09-17, B0 迭代 8）

## 结果：TB_REQUANT_PASS（与 run01/v18、v20 复跑逐计数一致）

```
[tb] requant stim=../stim/requant vectors=22493 pipe=5
TB_REQUANT_PASS compared=21465 vectors (y_pre+vld, pipe=5)
```

## RTL 变更（rtl/yolo_requant.v V1.2c → V1.2d，PIPE=5/吞吐不变）

B0 v21 ooc 两档残余 owner 的位精确修复（黄金复用 v18 冻结激励）：

1. **c3 owner prod_r→sticky_r −0.713**：V1.2c 的
   `|(prod_r << (65−s_r2))` 综合为 64b 桶形串 64b OR 树（~12L）。
   位 j 经移位存活（j+65−s ≤ 63）⟺ j ≤ s−2，故与 `|prod[s−2:0]`
   严格相等——改为与 c2 沿预寄存的 `mask_r`（= `~(全1<<(s−1))`，仅
   依赖 s_r1、与乘法完全并联；c2 周期 DSP 级联路径 v17 实测 +0.379
   余量）AND 后 OR 树（2+6L）。掩码用"移位后取反"规避 (1<<k)−1 的
   64 位借位纹波；s=0 掩 0 与旧行为（移位 ≥64→0）逐位一致。
2. **c4 档 sticky_r→y_pre_o −0.563**：V1.0 `sat_i8(q_r + ru)` 全 64
   位加 + 双向比较（~18L）改范围归约：在域 [−128,127] ⟺ `q[63:7]`
   全 0 或全 1（56b OR/AND 归约并联），域内 9 位加，唯一溢出 +128。

## 过程记录（run02a FAIL → run02b PASS）

- **run02a（首版，13 错全 `y=−128 exp=127`）**：溢出判据首版写成
  `sum9[8] && !sum9[7]`——位序错：128 的 9 位补码是 `0_1000_0000`
  （[8]=0,[7]=1），判据永假，q=127&ru=1 返回未饱和 0x80。修复：
  `(sum9 == 9'd128)`。
- **门链拦截生效**：M5 FAIL 即刻终止同批 M10/eng/OOC v22（TaskStop；
  xsim 内核僵尸进程残留锁快照目录，手动清理后重发）——数值路径改动
  必须先过模块门再进门链下游。
- **run02b：PASS**，compared=21465 与 v18/v20 相同。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m5_v22.sh
```

激励 = 冻结集 sim/stim/requant（v18 黄金，stim_manifest_requant.json /
stim_sha256.txt）。原始日志：m5_v22_{xvlog,xelab,xsim}.log（run02a 失败
transcript 同名覆盖于 m5_v22_xsim.log 之前版本，错型以本 README 记录
为准——M9b run03 教训：失败跑与通过跑不同名，本次 v22 首跑日志被
复跑覆盖，13 错错型已在修订记录中留档）。

门链位置：B0 迭代 8——**M5 run02** → M9 run03 → M9b run05 → M12 csr
v22 → M10 v22 → OOC v22。
