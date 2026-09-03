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
