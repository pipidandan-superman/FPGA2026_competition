# 2026-09-17 M5/M7 单元门 v25 — B0 迭代 11 单元层

## 结果

- **M5 requant V1.2f**：`TB_REQUANT_PASS compared=21465 vectors
  (y_pre+vld, pipe=6)`——计数与 v24 run03 相同；TB 唯一改动
  `localparam PIPE = 6`（en→vld 间隔 5→6 拍），订单式记分板使黄金
  hex 全复用。
- **M7 addrgen V1.3**：`TB_ADDRGEN_PASS compared=67918 beats across
  145 tiles`——值流逐位相同，呈现整体 +1 拍（start→beat0 22 拍）。

## 首跑 FAIL（transcripts 留档）

- M7 v25a：`TB_ADDRGEN_FAIL errors=66637 first_beat=4
  addr=0(exp 0) pad=1(exp 0)`——首版把 pad 的窗口比较放在与
  ih_full 捕获同沿，比较消费了上一拍的窗口（连续 pad 拍掩盖错位，
  首差恰在第一个界内拍）。修复 = 两级输出寄存（A 级捕获内部拍 /
  B 级呈现比较+选择）。

## RTL 变更

| 模块 | 版本 | 变更 |
|---|---|---|
| requant | V1.2e→V1.2f | prod2_r fabric 重寄存（v24 top1：prod_r 被 DSP 吸收为 PREG，CLK→P 发火 + 64:1 窗口 mux 同拍无解），PIPE 5→6 纯输出侧重定时；mask/himask 移至 c2b 沿从 s_r2 生成（同值晚一拍） |
| addrgen | V1.2→V1.3 | 两级输出寄存拆分窗口解码（v24 top2 家族 kh_r→pad_o/x_addr_o、k_len_c→row_off_r）+ last_k 改 k_len_m1_c 寄存预测（描述符接受沿采 K-1） |

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m5_v25.sh && bash run_m7_v25.sh
```

门链位置：B0 迭代 11——**M5 v25 + M7 v25** → M10 run10 → M12 csr v25
→ OOC v25。
