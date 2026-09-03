# 2026-09-03 执行计划

1. 以 480p 参数冻结：25.175 MHz、640x480、H total 800、V total 525。
2. 使用项目本地 `rtl-coding-standards` 和全局 `rtl-v-sv-style` 约束文件头、端口、宽度、FSM 和命名。
3. `rgb2ycbcr422` 使用 BT.709 定点系数、三级流水，并只在 DE 有效时维护 Cb/Cr 奇偶。
4. `adv7511_i2c_init` 使用像素时钟分频到约 100 kHz，上电延时不少于 100 ms 后写寄存器表。
5. 顶层输出数据与同步信号再次寄存，`HDMI_CLK` 使用 ODDR 转发。
6. 仿真通过后保存完整控制台输出；若仿真失败，先修复，不更新指标。

## 关键文件

- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\rgb2ycbcr422.sv`
- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table_pkg.sv`
- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_controller.sv`
- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_iic_data_xfer.sv`
- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_cfg_top.sv`
- `E:\competition\2_fpga\0_diaplay_test\rtl\iic\iic_protocal.v`
- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_out_adv7511.v`
- `E:\competition\2_fpga\0_diaplay_test\sim\adv7511_cfg_top_tb.sv`
- `E:\competition\2_fpga\0_diaplay_test\sim\hdmi_out_adv7511_tb.sv`
- `E:\competition\2_fpga\0_diaplay_test\sim\oddr_sim_model.sv`
- `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.srcs\constrs_1\new\pin_zynq7020_cam.xdc`
- `E:\competition\1_docs\pdf\EES-331 User Guide.pdf`

## 整体仿真入口

`E:\competition\2_fpga\0_diaplay_test\sim\run_modelsim.do`

## XDC 校验入口

`E:\competition\4_metrics\logs\2026-09-03_hdmi_xdc_constraint_check_run24\xdc_validation.txt`

## 实现失败分析入口

`E:\competition\4_metrics\logs\2026-09-03_hdmi_impl_place_failure_analysis_run25\place_failure_analysis.md`

## 归档入口

- `E:\competition\README.md`
- `E:\competition\.gitignore`
- GitHub 提交：`92a9bdc`（布局失败分析后的最新归档）

## 风险

ADV7511 寄存器表首版来源于公开推荐配置和方案文档关键项，尚未板级验证。若黑屏，优先检查 I2C ACK、HPD 延时、Cb/Cr 顺序和 DE 对齐。构建产物、仿真库和波形已通过 `.gitignore` 排除。活跃顶层已直接改为 Verilog；正式工程必须移除旧 `.sv` 顶层引用并加入新 `.v` 顶层。XDC 引脚已核对，综合通过但布局失败已定位为 `AA22/cam_pclk_0` 非 CCIO 驱动 BUFG；修复方案等待确认，时序和板级显示尚未验证。
## 2026-09-03 方案 A 执行结果

方案 A 约束和 run26 证据已提交并推送为 `main@7e52714`。
## 2026-09-03 实现与 OOC error 判定

Vivado 2025.2 顶层 `synth_1` 和 `impl_1` 均已完成，`place_design`、`route_design`、`write_bitstream` 成功；`display_test_wrapper.bit` 已生成。布线报告为 10,921/10,921 全连通、0 routing errors；全局 WNS/TNS 为 `10.551/0.000 ns`，WHS/THS 为 `0.023/0.000 ns`。`cam_pclk` 域 WNS/WHS 为 `35.138/0.070 ns`。Messages 中 3 个 `[Common 17-1257] Failed to create directory 'C'.` 来自 OOC 子 run 的 `create_project -in_memory` 阶段，但对应子 run 后续完成并生成 DCP 和完成标记，因此判定为非阻塞项目卫生问题，不影响本次有效比特流。证据见 `4_metrics/logs/2026-09-03_hdmi_ooc_synthesis_error_analysis_run27/ooc_error_analysis.md`。
## 2026-09-03 OV5640+HDMI BD 连线清单

已静态解析参考 `design_1.bd` 和当前 `display_test.bd`，核对 OV5640 配置/采集、Video In、VDMA S2MM/MM2S、HP0/HP1、SmartConnect/AXI Interconnect 控制面、Video Out、VTC、`pix_frame_display` 和新 HDMI 前端连接。清单位于 `E:\competition\2_fpga\0_diaplay_test\doc\bd_ov5640_hdmi_connection_checklist.md`，证据位于 `4_metrics/logs/2026-09-03_bd_connection_check_run28/bd_comparison_evidence.md`。结论：核心采集/DDR/视频输出连线一致；Zynq、50/100 MHz 外部时钟、PS FCLK0、HDMI 架构和 IP 版本差异均为工程基线差异；VDMA S2MM line buffer 当前为 512、参考为 1024，`rom_data` 当前接常量 0，这两项需理解但不阻断当前板测。
UART self-test build PASS; board test pending.
UART header dependency removed and rebuild pass.
UART delay and print headers now declared locally and rebuild pass.
GUI build and run log check pass; serial retry with COM6 open before Run.
XSCT target check complete after direct UART attempt; board power cycle required before next Run.
## 2026-09-03 DDR 根因记录

用户确认 Vitis UART 无输出的根因是 Zynq DDR 型号/配置与 EES-331 板卡不匹配，并已完成配置修改。当前记录只表示根因确认和软件侧修正动作；必须重新导出 XSA、更新 Vitis 平台、重建应用并板级复测后，才能重新评估 UART PASS/FAIL。证据记录见 `4_metrics/logs/2026-09-03_vitis_uart_ddr_root_cause_run31/ddr_root_cause.md`。
## 2026-09-03 最小 UART Raw TX 固件

用户完成 DDR/XSA/platform/BSP 更新并重建后仍无打印。应用已简化为直接写 PS UART1 TX FIFO 的裸 TX 测试，移除 `xil_printf`、BSP 头文件、heartbeat 和 RX echo。程序持续输出固定文本 `UART OK\r\n`。源码更新完成，`app_component.elf` 编译 PASS（text 25600/data 1420/bss 22952），板级复测状态为 PENDING。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/minimal_raw_tx.md`。
## 2026-09-03 XSCT 直接 UART1 分流

Vitis Run 日志只记录连接/断开，未稳定出现完整 `ps7_init + download + con` 流程；用户调试器反汇编显示无效内容。已改用 XSCT 直接执行新 XSA 的 `ps7_init.tcl`。寄存器回读确认 `MIO48_CTRL=0x12E0`、`MIO49_CTRL=0x12E1`、`UART_BAUDGEN=0x7C`、`UART_BAUDDIV=6`，随后直写 `XSCT OK\r\n` 并下载运行最小 ELF。等待用户确认 COM6 是否看到 `XSCT OK` 与重复 `UART OK`。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/direct_xsct_uart_result.md`。
## 2026-09-03 TXFULL 位修正

用户确认 COM6 只出现 XSCT 直写的 `XSCT OK`，应用未输出 `UART OK`。XSCT 停机后确认 CPU 停在 `main.c:9` 的 UART 状态等待循环。根因是最小代码把 `0x00000008` 误当作 TX FULL；该值实际是 `TXEMPTY`，BSP 定义 `TXFULL=0x00000010`。已改为 `bit4`，重新编译 PASS，并通过 XSCT 下载运行。等待 COM6 确认重复 `UART OK`。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/txfull_bitfix_result.md`。
## 2026-09-03 UART Raw TX 板级通过

修正 TXFULL 位后，用户 COM6 出现连续 `UART OK`，XSCT 下载日志显示 ELF 已加载到 `0x00100000` 并运行。结合前一步 `XSCT OK`，COM6/UART1/MIO48/49/115200 波特率硬件路径确认可用；结合 DDR 修正后可正常执行应用。当前结论是 RAW UART TX BOARD PASS；UART RX echo 与 HDMI 显示仍未验证。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/uart_board_tx_pass.md`。
