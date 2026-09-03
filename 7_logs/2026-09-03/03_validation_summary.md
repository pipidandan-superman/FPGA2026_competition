# 2026-09-03 验证摘要

## 既有事实

用户提供的 v_tc 截图为 Video Mode 480p：H Active 640、H Total 800、Sync End 752；V Active 480、V Total 525、Sync End 491。

## 本次验证要求

- RTL 仿真检查 480p 首个有效像素的 Cb/Y、第二个有效像素 Y/Cr 交替。
- 检查 RGB 数据经流水线后 DE/HS/VS 与输出数据同拍。
- 检查复位释放后 I2C 至少延时 100 ms。
- 解码 SDA 位流，确认写地址 0x72、寄存器地址和数据进行字节写入。
- 仿真结束返回 0。

## 结果

## 已完成证据

- ModelSim 10.1c 编译加载通过，覆盖 `adv7511_init_table_pkg`、`rgb2ycbcr422`、`adv7511_i2c_init`、`hdmi_out_adv7511`、testbench 和本地 ODDR 仿真模型。
- 480p 视频自检完成 16/16 像素；未出现 YCbCr、DE、HSYNC 或 VSYNC mismatch。
- I2C 首个 SCL 出现在 120.842 ms，满足不小于 100 ms 的上电延时要求。
- FAST_SIM 模式中前 5/18 个寄存器写入完成，确认 0x72 写地址、ACK、寄存器地址和数据字节可解码。

## 旧单模块架构当时的未完成项

- 旧 `adv7511_i2c_init` 架构当时完整 18 项寄存器序列仿真未结束，不能标记该架构全序列 PASS。
- 尚无 Vivado 综合、实现、时序和板级显示证据。

## 原始证据

- `E:\competition\4_metrics\logs\2026-09-03_hdmi_480p_adv7511_rtl_run01\modelsim_transcript.txt`：首轮编译失败记录。
- `E:\competition\4_metrics\logs\2026-09-03_hdmi_480p_adv7511_rtl_run02\modelsim_transcript.txt`：testbench 流水基线错拍记录。
- `E:\competition\4_metrics\logs\2026-09-03_hdmi_480p_adv7511_rtl_run03\modelsim_transcript.txt`：Cb/Cr 奇偶 bug 复现记录。
- `E:\competition\4_metrics\logs\2026-09-03_hdmi_480p_adv7511_rtl_run04\modelsim_transcript.txt`：视频 16/16 通过和 120.842 ms 起始证据。
- `E:\competition\4_metrics\logs\2026-09-03_hdmi_480p_adv7511_rtl_run09_fast\modelsim_transcript.txt`：FAST_SIM 前 5/18 写完成证据。

## 旧单模块架构当时判定

在重构前，旧架构状态为 `I2C SEQUENCE PARTIAL`。该结论随后由新的三层配置架构完整仿真关闭。

## 2026-09-03 IIC 架构重构补充验证

已按用户要求将配置通路拆分为三层：

1. `adv7511_controller`：上电延时、启动、完成/错误控制；
2. `adv7511_iic_data_xfer`：配置表读取、地址/数据组织和传输握手；
3. `iic_protocal`：直接复用用户提供的底层 IIC 协议，未修改源文件。

`adv7511_cfg_top` 为配置顶层，集成以上三层；`hdmi_out_adv7511` 已改为例化 `adv7511_cfg_top`。

### 新增验证结果

- ModelSim 10.1c 编译互连 PASS，覆盖新三层配置顶层和 `hdmi_out_adv7511`。
- 加速 IIC 配置仿真：18/18 次 START/STOP，18/18 项寄存器写入，ACK/内容比对 PASS。
- 99.9kHz IIC（25.175MHz / 252）配置仿真：18/18 次 START/STOP，18/18 项寄存器写入，ACK/内容比对 PASS。
- 真实上电延时仿真：`FAST_SIM=0`、延时 120ms、IIC 分频 252 时 PASS；仿真在 126.10558ms 完成，包含 18/18 次 START/STOP。

`iic_multi_byte.v` 保留为后续连续寄存器突发扩展资产，当前活跃链路不使用。

## 最新判定

当前状态为 `RTL COMPILE PASS / VIDEO PIPELINE CHECK PASS / ADV7511 CFG SIM PASS`；仍缺少 Vivado 综合、实现、时序和板级显示证据。

## 2026-09-03 整体 HDMI 顶层仿真

使用 ModelSim 10.1c 完成整体 `hdmi_out_adv7511` 仿真，包含视频转换、输出对齐、ODDR 仿真模型、ADV7511 控制层、数据传输层、用户 IIC 协议层。

### 最终结果

- 视频检查：16/16 像素 PASS；
- ADV7511 配置：18/18 项寄存器写入 PASS；
- IIC ACK：无 NACK 错误；
- 首个 IIC START：约 120.843ms；
- 最终仿真时间：126.09378ms；
- 稳定输出标记：`TEST_PASS: pixels=16 writes=18`。

### 原始证据

- 最终 PASS 证据：`E:\competition\4_metrics\logs\2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final\modelsim_transcript.txt`
- 修正前 testbench 监控误判记录：`E:\competition\4_metrics\logs\2026-09-03_hdmi_480p_adv7511_overall_sim_run17\modelsim_transcript.txt`

### 最新整体判定

整体 HDMI 新模块当前状态为 `HDMI TOP MODEL SIM PASS`。该结论仅覆盖 RTL/ModelSim 仿真，不覆盖 Vivado 综合、时序和板级显示。

## 2026-09-03 仿真文件迁移回归

已按目录集中要求将 `adv7511_cfg_top_tb.sv`、`hdmi_out_adv7511_tb.sv`、`oddr_sim_model.sv` 和 `run_modelsim.do` 从旧位置迁移到 `E:\competition\2_fpga\0_diaplay_test\sim`。脚本改用绝对源路径和独立 run20 输出目录，避免覆盖历史证据。

迁移后使用 ModelSim 10.1c 命令行重新执行整体仿真：

- 视频检查：16/16 像素 PASS；
- ADV7511 配置：18/18 项寄存器写入 PASS；
- 首个 IIC START：约 120.843ms；
- 最终仿真时间：126.09378ms；
- 磁盘 transcript 稳定标记：`TEST_PASS: pixels=16 writes=18`。

### 迁移后原始证据

- `E:\competition\4_metrics\logs\2026-09-03_hdmi_sim_relocation_run20\modelsim_transcript.txt`

迁移结果已提交并推送为 `origin/main@d9dd5b4`。

## 2026-09-03 BD Module Reference 限制验证

在独立临时工程中使用 Vivado 2020.2 和 `xc7z020clg484-1` 执行：

```tcl
create_bd_cell -type module -reference hdmi_out_adv7511 u_hdmi_out_adv7511
```

Vivado 明确返回：

```text
ERROR: [filemgmt 56-195] Reference 'hdmi_out_adv7511' contains top file
'.../hdmi_out_adv7511.sv' of type SystemVerilog. This type is not allowed
as the top file in the reference.
```

因此这不是依赖缺失，而是当前 Vivado 版本对 BD Module Reference 顶层文件类型的限制。旧 `HDMI_top`、`data_gen`、`pix_frame_dispaly` 等模块顶层是 `.v` 文件，所以可以直接拖入 BD。

### 证据

- `E:\competition\4_metrics\logs\2026-09-03_hdmi_bd_module_ref_check_run21\vivado_module_ref_check.txt`
- `E:\competition\4_metrics\logs\2026-09-03_hdmi_bd_module_ref_check_run21\check_hdmi_module_ref.tcl`

## 2026-09-03 HDMI 顶层改为 Verilog

已将活跃顶层从 `hdmi_out_adv7511.sv` 改为等价 `hdmi_out_adv7511.v`，模块名、端口、宽度、方向、复位行为、ADV7511 配置通路、RGB888 转 YCbCr422 通路和 ODDR 时钟转发保持不变。原 `.sv` 顶层已删除，避免重复模块定义。

### ModelSim 回归

使用 ModelSim 10.1c 重新编译并执行整体仿真：

- `hdmi_out_adv7511.v` 编译 PASS；
- 视频检查：16/16 像素 PASS；
- ADV7511 配置：18/18 项寄存器写入 PASS；
- 首个 IIC START：约 120.843ms；
- 最终仿真时间：126.09378ms；
- 磁盘 transcript 稳定标记：`TEST_PASS: pixels=16 writes=18`。

### Vivado Module Reference 检查

使用 Vivado 2020.2 独立工程添加 `.v` 顶层并执行：

```tcl
create_bd_cell -type module -reference hdmi_out_adv7511 u_hdmi_out_adv7511
```

Vivado 返回 `MODULE_REF_OK: top_file_type=verilog`，确认 BD 可以创建该 RTL cell。独立 BD 的后续 `validate_bd_design` 只因测试环境中 `PIX_CLK` 未连接有效时钟源报错，这与顶层文件类型无关；实际 BD 接线后应重新校验。

### 证据

- ModelSim：`E:\competition\4_metrics\logs\2026-09-03_hdmi_top_verilog_run22\modelsim_transcript.txt`
- Vivado：`E:\competition\4_metrics\logs\2026-09-03_hdmi_bd_verilog_ref_check_run23\vivado_module_ref_check.txt`
- Vivado 脚本：`E:\competition\4_metrics\logs\2026-09-03_hdmi_bd_verilog_ref_check_run23\check_hdmi_verilog_module_ref.tcl`

Verilog 顶层转换、仿真证据和 BD Module Reference 检查已提交并推送为 `origin/main@12d31e1`。

## 2026-09-03 EES-331 HDMI XDC 补齐检查

检查工程 XDC `pin_zynq7020_cam.xdc` 后确认：原文件已有 PL 100MHz 时钟 `M19`、复位 `L18` 和摄像头约束，但没有 HDMI/ADV7511 引脚约束，也没有系统输入时钟周期约束。

已根据 `EES-331 User Guide.pdf` 第 32/33 页 HDMI 引脚表和工程 BD wrapper 实际端口名补齐：

- 16 位 `HDMI_DATA_0[15:0]`；
- `HDMI_CLK_0`、`HDMI_DE_0`、`HDMI_HSYNC_0`、`HDMI_VSYNC_0`；
- I2C 配置 `HDMI_SCL_0` 与双向 `HDMI_SDA_0`；
- 可选状态输入 `HDMI_INT_0`；
- 全部新增 HDMI IO 设置为 `LVCMOS33`；
- 补充 `clk_in1_0` 的 `create_clock -period 10.000`；
- 补充 `CFGBVS=VCCO` 和 `CONFIG_VOLTAGE=3.3`。

自动检查结果：

- HDMI 手册引脚映射：23/23 PASS；
- BD wrapper HDMI 端口集合：匹配 PASS；
- 物理引脚重复检查：PASS；
- 每个约束端口电平标准检查：PASS；
- 当前 XDC 共 40 条 `PACKAGE_PIN` 和 40 条 `IOSTANDARD`；
- 稳定标记：`XDC_VALIDATION_PASS`。

### 证据

- `E:\competition\4_metrics\logs\2026-09-03_hdmi_xdc_constraint_check_run24\xdc_validation.txt`
- `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.srcs\constrs_1\new\pin_zynq7020_cam.xdc`

该结论仅覆盖静态 XDC 引脚/端口检查；Vivado 综合、实现、时序和板级显示仍待验证。

EES-331 HDMI XDC 补齐和静态检查证据已提交并推送为 `origin/main@c52e72b`。

## 2026-09-03 综合后布局失败分析

综合通过后，`impl_1/place_design` 在 IO Clock Placer 阶段失败。日志显示 `cam_pclk_0_IBUF` 到 `BUFGCTRL_X0Y0` 不满足 `rule_gclkio_bufg`，Vivado 建议的临时约束是 `CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_0_IBUF]`。

进一步查询 XC7Z020 CLG484 器件库确认：`AA22/Bank 33` 的封装功能是 `IO_L7P_T1_33`，不是 `MRCC/SRCC` 时钟能力引脚。同时 RTL 中 `cam_pclk` 是相机采集寄存器的实际采样时钟。因此失败根因是“普通 IO 被用作全局时钟输入”，不是 HDMI 新增引脚冲突或资源不足。

已形成两个待确认方案：

1. 方案 A：按 Vivado 建议为 `cam_pclk_0_IBUF` 添加 `CLOCK_DEDICATED_ROUTE FALSE`，并补充相机 PCLK `create_clock`；可快速解除阻塞，但时钟路径不理想，必须检查时序。
2. 方案 B：重构相机 PCLK 采样架构，不把 `AA22` 普通 IO 当全局时钟；更规范，但涉及采集 RTL/BD 重新验证。

### 证据

- 失败日志：`E:\competition\4_metrics\logs\2026-09-03_hdmi_impl_place_failure_analysis_run25\vivado_impl_runme.txt`
- 分析记录：`E:\competition\4_metrics\logs\2026-09-03_hdmi_impl_place_failure_analysis_run25\place_failure_analysis.md`
- 引脚能力查询：`E:\competition\4_metrics\logs\2026-09-03_hdmi_impl_place_failure_analysis_run25\pin_capability_vivado.txt`

布局失败原因、修复方案和原始证据已提交并推送为 `origin/main@92a9bdc`。

历史 run19 transcript 保留在原证据目录；其启动脚本已按当前目录规范迁移到 `sim/run_modelsim.do`，历史版本可通过 Git 历史回溯。

## GitHub 选择性归档记录

- 提交：`main@efaad7c`；
- 推送目标：`origin/main`，远端已从 `3f3bca5` 更新到 `efaad7c`；
- 提交内容：活跃 HDMI/ADV7511 RTL、三个仿真文件、最终 ModelSim 命令和 transcript、关键 Markdown 文档、当日日志、handoff、README 和 `.gitignore`；
- 未提交：Vivado 工程目录、旧 TMDS/摄像头模块、旧 ADV7511 初始化模块、非活跃 `iic_multi_byte.v`、中间仿真目录、PDF 和其他构建产物。
## 2026-09-03 相机 PCLK 方案 A 约束校验

用户确认 Clocking Wizard 实际输出频率为 `pclk=25 MHz`、`pclk_x5=125 MHz`、`xclk=24.03846 MHz`、`clk_50m=50 MHz`。相机返回的 `cam_pclk_0` 与 `xclk` 频率一致，因此按 41.600 ns 约束，替代此前错误的 20 ns 保守约束。

静态校验结果：

- `clk_in1_0` 主时钟 `create_clock`：不存在，符合时钟 IP 内部约束要求；
- `cam_pclk_0`：存在 `create_clock -period 41.600 -name cam_pclk`；
- `cam_pclk_0_IBUF`：存在 `CLOCK_DEDICATED_ROUTE FALSE`；
- EES-331 HDMI/ADV7511：23 个引脚约束和 23 个 LVCMOS33 电平约束保持完整；
- 当前状态：`PLAN_A_APPLIED / REIMPLEMENT_PENDING`。

本结论是约束静态校验，不替代实现结果。必须在 Vivado 2025.2 中重新加载 XDC 后重跑实现，并重点检查 `cam_pclk` 域 setup/hold 的 WNS/TNS。若该时钟域时序失败，先向用户汇报，再确认是否转向方案 B。原始证据在 `E:\competition\4_metrics\logs\2026-09-03_hdmi_cam_pclk_plan_a_apply_run26\plan_a_constraint_validation.txt`。
## 2026-09-03 Vivado 实现、比特流与 OOC error 判定

本次实现已通过：`place_design`、`route_design` 和 `write_bitstream` 均成功，最终比特流为 `display_test_wrapper.bit`。Route Status 显示 10,921 个 routable net 全部连通且 0 个 routing error。全局时序为 WNS `10.551 ns`、TNS `0.000 ns`、WHS `0.023 ns`、THS `0.000 ns`；`cam_pclk` 域 WNS `35.138 ns`、WHS `0.070 ns`。方案 A 的布局/时序风险已由实现结果关闭。

Messages 中的 3 个综合 error 来自 OOC 子 run：`util_vector_logic`、`rst_ps7_0_50M` 和 `axi_mem_intercon_imp_xbar`。错误是 `create_project -in_memory` 阶段的 `Failed to create directory 'C'.`，但相关 run 目录均存在最终 DCP 和 `__synthesis_is_complete__` 标记；`v_tc` 的当前日志中也保留同类错误记录。因此 GUI 的 error 计数是 OOC 子 run 日志中的历史/过程错误，不是顶层综合失败，也不使已生成的比特流无效。如需 Messages 清零，后续可单独 reset/regenerate 这些 OOC run；板级验证前不是必须动作。详细证据见 `4_metrics/logs/2026-09-03_hdmi_ooc_synthesis_error_analysis_run27/ooc_error_analysis.md`。
## 2026-09-03 OV5640+HDMI BD 静态连线核对

参考工程与当前工程的核心显示链路连接一致：OV5640 数据/PCLK/HREF/VSYNC 进入采集模块后，经 Video In、VDMA S2MM、AXI Interconnect、Zynq HP1 写 DDR；再经 HP0、VDMA MM2S、AXI-Stream、Video Out、VTC 时序、`pix_frame_display`，进入新 HDMI 模块。AXI 控制面最终都到达 VDMA S_AXI_LITE；当前控制拓扑使用 SmartConnect，参考工程使用 AXI Interconnect。

`cam_captrue_data`、`ov5640_cfg_top` 和 `pix_frame_display` 的源文件在两侧 SHA256 相同。Clocking Wizard 的 25/125/24.03846/50 MHz 输出配置一致；外部输入分别为 50 MHz 和 100 MHz，属于工程基线差异。VTC 两侧均为 480p、640x800、480x525、HSYNC/VSYNC High、RGB。VDMA 配置基本一致，仅当前 S2MM line buffer 生成值为 512，参考为 1024。

当前 HDMI 边界按 ADV7511 并口方案替换旧 TMDS 直驱方案，因此 `PIX_CLK/RST_N/RGB888/DE/H_SYNC/V_SYNC` 连接正确，无 `pclk_x5` 和 TMDS 差分口是预期。`pix_frame_display/rom_data` 当前接常量 0，参考工程接 ROM 输出；该差异只影响局部图案/OSD 显示，不阻断相机视频主链路。完整清单见 `2_fpga/0_diaplay_test/doc/bd_ov5640_hdmi_connection_checklist.md`。
UART self-test build PASS; board test pending.
UART header dependency removed and rebuild pass.
