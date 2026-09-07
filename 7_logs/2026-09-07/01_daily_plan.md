# 2026-09-06/07 工作区迁移 + ADV7511 颜色根因 + AI 侧手势通路（合并日志）

> 说明：本日区间为开发机迁移与 AI 侧爆发期，两日合并记录。开发机从旧环境迁移到 `E:\Work\Projects\AMD_proj\FPGA_competition_2026`（仓库根目录即项目根目录），已安装 Vivado 2025.2 ML Standard（器件仅 Zynq-7000 家族）。

## 当前判断

1. **FPGA 侧**：队友在旧工作区已将 HDMI 彩条调通（ADV7511 配置表 YCbCr422 修正 + Style 修正 + CSC 路线，见 `2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table.sv` V1.8，含写后读回校验），工程以 zip 交付。本机已将队友版本整体合入 `2_fpga/`（备份在本地 `0_assets/_backup_2fpga_src_20260906/`，不入库）。
2. **ADV7511 颜色问题根因（本机分析，供复测参考）**：HWUG Table 6/7 的 4:2:2 输入映射受 `R0x48[4:3]`（对齐）与 `R0x16[3:2]`（Style，注意寄存器值与手册编号不一一对应）双重控制，且 EES-331 数据线仅接 ADV7511 D[15:0]。历史上 0x16=0xB9（Style 位=10）使芯片到 D[23:16] 读 Y（板上悬空）导致纯色彩条全错。队友最终方案为 CSC 直出 RGB，绕开该问题，板测已验证。
3. **AI 侧**：手势模型 v1（YOLOv8n，Roboflow Hand-Gesture v6 数据集 7 类，train 1765）已训练完成；PC 全链路（摄像头→JPEG→UDP→ONNX Runtime CPU 推理→检测 JSON 回传→预览画框）实测通过。UDP 协议 v1 定稿于 `1_docs/interface.md`。

## 今日主要目标（已完成情况）

1. ✅ 仓库合并为主项目根目录；补齐完整 git 历史（原为浅克隆）。
2. ✅ 队友 `2_fpga` 验证版本合入（含新增 `rtl/HDMI`、`rtl/data_pre`、`rtl/fr_display`、`ov5640_data_cap` 资产与 display_test 工程、新测试台）。
3. ✅ 手势模型训练与实测（见验证记录）。
4. ✅ UDP 协议 v1 定稿（报文、分片、心跳、异常处理策略），写入 `1_docs/interface.md`。

## 优先任务（下一步）

- **P0**：FPGA 队友在 2025.2 环境复现基线 bit（Reset Runs → Generate Bitstream → 板测彩条），随后启动 PS 显示验证。
- **P0**：FPGA 队友按 `1_docs/interface.md` 实现 lwIP 发帧端（先发固定测试 JPEG，AI PC 侧 `inference_server.py` 已可直接收帧）。
- **P1**：AI 侧自采 Left/Right/Thumbs Down 补充数据（各 ≥100 张）后重训 v2。
- **P1**：舵机臂采购下单（闭环执行机构）。
- **P2**：中期申请报告（截止 2026-10-09）成稿，素材已就绪。
