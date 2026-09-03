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

历史 run19 transcript 保留在原证据目录；其启动脚本已按当前目录规范迁移到 `sim/run_modelsim.do`，历史版本可通过 Git 历史回溯。

## GitHub 选择性归档记录

- 提交：`main@efaad7c`；
- 推送目标：`origin/main`，远端已从 `3f3bca5` 更新到 `efaad7c`；
- 提交内容：活跃 HDMI/ADV7511 RTL、三个仿真文件、最终 ModelSim 命令和 transcript、关键 Markdown 文档、当日日志、handoff、README 和 `.gitignore`；
- 未提交：Vivado 工程目录、旧 TMDS/摄像头模块、旧 ADV7511 初始化模块、非活跃 `iic_multi_byte.v`、中间仿真目录、PDF 和其他构建产物。
