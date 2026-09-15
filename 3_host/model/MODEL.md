# 模型说明 — 手势识别 YOLOv8n v1

## 模型名称与来源

- **模型**：YOLOv8n 目标检测，Ultralytics COCO 预训练底座微调（官方预训练权重 `yolov8n.pt`，AGPL-3.0）
- **微调数据**：Roboflow Universe `yolo-zxvpk/hand-gesture-r7qgb` v6，许可证 CC BY 4.0
  （train 1765 / valid 59 / test 69，7 类）
- **版本**：gesture_v1（2026-09-07 训练），训练代码环境 Ultralytics 8.4.142

## 类别表（顺序即类别 id）

| id | 类别 | 语义 |
|---|---|---|
| 0 | Down | 食指指向下方 |
| 1 | Left | 食指指向左侧 |
| 2 | Right | 食指指向右侧 |
| 3 | Stop | 掌心朝前停止 |
| 4 | Thumbs Down | 拇指朝下（取消） |
| 5 | Thumbs up | 拇指朝上（确认） |
| 6 | Up | 食指指向上方 |

## 权重文件

| 文件 | 格式 | 大小 | 用途 |
|---|---|---|---|
| `best.pt` | PyTorch | 6.3 MB | 训练/微调底座、PC 端推理 |
| `best.onnx` | ONNX opset（simplify） | 12.3 MB | 部署推理（当前 CPU EP，目标机换 NPU EP） |

## 输入输出张量（onnxruntime 实测）

- **输入**：`images`，形状 `[1, 3, 640, 640]`，float32，数值域 0~1
- 预处理：640×480 输入帧 → letterbox 等比缩放（灰色填充 114）→ BGR→RGB → ÷255
- **输出**：`output0`，形状 `[1, 11, 8400]`（4 框坐标 + 7 类得分，8400 候选）
- 后处理：置信度阈值 0.45 + NMS（IoU 0.7 默认）

## 训练参数

`yolo detect train model=yolov8n.pt data=<data.yaml> epochs=60 imgsz=640 batch=16 device=0`
（RTX 5070 Ti Laptop，约 25 分钟）

## 已验证结果

**test 集（69 张，未参与训练）**：

| 指标 | 值 |
|---|---|
| mAP@0.5 | **0.730** |
| mAP@0.5:0.95 | 0.438 |
| Precision / Recall | 0.668 / 0.743 |

分类别 mAP50：Stop 0.995 / Thumbs up 0.967 / Up 0.956 / Down 0.928 / Left 0.511 / Right 0.418 / Thumbs Down 0.335

**实时链路实测**（PC 回环，摄像头→JPEG→UDP→ONNX CPU 推理→JSON 回传）：
27.5s 会话 349 帧，6/7 类在对应时间窗连续命中；延迟 P50 62ms / P95 118ms（CPU）。
证据：`7_logs/2026-09-07/03_validation_summary.md`（V-A1~V-A7）。

## 已知弱项与计划

- **Left / Right / Thumbs Down** 为弱项（成对易混 + 样本不足）。
- 计划：自采三类别各 ≥100 张（真实使用场景摄像头）合并重训 v2；应用层加"连续 5 帧同类去抖"。

## 量化参数（目标机 NPU 部署用，待做）

- 历史PC侧计划为INT8量化（Ryzen AI VitisAI EP）；校准只能选训练部分或独立代表性图片，禁止使用test集选择尺度、阈值或模型方案。100~200张仅为历史候选数量，不是充分性验收标准。
- 量化前后 mAP 对比将补充至本文件与 `4_metrics/metrics.csv`

## 2026-09-14：Zynq-7020部署与数据现状

当前工作聚焦PS+PL独立YOLO检测，PC扩展任务暂不实施。采用复用INT8 GEMM、向量/非线性算子及描述符调度；首版分类处理、DFL和NMS放PS。正式路线和数值/资源/视频隔离合同见[硬件部署计划r3](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)。这不是已完成的硬件模型或NPU部署。

已取得同项目v6 YOLOv8公共包：1893张416×416，train1765/valid59/test69，七类ID顺序匹配。ZIP大小29,538,322字节，SHA-256=`89b828c8bfad60243f790d58d896b5189a7ac6f3c498629fdd931b8179e378b5`。来源、CC BY 4.0元数据、逐类计数和检查边界见[下载与结构校验](../../4_metrics/logs/2026-09-14_gesture_dataset_download_run01/REPORT.md)。ZIP和图片只保存在本地，不上传本次PR。

`PACKAGE_STRUCTURE_PASS`不等于标签语义、框质量、去重/泄漏或新精度通过。上方69张测试指标属于历史训练记录，本轮未重测。仍需独立路径配置、真实场景补充、训练部分校准名单、640/416/320同集FP32对照、硬件一致整数参考与golden。测试集不能参与校准或方案选择；valid/test少数类样本极少，不能凭总体mAP掩盖弱类问题。

原PT/ONNX未修改；`INTEGER_REFERENCE_NOT_IMPLEMENTED / QUANTIZATION_NOT_RUN / RTL_NOT_IMPLEMENTED / BOARD_NOT_RUN`。
