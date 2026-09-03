# EES-331 HDMI ADV7511 Handoff

## 状态

- 日期：2026-09-03
- 状态：HDMI TOP MODEL SIM PASS
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

## 顶层接口冻结

`PIX_CLK`、`RST_N`、`RGB888[23:0]`、`DE`、`H_SYNC`、`V_SYNC`、`HDMI_INT`；`HDMI_SDA`；`HDMI_DATA[15:0]`、`HDMI_CLK`、`HDMI_HSYNC`、`HDMI_VSYNC`、`HDMI_DE`、`HDMI_SCL`。

## 下一步

进行 BD 集成和 XDC：替换 `HDMI_top`，删除 `pix_clk_x5`，按 480p/25.175MHz 与 EES-331 引脚约束，然后综合实现并检查时序。整体仿真最终证据见 `4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final`。

## 固定流程

每次关键动作后必须同步更新 `E:\competition\7_logs\YYYY-MM-DD\` 四个日志文件和 `E:\competition\HANDOFF.md`；验证原始日志必须保存到 `4_metrics`。
