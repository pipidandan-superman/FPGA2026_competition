# 2026-09-01 每日工程日志：赛题二项目启动整理

## 当前项目判断

此前项目主线曾确定为：

> 赛题二：基于紫光同创 FPGA 的任意角度的畸变矫正。（已转为历史规划）

此前目标硬件为：

> RK3568_MES2L100H（RK3568J + Logos-2 FPGA）。（不再作为当前主线）

## 方向变更记录（最新）

经用户确认，当前主线调整为：

> AMD 具身智能赛道（3.2）：Ryzen AI PC + AMD FPGA/Zynq 协同完成真实物理任务。

此前的紫光赛题二方案保留为历史规划，不再作为当前主线执行。

ViTA 项目使用的开发板对应 `XC7Z020 / Zynq-7020`。按赛题指南的器件分类，它可作为 AMD FPGA/Zynq 端进行原型和初步验证；正式参赛还必须补齐 AMD Ryzen AI PC、真实物理执行机构及合规性确认。

现有工程来自 Xilinx Zynq/Vivado/Vitis，包含 OV5640、VDMA、HDMI、PL 图像预处理以及 PS+PL CNN 加速。它可作为视频链路和软硬件协同设计基线，但尚未完成 Logos-2/PDS 移植，也尚未实现畸变矫正算法。

## 今日主要目标

1. 固化赛题二和 RK3568_MES2L100H 作为当前项目方向。
2. 明确现有工程可复用资产与赛题二新增功能边界。
3. 建立本项目唯一日志根目录：

   `C:\Users\Administrator\Desktop\competition\1_log`

4. 整理四份规范化日记文件，供后续连续记录使用。

## 优先任务

- 完成真实 OV5640 样张采集和相机标定参考流程。
- 用 OpenCV 建立软件畸变矫正黄金参考。
- 确认 PDS、Logos-2 FPGA、RK3568J、摄像头和 HDMI 的接口迁移方案。
- 再设计 FPGA 定点坐标映射和双线性插值流水线。
- 将多路视频和神经网络处理作为后续可选扩展，不作为当前基础完成承诺。

## AMD 具身智能当前主线

- 实验室现有 `XC7Z020 / Zynq-7020` 板卡作为当前 FPGA/Zynq 端原型平台。
- 普通 PC 可暂时代替 Ryzen AI PC 做算法和通信联调，但相关结果必须标注为原型验证，不作为正式 AMD 赛道硬件证据。
- 正式提交前需使用 AMD Ryzen AI PC，并按当届公告确认 Zynq-7020 开发板的可接受性。
- 机械臂优先采用“板卡/主控与机械臂控制器通信”的方案，不直接驱动商用机械臂关节电机。

## 明确非目标

- 今日不修改 E 盘原始工程源码。
- 今日不宣称多路视频或神经网络处理已经实现。
- 今日不把 Xilinx 工程直接视为 Logos-2/PDS 通过版本。
- 今日不上传未清理的 Vivado/Vitis 缓存、网表和临时文件。

## 今日产物

- 本目录下四份规范化工程日志。
- 选题二的需求、验证门禁和下一步启动条件。
- `C:\Users\Administrator\Desktop\competition\README.md` 项目总说明，并与 GitHub 仓库 README 对齐。
- GitHub 私有仓库已创建：
  `https://github.com/pipidandan-superman/rk3568-logos2-distortion-correction`
