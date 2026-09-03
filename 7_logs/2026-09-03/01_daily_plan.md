# 2026-09-03 日计划

## 当前判断

EES-331 HDMI 末级必须由 FPGA 直驱 TMDS 改为 ADV7511 并行总线驱动。用户已按 Video Timing Controller 截图将首版分辨率固定为 480p，对应 640x480@60、约 25.175 MHz 像素时钟。

## 今日目标

- 按 480p 冻结时钟、时序与 BT.709 颜色空间假设。
- 在 `2_fpga/0_diaplay_test/rtl/hdmi_new` 建立 ADV7511 并口输出 RTL。
- 建立可审查的寄存器初始化表、三段式 I2C FSM 和视频对齐逻辑。
- 建立模块级仿真证据并保持完整原始日志。

## 任务

- [x] 建立 RGB888 转 YCbCr422 流水线。
- [x] 建立 ADV7511 100 kHz I2C 位摆初始化模块。
- [x] 建立顶层 `hdmi_out_adv7511` 与 ODDR 时钟转发。
- [x] 编写模块级 testbench 并执行仿真。
- [x] 将原始仿真输出保存到 `4_metrics`，再更新验证摘要。
- [x] 完成 18 项 ADV7511 寄存器序列完整仿真。
- [x] 完成整体 `hdmi_out_adv7511` ModelSim 仿真。
- [x] 更新 README、新增构建产物忽略规则，并将关键代码与文档选择性推送 GitHub。
- [x] 将 HDMI 测试台和 ModelSim 脚本集中到 `2_fpga/0_diaplay_test/sim`，并完成迁移后回归。
- [x] 复现并记录 `hdmi_out_adv7511` 无法直接加入 BD 的原因。
- [x] 将 HDMI 活跃顶层改为等价 Verilog，并完成 ModelSim 回归和 Vivado Module Reference 检查。
- [x] 按 EES-331 手册补齐 HDMI/ADV7511 引脚约束，并完成 XDC 端口与引脚检查。
- [x] 分析 Vivado `place_design` 失败原因，并保存原始报告与引脚能力证据。
- [x] 按用户确认以方案 A 修复相机 PCLK 时钟布局约束。
- [ ] 执行 BD 集成、综合、实现和时序验证。

## 非目标

- 不修改摄像头、VDMA、DDR、GP0、v_tc 现有链路。
- 不做音频、CEC、HEAC。
- 不在仿真或综合通过前声称板级 HDMI 可用。

## 预期交付

RTL、Verilog 顶层、testbench、EES-331 XDC、原始仿真日志、验证摘要、README 归档说明、BD 集成限制证据和当前顶层 handoff。
- [x] 执行 BD 集成、综合、实现和时序验证。
- [x] 分析 OOC 综合 error 与已通过实现/比特流并存的原因。
- [x] 对照 2020 参考工程生成 OV5640+HDMI BD 关键连线清单。
UART self-test build PASS; board test pending.
UART header dependency removed and rebuild pass.
