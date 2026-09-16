# M5 requant 门 run03 — V1.2e 窗口化 c3 解码（2026-09-17, B0 迭代 10）

## 结果：TB_REQUANT_PASS（与 run01/v18、run02/v22 逐计数一致）

```
[tb] requant stim=../stim/requant vectors=22493 pipe=5
TB_REQUANT_PASS compared=21465 vectors (y_pre+vld, pipe=5)
```

## RTL 变更（rtl/yolo_requant.v V1.2d → V1.2e，PIPE=5/吞吐不变）

v23 ooc top10 全体为 `prod_c_w__2/CLK→q_r −0.457…−0.340`——c3 拍
64 输出桶形 `prod >>> s` 本体（DSP P 寄存 CLK→P + 6 级 mux + 64 负载
路由）。q_r 的全部消费者只需三样：

1. **q[7:0]**（c4 9 位舍入加）：q[j] = prod[j+s]，越界补符号——8 个
   64:1 窗口 mux（每比特 idx=(s+j)>63 判符号，2+3L）；
2. **q[63]**：算术右移保号，恒等于 prod[63]（0L，qneg_r）；
3. **在域判定**：q∈[−128,127] ⟺ −2^(s+7) ≤ prod ≤ 2^(s+7)−1
   （floor 除法边界反推）⟺ magn < 2^(s+7)，magn = prod[63]?~prod:prod
   （2L），用 c2 沿从 s_r1 预寄存的 himask_r（= 全1<<(s+7)，s≥57 → 0
   = 恒过；与 V1.2d mask_r 同模式同沿）AND 后 6L OR 归约。

64 位桶形整体消失（64 FF → 10 FF）。c4 域内/域外臂逐位等价
（sum9 用 q8_r，饱和方向用 qneg_r，ir_r = 原 ir_pos||ir_neg）。

## 过程记录（run03a FAIL → run03b PASS）

- **run03a（首版，2739 错，错型 `y=+127 exp=0x80`）**：himask 首版写成
  `~(全1<<(s+7))`——那是**低位**掩码 2^t−1，等价于拿 magn 的低 t 位做
  在域判定。手推复现：向量 acc=−257, s=1 → q=−129 域外，被误判域内，
  窗口 0x7F + ru=1 触发 ovf → +127（黄金 −128=0x80，TB 的 exp_q 无符号
  打印成 128）。修复：`全1<<(s+7)`（高位掩码 bits [63:s+7]）。
- **门链拦截生效**：M5 FAIL 时下游未发（本轮 M10/M12/OOC v24 均在
  M5 通过后才启动）。失败 transcript 留档 m5_v24a_xsim_fail.log
  （M9b run03 教训：失败跑与通过跑不同名——本轮先改名再复跑）。
- 与 V1.2d 的 ovf 判据 bug 同属"位级手推 vs 数值字面量"类错误，第二次
  被 M5 拦截。
- **run03b：PASS**，compared=21465 与 v18/v20/v22 相同。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m5_v24.sh
```

激励 = 冻结集 sim/stim/requant（v18 黄金，sha256 见 stim_sha256.txt）。

门链位置：B0 迭代 10——**M5 run03** → M10 v24 → M12 csr v24 → OOC v24。
