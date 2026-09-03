# EES-331 HDMI ADV7511 Handoff

## 状态

- 日期：2026-09-03
- 状态：HDMI TOP MODEL SIM PASS
- GitHub：关键 RTL、集中后的测试台/仿真脚本、文档和最终证据已发布到 `main@d9dd5b4`
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
| `hdmi_out_adv7511` | 整体 ModelSim 仿真 PASS | 顶层集成、输出寄存与 ODDR 时钟转发 |
| `iic_multi_byte` | 非活跃资产 | 保留用于后续连续寄存器突发扩展 |

当前可复现仿真入口：`E:\competition\2_fpga\0_diaplay_test\sim\run_modelsim.do`；测试台位于 `E:\competition\2_fpga\0_diaplay_test\sim`。迁移后的最终复现证据见 `4_metrics/logs/2026-09-03_hdmi_sim_relocation_run20`。

BD 集成限制：Vivado 2020.2 Module Reference 拒绝以 `.sv` 文件为顶层的 `hdmi_out_adv7511`，错误码 `filemgmt 56-195`。需要先增加 Verilog 顶层 wrapper，或将完整链路打包为 IP；不能直接拖入 SystemVerilog 顶层。

## 顶层接口冻结

`PIX_CLK`、`RST_N`、`RGB888[23:0]`、`DE`、`H_SYNC`、`V_SYNC`、`HDMI_INT`；`HDMI_SDA`；`HDMI_DATA[15:0]`、`HDMI_CLK`、`HDMI_HSYNC`、`HDMI_VSYNC`、`HDMI_DE`、`HDMI_SCL`。

## 下一步

进行 BD 集成和 XDC：先创建 `hdmi_out_adv7511_bd.v` Verilog wrapper 并加入 BD，替换 `HDMI_top`，删除 `pix_clk_x5`，按 480p/25.175MHz 与 EES-331 引脚约束，然后综合实现并检查时序。迁移后整体仿真最终证据见 `4_metrics/logs/2026-09-03_hdmi_sim_relocation_run20`；Module Reference 拒绝原因见 `4_metrics/logs/2026-09-03_hdmi_bd_module_ref_check_run21`。

## 归档记录

- 已更新 `README.md` 的 HDMI 架构、验证状态和未验证边界。
- 已新增 `.gitignore`，排除 Vivado/ModelSim 缓存、库文件、波形和构建产物。
- 已选择性提交活跃 RTL、testbench、关键 Markdown、最终 ModelSim 命令与原始 transcript；未提交工程目录、旧架构和非活跃突发 IIC 资产。
- 已将三个测试台和 `run_modelsim.do` 集中到 `2_fpga/0_diaplay_test/sim`，迁移后整体 ModelSim 回归 PASS，提交为 `main@d9dd5b4`。

## 固定流程

每次关键动作后必须同步更新 `E:\competition\7_logs\YYYY-MM-DD\` 四个日志文件和 `E:\competition\HANDOFF.md`；验证原始日志必须保存到 `4_metrics`。
