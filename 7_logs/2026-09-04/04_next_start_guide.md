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
