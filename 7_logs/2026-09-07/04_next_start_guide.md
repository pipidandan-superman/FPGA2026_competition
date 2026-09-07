# 下次开工指引 2026-09-07

## 环境速查

- 本机 Vivado：桌面快捷方式 "Vivado 2025.2"，或 `E:\WorkApps\Xilinx\Vivado_2025_2\2025.2\Vivado\bin\vivado.bat`（勿与桌面旧 Vivado 2020.2 混淆）。
- AI 环境：`D:\gesture_pipeline\venv\Scripts\python.exe`；激活后脚本在 `D:\gesture_pipeline\scripts\`。
- 推理服务：`venv\Scripts\python.exe scripts\inference_server.py`（监听 UDP 0.0.0.0:8888，协议见 `1_docs/interface.md`）。

## FPGA 队友下一步（按序）

1. 打开 `2_fpga\1_zynqtest_2025\project_1\project_1.xpr`（2025.2），Reset Runs → Generate Bitstream → 烧板看彩条（**白黑红蓝绿**，SW0=0）；LED 上电 A5 签名、LED6:0=R0x16 读回值（预期 0x38）。
2. 结果记入 `7_logs/2026-09-07/`（或新日期目录）并更新 HANDOFF。
3. PS 显示验证（VDMA 路线，参考 `1_docs/Zynq_PS7_Config_Report.md` 与 HANDOFF 2026-09-04 计划）。
4. 按 `1_docs/interface.md` 实现 lwIP 发帧端：第一步先发一张固定测试 JPEG 到 AI PC `192.168.10.1:8888`（AI PC 端 inference_server 已就绪，收到即回检测 JSON）；第二步接 OV5640 实时流；第三步测丢包/延迟。

## AI 侧下一步

1. 自采手势数据（重点 Left/Right/Thumbs Down 各 ≥100 张，其余类各补 30 张；同一摄像头、多光照背景），标注后与 Roboflow v6 合并重训 v2。
2. 训练命令：`yolo detect train model=D:/gesture_pipeline/models/yolov8n.pt data=<data.yaml> epochs=60 imgsz=640 batch=16 device=0`。
3. 中期申请报告（10-09 截止）：以 `1_docs/proposal_draft_midterm.md` 为骨架填内容，实测数据从 `7_logs/2026-09-07/03_validation_summary.md` 搬运。

## 共同事项

- 舵机臂采购下单（4-6DOF 套件）。
- UM790 Pro 到位结论 deadline 2026-09-20。
- 提交节奏：每完成一个里程碑 commit 一次。
