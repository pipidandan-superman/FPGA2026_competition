# EES-331 HDMI ADV7511 Handoff

## 状态

- 日期：2026-09-04
- 2026-09-04 板级链路进度：正常 Vitis Run 的 UART PASS；DDR pattern/保持测试 PASS；VDMA MM2S 单帧和连续读协议 PASS。PS/DDR/VDMA 链路驱动的 HDMI 首轮板测无显示，后续发现一次测试加载了旧 bit，因此该轮不能作为有效结论。
- 2026-09-04 纯 PL HDMI 隔离测试：实际使用 `2_fpga/1_zynqtest_2025/project_1/project_1.xpr`，顶层已确认为 `hdmi_colorbar_vtc_top`。链路为 100 MHz → `clk_wiz_0` 25 MHz → 自研 1-PPC 480p VTC → 5 条竖彩条 → `hdmi_out_adv7511`。显示器已点亮，说明时序、HDMI 时钟、DE 和 I2C 配置链路基本可用；颜色仍不正确。
- 2026-09-04 颜色根因修正：原 ADV7511 初始化表把外部 YCbCr422 总线误配置为 RGB/YCbCr444，且 AVI Infoframe 错写为 YCbCr444/VIC4。已将 `0x16` 改为 `0xB9`（YCbCr422 Style 1），AVI PB1 `0x55` 改为 `0x29`，VIC `0x57` 改为 `0x01`，checksum `0x54` 同步改为 `0xAB`。修改位于 `2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv`。
- 2026-09-04 复测纪律：`1_zynqtest_2025/project_1` 中曾出现综合 DCP 时间早于源码修改、bit 略晚生成的情况。颜色修正后必须对 `synth_1` 和 `impl_1` 执行 Reset Runs，再综合/实现/生成 bit；只有确认新 bit 晚于全部源码后，板测才有效。
- 2026-09-04 纯 PL 彩条定义：640×480@60，5 条竖彩条，每条 128 像素；预期从左到右为白、黄、青、绿、品红，亮度递减。XDC 只保留 EES-331 引脚和 LVCMOS33 电平，不做时序约束。ADV7511 当前表中的 `0x55~0x5E` 是 AVI Infoframe，不是内部测试彩条。
- 2026-09-04 辅助工程脚本：新增 `2_fpga/0_diaplay_test/rtl/hdmi_new/build_hdmi_colorbar_vtc.tcl`，可创建独立 Vivado 工程并生成 25 MHz Clocking Wizard；但实际板测复测也可继续使用 `2_fpga/1_zynqtest_2025/project_1`。
- 2026-09-04 XSCT fallback：普通 Vitis Run 再现无串口输出时，使用 `4_metrics/logs/2026-09-04_vitis_uart_bypass_run33/run_uart_bypass.tcl` 手动初始化 PS、直写 UART1 FIFO、下载并运行 ELF。先看 `XSCT OK` 是否出现，以区分串口路径和应用运行问题。
- 2026-09-04 正常启动链修正：`app_component/_ide/launch.json` 原指向旧 `.bit` 和旧 `ps7_init.tcl`，已改为当前 XSA 的 `hw/sdt` 产物。进一步发现 FSBL 虽然重编但实际源 `zynq_fsbl/ps7_init.c` 仍是旧 DDR 配置；已同步为当前 XSA 生成版本并重建，`export/.../boot/fsbl.elf` 已同步。普通 Vitis Run/Debug 复测仍待用户执行。
- 2026-09-04 UART 自初始化：正常 Run 仍无输出后，`main.c` 已在入口第一行自初始化 UART1 时钟、MIO48/49、115200-8-N1 和 RX/TX，不再依赖 launch/PS7 是否成功完成 UART 配置。应用构建 PASS；下一步只用 Vitis 正常 Run/Debug 验收。
- 状态：HDMI TOP MODEL SIM PASS / CAM PCLK PLAN A IMPLEMENT PASS / BITSTREAM GENERATED / OOC ERRORS NONBLOCKING / BD CONNECTION CHECK PASS / RAW UART TX BOARD PASS
- GitHub：关键 RTL、集中后的测试台/仿真脚本、文档和最终证据已发布到 `main@d9dd5b4`
- 最新顶层归档：`main@12d31e1`，活跃顶层已改为 `hdmi_out_adv7511.v`
- 最新 XDC 归档：`main@c52e72b`，EES-331 HDMI/ADV7511 引脚约束已补齐
- 最新 BD 核对：run28，OV5640+HDMI 关键连线清单完成
- 分辨率：480p / 640x480@60
- 像素时钟：25.175 MHz
- 颜色空间：BT.709，RGB888 转 YCbCr422
- 目标路径：`E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new`

## 当前模块

| 模块 | 状态 | 说明 |
|---|---|---|
| `rgb2ycbcr422` | 实现完成，视频检查通过 | BT.709 定点转换与 Cb/Cr 奇偶打包 |
| `adv7511_init_table_pkg` | 实现完成，板级待验 | 480p 首版寄存器配置表 |
| `adv7511_controller` | 配置仿真 PASS | 上电延时、启动、完成/错误控制 |
| `adv7511_iic_data_xfer` | 配置仿真 PASS | 配置表读取、寄存器地址/数据传输握手 |
| `iic_protocal` | 直接复用用户源码，配置仿真 PASS | 底层 IIC 协议，ADV7511 地址 7'h39，分频 252 |
| `adv7511_cfg_top` | 配置仿真 PASS | 配置模块顶层，集成控制、传输和 IIC 协议 |
| `hdmi_out_adv7511` | Verilog 顶层整体 ModelSim PASS | `.v` 顶层集成、输出寄存与 ODDR 时钟转发，供 BD Module Reference 直接引用 |
| `iic_multi_byte` | 非活跃资产 | 保留用于后续连续寄存器突发扩展 |

当前可复现仿真入口：`E:\competition\2_fpga\0_diaplay_test\sim\run_modelsim.do`；测试台位于 `E:\competition\2_fpga\0_diaplay_test\sim`。Verilog 顶层最终复现证据见 `4_metrics/logs/2026-09-03_hdmi_top_verilog_run22`。

BD 集成限制已关闭：原 `.sv` 顶层被 Vivado 2020.2 Module Reference 拒绝，错误码 `filemgmt 56-195`；当前已改为等价 `hdmi_out_adv7511.v` 顶层，独立工程确认可创建 BD RTL cell。旧 `.sv` 顶层已删除。

## 顶层接口冻结

`PIX_CLK`、`RST_N`、`RGB888[23:0]`、`DE`、`H_SYNC`、`V_SYNC`、`HDMI_INT`；`HDMI_SDA`；`HDMI_DATA[15:0]`、`HDMI_CLK`、`HDMI_HSYNC`、`HDMI_VSYNC`、`HDMI_DE`、`HDMI_SCL`。BD wrapper 实际导出端口均带 `_0` 后缀。

## 下一步

XDC 已按 EES-331 手册补齐 HDMI/ADV7511 引脚，并通过端口、重复引脚和电平标准检查。下一步在 Vivado 中重新加载约束，执行 BD 校验、综合、实现和时序检查。Verilog 顶层仿真证据见 `4_metrics/logs/2026-09-03_hdmi_top_verilog_run22`；BD Module Reference 接受证据见 `4_metrics/logs/2026-09-03_hdmi_bd_verilog_ref_check_run23`；XDC 检查证据见 `4_metrics/logs/2026-09-03_hdmi_xdc_constraint_check_run24`。

最新实现失败原因已分析完成：`cam_pclk_0/AA22` 是普通 IO，但被用作相机采样时钟并插入 BUFG，触发 `Place 30-574 / Place 30-99`。尚未修改设计，等待用户在“降级 CLOCK_DEDICATED_ROUTE”与“重构相机 PCLK 采样架构”之间确认。分析证据见 `4_metrics/logs/2026-09-03_hdmi_impl_place_failure_analysis_run25`。

## 归档记录

- 已更新 `README.md` 的 HDMI 架构、验证状态和未验证边界。
- 已新增 `.gitignore`，排除 Vivado/ModelSim 缓存、库文件、波形和构建产物。
- 已选择性提交活跃 RTL、testbench、关键 Markdown、最终 ModelSim 命令与原始 transcript；未提交工程目录、旧架构和非活跃突发 IIC 资产。
- 已将三个测试台和 `run_modelsim.do` 集中到 `2_fpga/0_diaplay_test/sim`，迁移后整体 ModelSim 回归 PASS，提交为 `main@d9dd5b4`。
- 已将活跃顶层从 `hdmi_out_adv7511.sv` 改为等价 `hdmi_out_adv7511.v`，ModelSim 回归 PASS，Vivado 2020.2 BD Module Reference 检查 PASS，提交为 `main@12d31e1`。
- 已将 EES-331 手册中的 23 个 HDMI/ADV7511 引脚补入工程 XDC，并保存 `XDC_VALIDATION_PASS` 证据，提交为 `main@c52e72b`。
- 已分析综合后 `place_design` 失败原因，保留 Vivado 日志、DRC 报告和 AA22 引脚能力查询；尚无修复动作，提交为 `main@92a9bdc`。

## 固定流程

每次关键动作后必须同步更新 `E:\competition\7_logs\YYYY-MM-DD\` 四个日志文件和 `E:\competition\HANDOFF.md`；验证原始日志必须保存到 `4_metrics`。
## 2026-09-03 方案 A 实现结果

用户已确认采用方案 A，并根据 Clocking Wizard 实际频率将相机返回的 `cam_pclk_0` 约束为 41.600 ns（24.03846 MHz）；外层主时钟 `clk_in1_0` 不添加重复 `create_clock`，`cam_pclk_0_IBUF` 已设置 `CLOCK_DEDICATED_ROUTE FALSE`。静态证据见 `4_metrics/logs/2026-09-03_hdmi_cam_pclk_plan_a_apply_run26`。Vivado 2025.2 实现已通过，全局 WNS/TNS 为 `10.551/0.000 ns`，WHS/THS 为 `0.023/0.000 ns`，`cam_pclk` 域 WNS/WHS 为 `35.138/0.070 ns`，route error 为 0，`display_test_wrapper.bit` 已生成。OOC 子 run 中的 `Failed to create directory C` 为非阻塞错误，详细判定见 `4_metrics/logs/2026-09-03_hdmi_ooc_synthesis_error_analysis_run27`。下一动作是板级 HDMI 显示验证；是否清理 OOC error 由用户确认。
## 2026-09-03 BD 连线核对

已对照 2020 `cam_vdma_hdmi_true` 工程生成清单：`2_fpga/0_diaplay_test/doc/bd_ov5640_hdmi_connection_checklist.md`。OV5640 采集、Video In、VDMA S2MM/MM2S、HP0/HP1、Video Out、VTC、`pix_frame_display` 到新 HDMI 前端的关键连线一致。当前控制面使用 SmartConnect，参考工程使用 AXI Interconnect；Zynq 7010/7020、50/100 MHz 外部时钟、PS FCLK0 频率和 HDMI 输出架构差异均记录为工程基线差异。VDMA S2MM line buffer 当前为 512、参考为 1024；当前 `rom_data` 接常量 0，参考接 ROM。二者需理解但不阻断当前板测。证据见 `4_metrics/logs/2026-09-03_bd_connection_check_run28`。
UART self-test build PASS; board test pending.
UART header dependency removed and rebuild pass.
UART delay and print headers now declared locally and rebuild pass.
GUI build and run log check pass; serial retry with COM6 open before Run.
XSCT target check complete after direct UART attempt; board power cycle required before next Run.
## 2026-09-03 UART 无输出根因更新

用户确认 Zynq DDR 型号/配置未按 EES-331 板卡正确选择，并已完成修改。该根因可解释 FSBL/应用进入 DDR 后跑飞、debug session 提前断开、自动 COM6 终端关闭且 UART 无输出。当前仍是根因记录，不是 UART 板级 PASS；必须重新生成/导出 XSA，更新 Vitis platform/BSP/FSBL，重建应用，重新上电后在唯一 COM6 `115200-8-N1` 终端验证 header、heartbeat 和 RX echo。证据见 `4_metrics/logs/2026-09-03_vitis_uart_ddr_root_cause_run31/ddr_root_cause.md`。
## 2026-09-03 最小 UART Raw TX 测试

用户已完成 DDR 修正、XSA 更新、platform/BSP 更新和重新编译，但 UART 仍无输出。`app_component/src/main.c` 已简化为直接写 PS UART1 TX FIFO（`0xE0001030`），仅检查 TX FULL（`0xE000102C` bit3），并持续输出 `UART OK\r\n`；不再依赖 `xil_printf`、BSP API、heartbeat 或 RX echo。SOURCE UPDATE COMPLETE / BUILD PASS / BOARD TEST PENDING；ELF text/data/bss 为 `25600/1420/22952`。复测需唯一 COM6 `115200-8-N1` 终端；若无输出，排查 UART1 MIO、时钟/波特率、初始化、COM 端口映射和硬件路径。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/minimal_raw_tx.md`。
## 2026-09-03 XSCT 直接 UART 分流结果

Vitis Run 日志缺少完整下载/运行流程，调试器反汇编出现无效内容，不能证明应用执行。改用 XSCT 直接执行新 XSA 的 `ps7_init.tcl` 后，寄存器回读确认 `MIO48_CTRL=0x12E0`、`MIO49_CTRL=0x12E1`、`UART_BAUDGEN=0x7C`、`UART_BAUDDIV=6`；已直写 `XSCT OK\r\n`，并下载运行最小 `app_component.elf`。当前等待 COM6 确认是否出现 `XSCT OK` 和重复 `UART OK`。若两者都出现，UART 硬件路径正常，问题收敛为 Vitis Run 流程；若都没有，继续排查 COM6 与板卡 UART 的硬件映射。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/direct_xsct_uart_result.md`。
## 2026-09-03 UART TXFULL 位修正

用户确认 COM6 只出现 XSCT 直写的 `XSCT OK`，证明 COM6/UART1 硬件路径可用。XSCT 停机确认应用卡在 `main.c:9` 的错误等待循环：原掩码使用 `0x08`，但 Zynq UART 状态寄存器 `0x08` 是 `TXEMPTY`，BSP 定义的 `TXFULL` 是 `0x10`。已改为 `UART1_STATUS_TX_FULL=(1UL << 4)` 并重建 ELF（text/data/bss `25600/1420/22952`），随后通过 XSCT 下载运行。当前 UART BOARD TX 为 FIX APPLIED / COM6 REPEAT CONFIRMATION PENDING。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/txfull_bitfix_result.md`。
## 2026-09-03 UART Raw TX Board PASS

修正 Zynq UART1 `TXFULL` 位后，COM6 已连续输出 `UART OK`，`app_component.elf` 经 XSCT 加载到 `0x00100000` 并运行；调试反汇编也显示有效 `_start/main/uart_puts/uart_putc/exception` 代码。结合 DDR 修正，最小 UART 应用的板级执行链路已通过。当前结论为 `RAW UART TX BOARD PASS`；UART RX echo 和 HDMI 显示仍待验证。当前 `main.c` 仍是最小 TX 固件。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/uart_board_tx_pass.md`。
