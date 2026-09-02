# 小月文刀队｜RK3568_MES2L100H 任意角度实时视频畸变矫正

本项目面向全国大学生嵌入式芯片与系统设计竞赛 2026 FPGA 创新设计赛道，当前选择：

> **选题二：基于紫光同创 FPGA 的任意角度的畸变矫正**

目标平台：

> **RK3568_MES2L100H（RK3568J + Logos-2 FPGA）**

## 项目目标

构建一套面向机器视觉、智能交通和工业检测的实时视频畸变矫正系统。系统以摄像头或 HDMI 视频作为输入，在 FPGA 端完成视频缓存、坐标映射、定点化运算和双线性插值，在 RK3568J 端完成相机标定参数、姿态参数和系统配置管理。

## 计划完成范围

### 基础功能

- 单路摄像头/HDMI 视频采集、缓存与显示；
- 二阶径向畸变和切向畸变模型；
- FPGA 定点坐标映射；
- 双线性插值、边界和空洞处理；
- 实时输出以及端到端延迟、帧率测试。

### 高阶功能

- 通过上位机指令或姿态传感器动态更新旋转/倾斜参数；
- 任意角度下的动态畸变矫正和仿射变换；
- 面向强光、夜间等场景的自适应图像增强；
- 直线度误差、MTF50/SFR、资源占用和时序分析。

### 可选扩展

系统将预留多路视频并行处理和神经网络推理接口。在基础及高阶功能稳定通过后，再根据 RK3568_MES2L100H 的资源、时序和实际测试结果决定是否加入。多路视频与神经网络属于探索性扩展，不作为当前已完成能力或基础验收前提。

## 现有工程基础

已有 Xilinx Zynq/Vivado/Vitis 工程可作为视频链路和软硬件协同设计参考：

- `E:\FPGA_Project\2020_2\cnn_PS_PL_ACC_final\cam_vdma_hdmi_true`
- `E:\FPGA_Project\2020_2\cnn_PS_final\cam_vdma_hdmi_true`

现有资产包括 OV5640、VDMA、HDMI、PL 图像预处理、BRAM/DDR 数据交换和 PS+PL CNN 加速经验。Xilinx 工程不能直接视为 Logos-2/PDS 已通过版本，后续需要完成平台迁移和验证。

## AMD 赛题二归档目录

```text
competition/
├─ README.md
├─ 1_docs/      # architecture/interface/hardware_setup 与赛题、平台文档
├─ 2_fpga/      # RTL/HLS、构建脚本、.bit/.xsa/.hwh、综合实现报告
├─ 3_host/      # 模型、上位机应用、部署脚本与清单
├─ 4_metrics/   # metrics.csv、原始日志、测试脚本、截图/波形证据
├─ 5_report/    # 设计报告、复现说明、归档清单
├─ 6_skill/     # 可复用 Skill 与工具说明（含本地日志 Skill 副本）
└─ 7_logs/      # 内部工程日志（不替代 4_metrics/ 下的提交证据）
```

赛题二 3.2.5.5 的推荐结构已映射到本仓库。`4_metrics/metrics.csv` 中的每条指标必须能追溯到
`4_metrics/logs/`、`4_metrics/scripts/` 或 `4_metrics/evidence/` 中的原始证据；尚未完成的项目保留
占位说明，不填写猜测值。

内部计划、执行记录和交接记录统一放在顶层：

`C:\Users\Administrator\Desktop\competition\7_logs`

每个日期目录使用：

- `01_daily_plan.md`
- `02_execution_plan.md`
- `03_validation_summary.md`
- `04_next_start_guide.md`

## 当前状态

- 赛题二和 RK3568_MES2L100H 已确定；
- GitHub 私有仓库已创建；
- 现有 Zynq 工程已完成初步资产盘点；
- 已按 AMD 赛题二归档结构建立 `1_docs/2_fpga/3_host/4_metrics/5_report/6_skill` 目录及必要模板；
- Logos-2/PDS 移植、真实相机标定和 FPGA 畸变矫正 RTL 尚未开始；
- 多路视频和神经网络功能仍处于可选扩展阶段。

## GitHub

远程仓库：<https://github.com/pipidandan-superman/rk3568-logos2-distortion-correction>

## 开发原则

1. 区分赛题文件中的要求、当前工程已验证事实和未来计划。
2. 每次验证保存完整原始日志，不以摘要替代证据。
3. 先完成单路实时矫正闭环，再评估多路视频和神经网络扩展。
4. 不将未通过 PDS 综合、时序和板级验证的功能描述为已实现。
