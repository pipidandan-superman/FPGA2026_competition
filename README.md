# 小月文刀队｜AMD 具身智能赛道

本项目面向全国大学生嵌入式芯片与系统设计竞赛 2026，当前选择：

> **AMD 具身智能赛道（赛题 3.2）**
> **作品名称：锐眼·智行——具身智能分拣**
> **应用场景：视觉识别与自动分拣**

系统架构：

> **AMD Ryzen AI PC（上位机"大脑"）+ AMD Zynq-7000 FPGA（实时"小脑"）异构协同**

## 项目目标

构建一套具身智能视觉分拣系统，在真实环境中完成"感知→决策→控制→执行"的完整闭环。Ryzen AI PC 在本地运行 YOLO 目标检测模型（ROCm），识别目标物体并规划抓取策略；Zynq FPGA 在 PL 端完成图像采集与预处理、CNN 特征提取加速、多轴舵机精确控制与硬件级安全保护。两者通过 Ethernet 通信，协同完成机械臂自动抓取与分拣。

## 系统分工

| 角色 | 平台 | 职责 |
|------|------|------|
| 大脑（AI 决策） | AMD Ryzen AI PC | YOLO 目标检测推理（mAP ≥ 0.7）、位姿估计、抓取策略规划、人机交互界面 |
| 小脑（实时控制） | AMD Zynq-7000 FPGA | OV5640 图像采集、PL 端图像预处理、CNN 加速推理、多轴舵机 PWM 控制、轨迹插值、HDMI 实时显示、硬件安全逻辑 |
| 通信桥梁 | Ethernet（UDP） | 双向数据流：检测特征上行、控制指令下行、状态反馈上行；RTT < 5 ms |

## 闭环链路

```
摄像头感知 → FPGA 预处理与 CNN 推理 → 通信上传 → AI PC 识别与规划
    → 控制指令下发 → FPGA 轨迹插值 → 多轴舵机执行 → 机械臂抓取
    → 视觉反馈验证 → 循环下一目标
```

## 赛道核心要求

### 必须满足

- 上位机必须为 AMD Ryzen AI PC，型号不限；✅ 已规划
- 必须包含基于 AMD 器件的 FPGA/Zynq 设计，并说明其实际作用；✅ CNN 加速 + 多轴控制 + HDMI 显示
- FPGA/Zynq 不能仅作为普通 USB、串口或 GPIO 转接板使用；✅ PL 端并行计算与实时控制不可由软件替代
- 必须给出 AI PC 与 FPGA/Zynq 的通信方式和数据流；✅ Ethernet + 协议帧格式
- AI 决策到物理执行的闭环必须完整，至少完成一项真实物理任务。✅ 机械臂抓取与分拣

## 平台与工具链

| 组件 | 说明 |
|------|------|
| 上位机 | AMD Ryzen AI PC（型号待定/自有设备） |
| AI 推理 | ROCm 7.14.0+，YOLOv8-n 端侧部署 |
| FPGA 板卡 | 依元素 EES-331（Zynq-7000 XC7Z020 CLG484-1） |
| FPGA 开发工具 | AMD Vivado / Vitis 2020.2（赛题不限制版本） |
| 仿真工具 | ModelSim |
| 通信方式 | Ethernet（UDP，RTT < 5 ms） |
| 机械臂 | 4-6 自由度舵机机械臂（待采购） |
| 摄像头 | OV5640（DVP 并行接口，已有） |
| 显示器 | HDMI 480p60 通过 ADV7511（已有） |

## 核心量化指标（赛题 3.2.4.3 必报）

| 指标 | 目标 |
|------|------|
| 任务闭环成功率 | ≥ 90%（50 次重复测试） |
| 端到端响应延迟 | P50/P95/P99/最大值，待标定 |
| AI 任务效果 | mAP@0.5:0.95 ≥ 0.7 |
| AI 推理延迟 | ≤ 30 ms / 帧（batch=1） |
| FPGA CNN 推理延迟 | ≤ 5 ms / 帧 |
| FPGA vs. CPU 加速比 | ≥ 5× |
| AI PC ↔ FPGA RTT | ≤ 5 ms |

详细指标与测量方式见 `1_docs/设计方案_具身智能视觉分拣.md` 第 5 节。

## 现有工程基础

| 工程 | 路径 | 说明 | 复用状态 |
|------|------|------|----------|
| OV5640 + HDMI 显示 | `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true` | 纯 PL 视频采集与显示链路 | 直接复用 |
| PS 端神经网络 | `E:\FPGA_Project\2020_2\cnn_PS_final` | 手写数字识别，NN 推理运行在 ARM PS 端 | 架构参考 |
| PS+PL 神经网络 | `E:\FPGA_Project\2020_2\cnn_PS_PL_ACC_final` | PL 硬件加速 + OV5640/HDMI 视频链路 | CNN 加速器架构复用 |

## HDMI / ADV7511 适配进展

**当前冻结基线：`camera-hdmi-visual-pass-20260907`。** OV5640 画面已通过 S2MM 写入 DDR、MM2S 读出并经 HDMI 输出，板端三张照片归档为 `BOARD_VISUAL_PASS`；完整 UART 验收仍待用同一 BIT + 同一 ELF 复测。

EES-331 显示适配按 **480p60（640×480@60，25 MHz 像素时钟）** 完成 RTL 与 ModelSim 仿真。当前 ADV7511 输出链路使用 **BT.601 limited-range CSC**、`R0x15=01`、`R0x16=38`、`R0x48=08`、16 位 YCbCr422 逻辑数据和 EES-331 板级字节交换。

### 活跃模块层级

```text
hdmi_out_adv7511_v1_0
├─ rgb2ycbcr422
└─ adv7511_cfg_top
   ├─ adv7511_controller
   ├─ adv7511_iic_data_xfer
   └─ iic_protocal
```

源码位于 `2_fpga/0_diaplay_test/rtl/hdmi_new`；当前 BD 顶层为 `hdmi_out_adv7511_v1_0`。下载冻结 BIT 并加载配套 ELF 后，必须手动复位一次摄像头采集，复位后实时画面才能正常稳定显示；这是当前冻结恢复流程的必要步骤。详细版本说明见 `2_fpga/0_diaplay_test/doc/camera_hdmi_correct_version_2026-09-08.md`。

### 验证状态

| 项目 | 结果 |
|------|------|
| 视频像素检查 | PASS，16/16 |
| ADV7511 寄存器写入检查 | PASS，18/18 |
| Verilog 顶层复现证据 | `4_metrics/logs/2026-09-03_hdmi_top_verilog_run22` |
| BD Module Reference | PASS |
| EES-331 XDC 引脚检查 | PASS，23/23 |
| PS UART 通信 | 板级 PASS |
| Vivado 实现 | PASS，11060/11060 nets fully routed，0 routing errors |
| 时序收敛 | PASS，WNS 9.510 ns，TNS 0.000 ns，constraints met |
| PS VDMA + HDMI 彩条 | BOARD VISUAL PASS |
| OV5640 + PS VDMA + HDMI | BOARD VISUAL PASS，2026-09-07 |
| OV5640 + PS VDMA 完整 UART 验收 | 待复测，同一冻结 BIT + ELF |
| 主工程 Zynq ENET0 配置等效性（vs 回环工程 21 项 PCW） | PASS，2026-09-08 |
| 主工程 lwIP UDP 回环 + 摄像头 HDMI 同板共存 | BOARD PASS（`MAIN_ETH_LOOPBACK_PASS`），2026-09-08 |
| 自定义 UDP 视频协议 + 上位机（Python/exe）设计 | 文档交付，2026-09-08 |
| 主工程 →PC UDP 视频流 B1（1 fps 彩条，640 包/帧，921.6 KB/帧） | BOARD PASS（`UDP_TX_B1_PASS`），2026-09-08 |
| 主工程 →PC 摄像头实时画面 C1（快照选槽，~5 fps） | BOARD PASS（`UDP_CAMERA_C1_PASS`），2026-09-08 |
| C1.1/C1.2 质量优化（双缓冲 + 分块拷贝 + 突发整形） | BOARD PASS（`C12_QUALITY_PASS`：1533+ 帧丢帧=0/CRC 错=0 @4.77 fps），2026-09-08 |

## 归档目录

```text
competition/
├─ README.md
├─ 1_docs/      # 设计方案、架构、接口、硬件说明与赛题文档
├─ 2_fpga/      # RTL/HLS、构建脚本、.bit/.xsa/.hwh、综合实现报告
├─ 3_host/      # 模型、上位机应用、部署脚本与清单
├─ 4_metrics/   # metrics.csv、原始日志、测试脚本、截图/波形证据
├─ 5_report/    # 设计报告、复现说明、归档清单
├─ 6_skill/     # 可复用 Skill 与工具说明
└─ 7_logs/      # 内部工程日志（不替代 4_metrics/ 下的提交证据）
```

## 当前状态

- AMD 具身智能赛道已确定，应用场景已冻结为**视觉识别与自动分拣**；
- 设计方案已固化至 `1_docs/设计方案_具身智能视觉分拣.md`；
- HDMI ADV7511 RTL、实现、时序和板级显示已完成；
- PS UART 板级通信已验证；
- 2026-09-07 冻结 OV5640 → VDMA → DDR → VDMA → HDMI 可视化显示基线；
- 2026-09-08 主工程 PS 使能 ENET0（MIO16..27 + MDIO 52..53 + PHY 复位 MIO47），新 XSA/BIT 与 V3.1 固件（lwIP RAW UDP 回环 + 原 VDMA/HDMI 逻辑）板级验证通过：UDP 回环 `RX=TX` 且摄像头 HDMI 显示正常；
- 2026-09-08 板→PC UDP 视频流 B1 通过（1 fps 彩条、640 包/帧、921.6 KB/帧、丢帧/CRC=0），配套图形接收端 `EES331_UDP_Viewer.exe` 与协议设计文档；
- 2026-09-08 **C1.2 质量版固化**（`udp-camera-c12-pass-20260908`）：双缓冲快照 + 分块拷贝 + 突发整形，1533+ 帧丢帧=0/CRC 错=0 @4.77 fps，配对 BIT `7CB11F7D...` + ELF `6EB0097C...` + XSA `30644B31...`；
- CNN PS+PL 加速架构已有历史工程基础；
- 下一步：相机快照接入（C1，前置：排查 S2MM 相机流错误）→ 提速 5/15 FPS（C2）→ 多轴 PWM 控制器开发 → 通信协议实现 → YOLO 部署 → 联调。

## GitHub

远程仓库：<https://github.com/pipidandan-superman/FPGA2026_competition>

## 开发原则

1. 区分赛题文件中的要求、当前工程已验证事实和未来计划。
2. 每次验证保存完整原始日志，不以摘要替代证据。
3. 先完成单任务实时闭环，再评估多任务和多传感器扩展。
4. 不将未通过综合、时序和板级验证的功能描述为已实现。
