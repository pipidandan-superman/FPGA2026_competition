# 验证记录 2026-09-06/07

## 已验证（含证据）

| 编号 | 项目 | 结果 | 证据 |
|---|---|---|---|
| V-A1 | 手势模型 test 集评估（69 张未参与训练） | PASS（有保留）：mAP50=0.730，mAP50-95=0.438，P=0.668，R=0.743 | `D:\gesture_pipeline\runs\detect\val`；混淆明细见下 |
| V-A2 | 分类别 mAP50 | Stop 0.995 / Thumbs up 0.967 / Up 0.956 / Down 0.928 / **Left 0.511 / Right 0.418 / Thumbs Down 0.335**（弱项为成对易混类，数据不足） | 同上 |
| V-A3 | PC 全链路实时实测（摄像头→JPEG→UDP→ONNX CPU→JSON 回传） | PASS：27.5s 会话 349 帧，7 类中 6 类在对应时间窗连续命中（Stop 37 帧、Thumbs Down 38、Thumbs up 28、Right 23、Down 20、Up 19） | `D:\gesture_pipeline\datasets\session_log.csv` + `session_snaps\` |
| V-A4 | 实测延迟（ONNX CPU） | P50 62ms / P95 118ms / 最大 1934ms(首帧预热) | session_log.csv |
| V-A5 | ONNX 导出与 ONNX Runtime 推理一致性 | PASS | `scripts/test_yolo.py` 输出 |
| V-A6 | MediaPipe HandLandmarker 基线 | PASS（thumb_up 样例检出 1 手，关键点/左右手正常） | `scripts/test_mediapipe.py` |
| V-A7 | ONNX 推理后端 | 固定 CPUExecutionProvider（onnxruntime-gpu 因缺 CUDA13/cuDNN9 运行库不可用，已卸载；小模型 CPU 足够） | 2026-09-07 服务端日志 |

## 已知问题（待复验/待修）

| 编号 | 问题 | 根因分析 | 计划 |
|---|---|---|---|
| K1 | **Left 手势实测失败**（整个时间窗仅 1 帧，conf 0.59） | 指向身体对侧时食指轮廓透视缩短，与训练集侧身素材域差异大；且训练集 Left/Right 样本不足 | 自采补充数据重训 v2；演示时侧身做手势 |
| K2 | Thumbs up/Thumbs Down 边界串扰（各 3~4 帧） | 手势切换过渡帧 | 应用层去抖：连续 5 帧同类才触发指令 |
| K3 | ADV7511 颜色根因分析（Style 位与手册编号不对应、R0x48 对齐位） | 本机文档分析结论，**未板测复验**——队友 CSC 路线已板测通过，此分析留作备援路线资料 | 维持队友方案；如需回退 422 直通路线时按分析复验 |
| K4 | 2025.2 环境下基线 bit 复现 | 尚未在本机执行 Reset Runs→重建→板测 | P0，FPGA 队友执行 |

## 证据归档说明

- 本机 AI 侧证据在 `D:\gesture_pipeline\`（数据集/权重体积大，不入仓库）；关键数值已录入本文件，后续正式指标迁入 `4_metrics/metrics.csv`。
- ADV7511 手册关键页截图见 `7_logs/2026-09-07/`（Table 7 与 EES-331 SD/ETH 章节）。
