# 2026-09-03 下一次启动指引

## 先读

1. `E:\competition\HANDOFF.md`。
2. 本日 `03_validation_summary.md`。
3. `E:\competition\1_docs\EES-331_HDMI显示适配修正方案.md`。
4. `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_out_adv7511.v`。
5. `E:\competition\2_fpga\0_diaplay_test\sim\run_modelsim.do`。
6. `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.srcs\constrs_1\new\pin_zynq7020_cam.xdc`。

## 第一动作

整体 ModelSim 仿真已 PASS，活跃顶层已是 `hdmi_out_adv7511.v`，Vivado Module Reference 检查通过，EES-331 HDMI XDC 引脚检查也已 PASS。在 Vivado 中重新加载工程和 XDC，校验 BD 连接后依次执行综合、实现和时序检查。

## 暂不要做

在仿真和板级验证完成前不要声称显示器已稳定出图；不要删除 TMDS 旧模块。

## 成功标准

综合集成后无引脚错误、时序 WNS 不小于 0，最后由板级显示器稳定显示摄像头图像。当前关键源码、集中后的仿真资产、HDMI 约束和布局失败分析已保存在 `origin/main@92a9bdc`。
## 2026-09-03 方案 A 更新

相机 PCLK 方案 A 约束已按实际 `xclk=24.03846 MHz` 修正为 41.600 ns；主时钟 `clk_in1_0` 保持不添加外部 `create_clock`，`cam_pclk_0_IBUF` 已设置 `CLOCK_DEDICATED_ROUTE FALSE`。下一动作是在 Vivado 2025.2 中重新加载工程和 XDC，重跑实现，并重点检查 `cam_pclk` 域 setup/hold WNS/TNS。若实现后该域时序失败，先暂停并向用户汇报，再确认是否转向方案 B。方案 A 静态校验证据在 `4_metrics/logs/2026-09-03_hdmi_cam_pclk_plan_a_apply_run26`。
## 2026-09-03 实现通过后的更新

实现和比特流已通过：全局 WNS/TNS 为 `10.551/0.000 ns`，WHS/THS 为 `0.023/0.000 ns`；`cam_pclk` 域 WNS/WHS 为 `35.138/0.070 ns`，route error 为 0。Messages 中 3 个 OOC `Failed to create directory 'C'.` 是子 run 过程错误；相关 DCP 和完成标记存在，顶层比特流有效。下一动作是下载比特流并做板级 HDMI 显示验证；OOC error 清理可选，待用户确认后再执行。
## 2026-09-03 BD 连线清单更新

OV5640+HDMI 显示链路已对照 2020 参考工程完成静态核对，清单在 `2_fpga/0_diaplay_test/doc/bd_ov5640_hdmi_connection_checklist.md`。核心连线一致；当前 HDMI 输出按 ADV7511 并口方案处理，不再接 `pclk_x5` 或 TMDS。板测时按清单顺序检查 Clocking Wizard locked、SCCB 配置完成、VDMA S2MM 写 DDR、VDMA MM2S 读 DDR 和显示器输出。VDMA S2MM line buffer 当前为 512，参考为 1024；先保持当前通过实现，板测稳定后再决定是否完全对齐。
UART self-test build PASS; board test pending.
UART header dependency removed and rebuild pass.
UART delay and print headers now declared locally and rebuild pass.
GUI build and run log check pass; serial retry with COM6 open before Run.
XSCT target check complete after direct UART attempt; board power cycle required before next Run.
## 2026-09-03 DDR 修正后的启动动作

用户已确认并修正 DDR 型号/配置。下一步不要直接沿用旧 Vitis 平台判断 UART 失败；先完成 Vivado BD 校验和 XSA 导出，再更新 Vitis platform/BSP/FSBL，重建 `app_component`，板卡断电重启后只打开一个 COM6 `115200-8-N1` 终端并重跑 UART self-test。验收标准是 header、3 条 heartbeat 和输入字符 echo 全部可见。记录见 `4_metrics/logs/2026-09-03_vitis_uart_ddr_root_cause_run31/ddr_root_cause.md`。
## 2026-09-03 最小 Raw TX 复测指引

当前应用已编译为持续直接输出 `UART OK\r\n` 的最小固件。下一步保持唯一 COM6 `115200-8-N1` 终端打开、断电重启后 Run。若重复看到 `UART OK`，基础 UART TX 通过；若仍无输出，继续检查 UART1 MIO 映射、时钟/波特率、FSBL/PS7 初始化、COM6 是否为实际板卡串口以及 USB 硬件路径。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/minimal_raw_tx.md`。
## 2026-09-03 XSCT 分流后的判断

已确认 PS7/MIO48/49/UART1 波特率配置正确，并已用 XSCT 绕过 Vitis Run 直接写 UART 和下载运行最小应用。若 COM6 同时看到 `XSCT OK` 与重复 `UART OK`，说明 UART 硬件路径正常，问题定位为 Vitis Run 流程；若只看到 `UART OK`，说明应用可用但 Vitis 启动流程有差异；若都没有，需要检查 COM6 是否为板卡 UART、USB 线缆/驱动或 MIO 电平。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/direct_xsct_uart_result.md`。
## 2026-09-03 TXFULL 修正后的下一步

用户只看到 `XSCT OK` 后，停机证据确认应用卡在 `main.c:9`，根因是 TX FULL 掩码误用 `bit3`；正确值为 BSP 的 `XUARTPS_SR_TXFULL=0x10`。已修正、重建并通过 XSCT 下载运行。下一步只需确认 COM6 是否连续出现 `UART OK`。确认后可将 UART BOARD TX 记为 PASS，再决定是否恢复完整自测或继续 HDMI 板级验证。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/txfull_bitfix_result.md`。
## 2026-09-03 UART 通过后的下一步

COM6 已连续显示 `UART OK`，raw UART TX 板级测试 PASS。当前 `main.c` 仍是最小 TX 测试，不是 HDMI 应用；下一步先决定是否恢复完整 UART RX echo 自测，或直接继续 ADV7511 初始化/HDMI 显示验证。若恢复 HDMI 应用，可保留最小 UART 初始化逻辑作为状态输出基础，但不要在同一阶段混入多个变量。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/uart_board_tx_pass.md`。
