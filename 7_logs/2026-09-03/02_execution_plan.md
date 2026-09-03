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
- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_out_adv7511.sv`
- `E:\competition\2_fpga\0_diaplay_test\sim\adv7511_cfg_top_tb.sv`
- `E:\competition\2_fpga\0_diaplay_test\sim\hdmi_out_adv7511_tb.sv`
- `E:\competition\2_fpga\0_diaplay_test\sim\oddr_sim_model.sv`

## 整体仿真入口

`E:\competition\2_fpga\0_diaplay_test\sim\run_modelsim.do`

## 归档入口

- `E:\competition\README.md`
- `E:\competition\.gitignore`
- GitHub 提交：`d9dd5b4`（测试台和仿真脚本集中后的最新归档）

## 风险

ADV7511 寄存器表首版来源于公开推荐配置和方案文档关键项，尚未板级验证。若黑屏，优先检查 I2C ACK、HPD 延时、Cb/Cr 顺序和 DE 对齐。构建产物、仿真库和波形已通过 `.gitignore` 排除。
