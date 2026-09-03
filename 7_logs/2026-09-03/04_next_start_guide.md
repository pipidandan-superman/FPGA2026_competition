# 2026-09-03 下一次启动指引

## 先读

1. `E:\competition\HANDOFF.md`。
2. 本日 `03_validation_summary.md`。
3. `E:\competition\1_docs\EES-331_HDMI显示适配修正方案.md`。
4. `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_out_adv7511.sv`。
5. `E:\competition\2_fpga\0_diaplay_test\sim\run_modelsim.do`。

## 第一动作

整体 ModelSim 仿真已 PASS，测试台和脚本集中在 `sim` 根目录。下一步先创建 Verilog BD wrapper（例如 `hdmi_out_adv7511_bd.v`）来例化 SystemVerilog 顶层，再把它加入 BD 替换 `HDMI_top`；也可以选择把整链打包为 IP。随后删除 `pix_clk_x5`，更新 480p 引脚约束与顶层端口映射，执行综合、实现和时序检查。

## 暂不要做

在仿真和板级验证完成前不要声称显示器已稳定出图；不要删除 TMDS 旧模块。

## 成功标准

综合集成后无引脚错误、时序 WNS 不小于 0，最后由板级显示器稳定显示摄像头图像。当前关键源码和集中后的仿真资产已保存在 `origin/main@d9dd5b4`。
