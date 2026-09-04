# 下次启动指引

## 先读文件

1. 本目录 `02_execution_plan.md` 的阶段 0 到阶段 3。
2. `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true\7_proj\vmda_HDMI_cam\vitis\cam_vdma_hdmi\src\cam_vdma_hdmi.c`。
3. `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true\7_proj\vmda_HDMI_cam\vitis\vdma_ctrl\src\main_vdma_read.c`。
4. 当前生成平台的 `xparameters.h` 与 `lscript.ld`。

## 第一个具体动作

阶段化代码已改入 `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`，当前 ELF 构建通过。下一步进行板级运行：

1. 已修正 Vitis launch 使用当前 `display_test_platform/hw/sdt/ps7_init.tcl`；确认重新运行时该路径生效。
2. 应用已新增 UART1 自初始化，`main()` 第一行配置时钟、MIO48/49、8-N-1 和 115200 baud。
3. 停止旧 debug，建议完全关闭并重新打开 Vitis，确保 `_ide/launch.json` 修改被重新加载。
4. 建立独立记录目录并开启唯一 COM6 `115200-8-N1` 终端。
5. 用 Vitis 正常 Run/Debug 下载运行；先确认 5 次 `UART_OK INDEX=n` 和 `UART_TEST_PASS`。
6. UART 通过后等 5 秒，继续等待 `DDR_PASS`；若出现 `DDR_FAIL_STOP`，不要启动 VDMA。
7. 看到 `COLORBAR_FILLED`、VDMA 寄存器快照和 `VDMA_MM2S_PASS` 后，再人工判定 HDMI 是否显示 640×480 八彩条。

## UART 再次无输出的 XSCT fallback

先终止当前 Vitis debug，再执行：

```powershell
& F:\vivado2025\2025.2\Vitis\bin\xsct.bat E:\competition\4_metrics\logs\2026-09-04_vitis_uart_bypass_run33\run_uart_bypass.tcl
```

COM6 应先看到 `XSCT OK`，随后是 `UART_TEST_BEGIN`、5 次 `UART_OK` 和 `UART_TEST_PASS`。若无 `XSCT OK`，优先查串口路径/PS7 初始化；若有 `XSCT OK` 但无应用输出，才回到应用下载/运行分析。

## 立即不要做

- 不要直接打开 OV5640 或调试 IIC。
- 不要同时启动 MM2S 和 S2MM 来“顺便看能不能显示”。
- 不要把 1280×720 packed RGB 测试参数直接套到 640×480 AXI 对齐流程。
- 不要覆盖 2020 参考工程源码。

## 下次成功标准

至少获得一份完整 UART 证据，其中包含：

```text
V1_PLATFORM_OK
DDR_PASS
```

若能继续，则再要求：

```text
VDMA_MM2S_PASS
HDMI_COLORBAR_PASS
```

## 2026-09-04 代码就绪状态

`app_component.elf` 已重建通过；当前代码默认按 `UART → DDR → VDMA MM2S` 执行。已修正正常 Vitis launch 使用 DDR 修正后的 `ps7_init.tcl`。若只想隔离 UART 问题，把 `RUN_DDR_TEST` 和 `RUN_VDMA_MM2S` 改为 `0`；若只想隔离 DDR，把 `RUN_VDMA_MM2S` 改为 `0`；正式判定仍应保留默认 `1/1/1`。

## 当前阻塞点

无计划阻塞。唯一需要在执行前确认的是：本次下载的 `.bit`/`.xsa` 是否为当前 EES-331 HDMI/ADV7511 活跃工程导出的同一版本。

## 2026-09-04 PS-only 最小 UART 应用下一步

当前隔离测试工程是 `E:\competition\2_fpga\1_zynqtest_2025\vitis`，应用构建已通过：

```text
E:\competition\2_fpga\1_zynqtest_2025\vitis\app_component\build\app_component.elf
```

**板级结果已更新：PS-only UART PASS。** 第一个动作切回主工程 `E:\competition\2_fpga\0_diaplay_test\vitis`，重新构建 `app_component`，继续按 `UART → DDR → VDMA MM2S → HDMI` 顺序执行正常 Run/Debug。不要重新创建应用，不要回到手动 `-nostdlib` 旁路。关闭多余串口终端，只保留一个 COM6 `115200-8-N1`。

预期串口输出：

```text
UART OK 0
UART OK 1
UART OK 2
UART OK 3
UART OK 4
```

PS-only 工程已证明 Vitis 正常启动和 UART 通路可用。若主工程仍无输出，优先检查主工程 launch 是否加载当前 `.bit`、`ps7_init.tcl` 和当前 ELF；不要先改串口波特率或重复重建 PS-only 工程。

## 2026-09-04 新主工程 UART 复现启动动作

新主工程已经重建为与 PS-only UART 测试一致的最小程序：

```text
E:\competition\2_fpga\0_diaplay_test\vitis\app_component\build\app_component.elf
```

直接在 Vitis 中重新构建并正常 Run/Debug `app_component`。只打开一个 COM6 `115200-8-N1` 终端。板级预期输出：

```text
UART OK 0
UART OK 1
UART OK 2
UART OK 3
UART OK 4
```

若该程序在新主工程无输出，而 PS-only 工程仍有输出，则不再怀疑 UART 源码；立即比对两边 launch 使用的 `.bit`、FSBL 和 `ps7_init.tcl` 哈希。确认 UART 通过后，才能把主程序扩展回 `DDR → VDMA MM2S → HDMI` 分层验证。

## 2026-09-04 UART PASS 后下一步

新主工程 UART 已通过用户板级确认。下一步不要直接开摄像头或 VDMA，应先把主程序扩展为分层测试：

1. 保留当前 UART 作为状态输出；
2. 增加 DDR 读写测试：全 0、全 1、`AAAA5555`、`5555AAAA`、地址指纹、递增值；
3. 增加短时保持回读，确认 DDR 不是仅写入后立刻可读；
4. 只有串口输出 `DDR_PASS` 后，再预填彩条并单独启动 VDMA MM2S；
5. HDMI 彩条显示稳定后，再进入 VDMA S2MM / 摄像头路径。

正式判定标记：

```text
DDR_PASS / DDR_FAIL
VDMA_MM2S_PASS / VDMA_MM2S_FAIL
HDMI_COLORBAR_PASS / HDMI_COLORBAR_FAIL
```

## 2026-09-04 分层固件板测步骤

代码已构建到：

```text
E:\competition\2_fpga\0_diaplay_test\vitis\app_component\build\app_component.elf
```

板测流程：

1. 关闭多余串口终端，只保留一个 COM6 `115200-8-N1`。
2. 用 Vitis 正常 Run/Debug 下载当前 ELF。
3. UART 应先出现 `V1_PLATFORM_OK` 和多行 `DDR_ROUND`。
4. DDR 保持阶段耗时约 36 秒，必须看到 `DDR_HOLD_OK SECOND=30` 和 `DDR_PASS`。
5. `DDR_PASS` 后程序自动填彩条并启动 VDMA MM2S。
6. 看到 `VDMA_MM2S_PASS` 和 `HDMI_COLORBAR_RUNNING` 后，人工检查显示器是否为 8 条垂直彩条。
7. 将完整 UART 输出、显示器照片/录屏和 Vitis 控制台保存到当日记录。

自动/人工判定：

- `DDR_PASS`：DDR 软件判定通过；
- `VDMA_MM2S_PASS`：VDMA 寄存器配置、错误位和 frame count 自动判定通过；
- `HDMI_COLORBAR_PASS`：必须由用户肉眼确认 640×480 八彩条后记录；
- 任一 `FAIL`：停止后续阶段，不要进入摄像头。

## 2026-09-04 VDMA 修正后复测步骤

首轮板测已确认 `DDR_PASS`。VDMA 停止原因是固件把 frame-count interrupt 误判为错误，不是 DDR 或 VDMA 地址失败。修正版 ELF 已重建：

```text
E:\competition\2_fpga\0_diaplay_test\vitis\app_component\build\app_component.elf
```

复测时可以跳过人工确认 DDR，直接观察 VDMA 新标记：

```text
VDMA_ONE_FRAME SR=0x00011001 COUNT=1 ERR=0x00000000
VDMA_ONE_FRAME_PASS
VDMA_CONTINUOUS SR=... CR=...
VDMA_MM2S_PASS
HDMI_COLORBAR_RUNNING
```

若出现 `VDMA_ONE_FRAME_PASS`，说明 MM2S 至少完整读取一帧彩条。若随后进入 `HDMI_COLORBAR_RUNNING` 且每 5 秒心跳持续出现，再人工确认显示器为 640×480 八条垂直彩条。确认后记录 `VDMA_MM2S_PASS` 和 `HDMI_COLORBAR_PASS`；若屏幕异常但心跳正常，优先检查 HDMI/VTC/ADV7511 数据格式和时钟，不要回退去调 DDR 或摄像头。

## 2026-09-04 ADV7511 修正后 HDMI 复测步骤

第二次板测已经确认：

```text
DDR_PASS
VDMA_ONE_FRAME_PASS
VDMA_MM2S_PASS
HDMI_COLORBAR_FAIL / HDMI_NO_DISPLAY
```

故障已收敛到 HDMI 输出链路。已修正 ADV7511 配置：

1. 增加 `0x41=0x10` 显式 power-up；
2. 将 `0xAF` 改为 `0x12`，进入 HDMI mode；
3. 写入正确 AVI Infoframe，声明 YCbCr 4:2:2、BT.709、4:3、VIC 1；
4. 设置 `0x44=0x10` 使能 AVI Infoframe；
5. 设置 `0xD6=0xC0`，避免 HPD 自动断电。

已完成：

```text
ModelSim CFG_TEST_PASS: transactions=31 starts=31 stops=31
Vivado ADV_CFG_FIX_VIVADO_PASS
WNS=10.289 ns / WHS=0.024 ns
XSA/SDT/bit 已同步到 2026-09-04 16:05:31
FSBL 已按新 ps7_init.c 清洁重建
app_component.elf 构建通过
launch 使用的 bit/ps7_init.tcl 副本已同步
```

复测步骤：

1. 断开/接通显示器 HDMI，最好先让显示器接在板卡上再给板卡上电。
2. 只保留一个 COM6 `115200-8-N1` 终端。
3. 使用 Vitis 正常 Run/Debug 启动 `app_component`，不要使用 XSCT 绕过。
4. 等待 `VDMA_MM2S_PASS` 和 `HDMI_COLORBAR_RUNNING`。
5. 观察显示器是否出现 640x480 八条垂直彩条。
6. 保存完整 UART 输出为 `display_test_staged_board_uart3.txt`。

判定：

- 显示八彩条：记录 `HDMI_COLORBAR_PASS`，才可进入 S2MM/摄像头阶段；
- 无显示但 UART 心跳继续：保留 UART3 输出，说明后续应加 `cfg_done/cfg_error`、Video Out `locked/underflow` 和 HDMI_INT 状态可读通路；
- 显示同步但颜色异常：优先复查 AVI Infoframe、BT.709 系数和 YCbCr422 16-bit packing。

## 2026-09-04 纯 PL HDMI 彩条测试综合步骤

用户已要求先做不使用 Zynq 的固定彩条测试。在新建 Vivado RTL 工程或现有工程单独 source set 中添加：

1. `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_colorbar_vtc_top.v` 作为顶层；
2. `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\vtc_480p_1ppc.v`；
3. `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_out_adv7511.v` 及其引用的全部 `.sv` 文件；
4. `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_colorbar_vtc_top.xdc`，不要同时启用主工程旧 XDC 中同名的 PS/摄像头约束。

设置 `hdmi_colorbar_vtc_top` 为顶层后正常综合、实现并生成比特流。顶层依赖工程内已配置为 25 MHz 输出的 `clk_wiz_0` IP；下载成功后显示器应显示 640x480、5 条竖彩条，亮度从左到右递减。该测试不加载 PS，不需要 UART，也不需要 Vitis。只有肉眼确认五条彩条后，才能把问题收敛回 PS/DDR/VDMA 与显示后级的组合路径。

**不要在旧 `display_test_zynq7020_school` 工程中直接生成比特流**：其当前顶层仍是 `display_test_wrapper`，已造成修改彩条后画面不变的无效测试。优先使用新增脚本创建独立工程：

```powershell
& F:\vivado2025\2025.2\Vivado\2025.2\bin\vivado.bat -mode batch -source E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\build_hdmi_colorbar_vtc.tcl
```

生成后打开 `E:\competition\2_fpga\0_diaplay_test\proj\hdmi_colorbar_vtc\hdmi_colorbar_vtc.xpr`，确认 RTL 顶层为 `hdmi_colorbar_vtc_top`，再生成比特流。下载后必须确认画面变成 5 条、每条 128 像素的竖彩条；只有此时才能继续分析颜色是否正确。

## 2026-09-04 颜色错配修正复测步骤

实际使用的 `1_zynqtest_2025/project_1` 顶层确认正确，因此继续用该工程复测，但必须避免使用旧 DCP：

1. 先保存/关闭当前显示截图，记录 `hdmi_colorbar_vtc_top.bit` 当前时间。
2. 在 Vivado 中对 `synth_1` 和 `impl_1` 执行 **Reset Runs**，不要只点 Generate Bitstream。
3. 重新综合、实现并生成 bit；确认新 `hdmi_colorbar_vtc_top.bit` 时间晚于 `adv7511_init_table_pkg.sv`。
4. 下载后人工判定 5 条竖彩条。预期从左到右为白、黄、青、绿、品红。
5. 若颜色仍异常，保留照片/bit 时间和 Vivado 运行时间戳；不要再改 DDR/VDMA。
