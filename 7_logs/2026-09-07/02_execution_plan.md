# 执行记录 2026-09-06/07

## 工作区与工具链

- 项目根目录迁至 `E:\Work\Projects\AMD_proj\FPGA_competition_2026`（GitHub 仓库 `FPGA2026_competition` 的完整克隆，历史 32 commits 已补全）。
- Vivado 2025.2 ML Standard 安装于 `E:\WorkApps\Xilinx\Vivado_2025_2`（仅 Zynq-7000 器件家族）；桌面快捷方式修复（原开始菜单链接指向不存在的路径）。
- ADV7511 四份官方资料归档 `1_docs/pdf/adv7511/`（HWUG/Datasheet/UG-235/UG-556）；EES-331 手册确认板上 micro SD（J15，PS SD0/MIO40-45）与 PS 以太网（ENET0，88E1518 PHY）。

## 2_fpga 合入（队友验证版本）

- `0_diaplay_test`：RTL 全量更新（hdmi_new V1.8：`adv7511_init_table.sv` 取代 `_pkg.sv`，含 CSC 寄存器块与读回校验；新增 `rtl/HDMI` TMDS 直出路径、`rtl/data_pre`、`rtl/fr_display`、`ov5640_data_cap`）；`proj/display_test_zynq7020_school` 工程更新；`vitis/display_test_plat` 与 app_component 更新（工作区元数据不入库）。
- `1_zynqtest_2025`：以 zip 解压方式本地恢复（含 ILA），按团队约定工程目录不入库。
- 复测纪律沿用 HANDOFF：任何源码变更后 Reset Runs → 重新出 bit → 校验时间戳后再板测。

## AI 侧（3_host）

- 环境：`D:\gesture_pipeline`（venv Python 3.11 + ultralytics 8.4 + onnxruntime 1.29 CPU + torch 2.11.0+cu128 RTX 5070 Ti 可用）。
- 数据：Roboflow `yolo-zxvpk/hand-gesture-r7qgb` v6（CC BY 4.0），7 类，train 1765 / valid 59 / test 69。
- 训练：yolov8n 微调 60 epochs，产物 `runs/gesture_v1/weights/best.pt` 及 ONNX。
- 脚本：`scripts/{camera_test,inference_server,frame_sender,test_yolo,test_mediapipe,download_roboflow}.py`。
- 协议 v1 定稿于 `1_docs/interface.md`（分片帧上行 + JSON 结果下行 + 1Hz 心跳 + 异常处理表）。
