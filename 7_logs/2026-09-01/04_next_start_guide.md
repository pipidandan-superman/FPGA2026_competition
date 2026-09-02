# 下一次启动指南

## 唯一日志根目录

从下一次工程会话开始，所有赛题二项目日志、仿真日志、综合日志、板测日志和交接记录统一存放于：

`C:\Users\Administrator\Desktop\competition\1_log`

每个日期建立一个子目录，例如：

`C:\Users\Administrator\Desktop\competition\1_log\2026-09-02`

每个日期目录继续使用：

- `01_daily_plan.md`
- `02_execution_plan.md`
- `03_validation_summary.md`
- `04_next_start_guide.md`

## 下次先读

1. 本目录四份日志。
2. 原始赛题 PDF 第 10–11 页的赛题二要求。
3. PS+PL 工程中的视频输入、缓存、显示和时钟复位模块。
4. GitHub 仓库 README 和本地工程清理清单。

## 第一个具体动作

采集一组真实 OV5640 棋盘格图像，并完成 OpenCV 标定和软件畸变矫正参考结果。

## 不要立即做

- 不要先移植全部 Xilinx Block Design。
- 不要先扩展多路视频。
- 不要先加入神经网络。
- 不要在没有软件黄金参考的情况下编写插值 RTL。

## 成功标准

下次结束时至少应获得：一组可复现标定参数、一张软件矫正参考图、明确的目标分辨率/帧率，以及 FPGA 坐标映射接口定义。

## 当前阻塞条件

此前“确认 RK3568_MES2L100H/PDS”的事项属于历史紫光赛题二主线；当前 AMD 主线应改为确认 ViTA 的 XC7Z020/Zynq-7020 工程状态、摄像头连接方式、HDMI 接口和可用开发资料。

## AMD 3.2 主线下一步

1. 从 ViTA 工程和板卡资料确认 `XC7Z020 / Zynq-7020` 的 FPGA 型号、接口、电平、可用存储和启动方式。
2. 确认实验室是否已有机械臂；若有，先获取控制器型号和通信协议手册。
3. 若暂无机械臂，先用串口/Ethernet 模拟控制器完成指令—反馈闭环，再接入真实设备。
4. 不要先做关节电机底层驱动；优先完成高层控制器通信和安全状态机。
5. 确认一台 AMD Ryzen AI PC，普通 PC 仅用于前期联调。
6. 查询 EES-331 是否有 Linux/PYNQ 官方镜像；若没有，先用 PC Python + Zynq Vitis 通信，不要立即开展 PYNQ 移植。
