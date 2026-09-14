# 2026-09-15 验证摘要

## 当前：G2 量化整数参考门限通过（2026-09-15）

**G2_QUANT_INTREF_PASS**：valid FP32 mAP50 0.8939 → INT8 0.8763，drop +0.0176 ≤ 0.02（计划 r3 G2 门限）。逐层余弦 165 检查最差 0.9305；数值合同（W8A8、每通道 M+shift RNE、双尺度 SiLU LUT、首层 u−128 z 折叠）全程未变——方法演进只动校准。test split drop +0.0571（FP 基线仅 0.7255、npos 极少，未参与调参，如实报告；残余损失主因 valid Left −0.100 ≈1.4 框当量）。部署包 weights/bias/lut/quant+manifest 已复制 `2_fpga/3_yolo_zynq/rom_data/` 并逐字节哈希核对；golden（5 图全节点张量）与 128 帧回归为 G3 对齐源。[G2 REPORT](../../4_metrics/logs/2026-09-14_yolo7020_g2_quant_intref_run01/REPORT.md)。限制：LSQ 再拟合 ×6 轮会过收缩（+0.0344），×2 为选定平衡点；若需更高 test 裕量，后续单变量候选为偏置校正/QAT（计划第 17 行）。

## 补记：G1 FP32 基线（完成于 2026-09-14）

G1_FP32_BASELINE_PASS：640/416/320 三尺寸，320 较 640 valid mAP50 −0.0278（更高），G2 采用 320；420 图校准清单产出。[G1 REPORT](../../4_metrics/logs/2026-09-14_yolo7020_g1_fp32_baseline_run01/REPORT.md)。

## 待办交接

G3 单算子 RTL 逐位对齐（以 golden npz 为源）+ `3_yolo_zynq` PS 侧 PYNQ 开发（借鉴 `0_diaplay_test` 参数，其 doc/README 借用表已建）。PR #8 仍在等队友审核。
