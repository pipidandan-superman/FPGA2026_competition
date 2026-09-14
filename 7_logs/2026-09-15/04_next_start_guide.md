# 2026-09-15 下次启动指南

## 当前：G2 已通过，进入 3_yolo_zynq 硬件侧（任务 #6）

1. 部署包已就位 `2_fpga/3_yolo_zynq/rom_data/`（weights/bias/lut/quant/manifest + README；来源 G2 run，SHA 一致）。`quant.json` 是节点表/尺度/req/偏移的唯一权威；golden 对齐源在 `4_metrics/logs/2026-09-14_yolo7020_g2_quant_intref_run01/golden/` 与 `regression_128frames.json`。
2. PS 侧按 PYNQ 流程开发（借鉴只读 `2_fpga/0_diaplay_test` 的板型/时钟/DDR 参数，借用表在 `3_yolo_zynq/doc/README.md`）。PS 首责：DFL softmax + 解码 + NMS（float64，`intref_yolov8.py` 已有可移植参考实现）。
3. G3 单算子：先做 conv（含首层 z 折叠路径）与 golden 逐位对齐，再做 LUT/Add/Concat/MaxPool/Upsample。数值合同冻结，实现不得改合同。
4. 数值口径：valid drop +0.0176（G2）；test +0.0571 未参与调参仅报告；Left 类残余 −0.100 是已知弱点。

## 边界（沿用）

- `2_fpga/0_diaplay_test` 只读；新建内容仅限 `3_yolo_zynq`；文件不越 `E:\competition`。
- 板卡加载/重配置需用户单独授权；测试集不参与调参；数据本体不入 Git。
- main 受保护：提交走个人分支 + PR（PR #8 仍待队友审核）。

## 后续可选（单变量，按需）

- G2 裕量提升：偏置校正 / p99.9 网格 / 计划第 17 行 QAT 决策。
- HaGRID OOD 评估（COCO→YOLO bbox 转换 + user_id 划分）；方向类数据缺口见调研文档。
