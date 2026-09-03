# EES-331 HDMI ADV7511 Handoff

## 状态

- 日期：2026-09-03
- 状态：HDMI TOP MODEL SIM PASS / CAM PCLK PLAN A IMPLEMENT PASS / BITSTREAM GENERATED / OOC ERRORS NONBLOCKING
- GitHub：关键 RTL、集中后的测试台/仿真脚本、文档和最终证据已发布到 `main@d9dd5b4`
- 最新顶层归档：`main@12d31e1`，活跃顶层已改为 `hdmi_out_adv7511.v`
- 最新 XDC 归档：`main@c52e72b`，EES-331 HDMI/ADV7511 引脚约束已补齐
- 最新实现判定：run27，综合/实现/比特流通过；OOC error 非阻塞
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
