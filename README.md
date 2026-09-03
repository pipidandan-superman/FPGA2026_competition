# 小月文刀队｜AMD 具身智能赛道

本项目面向全国大学生嵌入式芯片与系统设计竞赛 2026，当前选择：

> **AMD 具身智能赛道（赛题 3.2）**

系统架构：

> **AMD Ryzen AI PC（上位机）+ AMD FPGA/Zynq 板卡（实时控制）异构协同**

## 项目目标

构建一套具身智能系统，在真实环境中完成感知、决策和执行的闭环。Ryzen AI PC 负责端侧 AI 推理、任务规划、人机交互和上层决策；FPGA/Zynq 板卡负责高速传感接入、实时处理、I/O 扩展、运动控制或低延迟数据桥接。两者共同完成一项真实物理任务。

## 赛道核心要求

### 必须满足

- 上位机必须为 AMD Ryzen AI PC，型号不限；
- 必须包含基于 AMD 器件的 FPGA/Zynq 设计，并说明其在系统中的实际作用；
- FPGA/Zynq 不能仅作为普通 USB、串口或 GPIO 转接板使用；
- 必须给出 AI PC 与 FPGA/Zynq 的通信方式、数据流与时间同步方案；
- AI 决策到物理执行的闭环必须完整，至少完成一项真实物理任务。

### 选型方向（可选其一或自行提出）

- 智能移动机器人导航与避障
- 视觉识别与自动分拣
- AI 机械臂抓取与控制
- 高清视觉检测与实时执行
- 多传感器融合与运动控制
- 人机交互驱动的智能执行系统
- 工业场景下的安全监测与实时控制

## 平台与工具链

| 组件 | 说明 |
|------|------|
| 上位机 | AMD Ryzen AI PC（型号待定/自有设备） |
| FPGA 板卡 | Zynq-7000 XC7Z020（基于现有 ViTA 工程） |
| 开发工具 | AMD Vivado / Vitis 2025.2 |
| AI 推理 | Ryzen AI PC 端侧推理（ROCm 7.14.0+） |
| 通信方式 | 待确定（Ethernet / UART / PCIe 等） |

## 计划完成范围

### 基础功能

- AI PC 端：本地 AI 推理与任务决策
- FPGA/Zynq 端：实时 I/O 控制、传感数据接入或图像预处理
- 两端通信与数据同步
- 至少一项真实物理任务的完整闭环

### 高阶功能

- 端到端延迟优化（P95/P99 与最大值）
- 多传感器融合
- FPGA/Zynq 可量化贡献提升
- 可复用 Skill 与标准化工作流封装

## 现有工程基础

已有三个 Xilinx Zynq-7010 工程可作为实时控制链路和软硬件协同设计参考：

| 工程 | 路径 | 说明 |
|------|------|------|
| OV5640 + HDMI 显示 | `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true` | 纯 PL 视频采集与显示链路 |
| PS 端神经网络 | `E:\FPGA_Project\2020_2\cnn_PS_final` | 手写数字识别，NN 推理运行在 ARM PS 端 |
| PS+PL 神经网络 | `E:\FPGA_Project\2020_2\cnn_PS_PL_ACC_final\cam_vdma_hdmi_true` | 手写数字识别，PL 硬件加速 + OV5640/HDMI 视频链路 |

现有资产包括 OV5640 采集、VDMA 帧缓存、HDMI 输出、PL 图像预处理、BRAM/DDR 数据交换和 PS+PL CNN 硬件加速经验。

## HDMI / ADV7511 适配进展

EES-331 显示适配按 **480p60（640×480@60，25.175 MHz）** 完成 RTL 与 ModelSim 仿真。FPGA 不再直接输出五倍频像素时钟和 TMDS，而是将 RGB888 转换为 **BT.709 YCbCr422**，通过 ADV7511 寄存器配置和 16 位视频总线输出。

### 活跃模块层级

```text
hdmi_out_adv7511
├─ rgb2ycbcr422
└─ adv7511_cfg_top
   ├─ adv7511_controller
   ├─ adv7511_iic_data_xfer
   └─ iic_protocal
```

源码位于 `2_fpga/0_diaplay_test/rtl/hdmi_new`，底层 IIC 协议复用 `2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v`。测试台位于 `2_fpga/0_diaplay_test/sim/hdmi_new`。

### 验证状态

| 项目 | 结果 |
|------|------|
| 视频像素检查 | PASS，16/16 |
| ADV7511 寄存器写入检查 | PASS，18/18 |
| IIC 首个 START | 约 120.843 ms |
| 最终证据 | `4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/modelsim_transcript.txt` |
| Vivado 综合 | 未验证 |
| 时序收敛 | 未验证 |
| EES-331 板级显示 | 未验证 |

当前结论只覆盖 RTL/ModelSim 行为验证；综合、时序和板级显示验证完成前，不将硬件显示描述为已实现。

## 归档目录

```text
competition/
├─ README.md
├─ 1_docs/      # architecture/interface/hardware_setup 与赛题、平台文档
├─ 2_fpga/      # RTL/HLS、构建脚本、.bit/.xsa/.hwh、综合实现报告
├─ 3_host/      # 模型、上位机应用、部署脚本与清单
├─ 4_metrics/   # metrics.csv、原始日志、测试脚本、截图/波形证据
├─ 5_report/    # 设计报告、复现说明、归档清单
├─ 6_skill/     # 可复用 Skill 与工具说明
└─ 7_logs/      # 内部工程日志（不替代 4_metrics/ 下的提交证据）
```

核心必报指标（赛题 3.2.4.3）：

1. 任务闭环成功率
2. 端到端响应延迟
3. AI 任务效果和推理性能
4. FPGA/Zynq 的量化贡献
5. AI PC 与 FPGA/Zynq 的通信性能

## 当前状态

- AMD 具身智能赛道已确定；
- GitHub 私有仓库已创建并同步；
- 现有 Zynq 工程已完成初步资产盘点；
- 已按赛道归档结构建立目录及必要模板；
- EES-331 HDMI 480p/ADV7511 RTL 和 ModelSim 整体仿真已完成；
- Vivado 综合、时序分析和板级显示验证尚未开始；
- 具体应用场景、Ryzen AI PC 机型、AI 推理部署和两端通信方案仍在推进中。

## GitHub

远程仓库：<https://github.com/pipidandan-superman/FPGA2026_competition>

## 开发原则

1. 区分赛题文件中的要求、当前工程已验证事实和未来计划。
2. 每次验证保存完整原始日志，不以摘要替代证据。
3. 先完成单任务实时闭环，再评估多任务和多传感器扩展。
4. 不将未通过综合、时序和板级验证的功能描述为已实现。
