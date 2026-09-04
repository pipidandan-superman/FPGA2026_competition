# 验证记录

## 今日前已验证

- RAW UART 板级发送：PASS，证据位于 `E:\competition\4_metrics\logs\2026-09-03_vitis_uart_minimal_raw_tx_run32`。
- HDMI `hdmi_out_adv7511` 顶层 ModelSim：PASS，16/16 像素与 18/18 ADV7511 写入。
- Vivado 实现与时序：PASS，WNS `10.551 ns`，TNS `0.000 ns`；该结论属于当前已归档工程状态，仍需与新测试固件配对复测。
- 参考工程源码中存在 640×480 三缓冲 VDMA 彩条流程和独立 MM2S 直显/DDR 回读流程；今日只作为模板，不视为新平台板级结果。

## 今日待验证

| 编号 | 项目 | Pass 判定 | Fail 处理 |
|---|---|---|---|
| V1 | bit/XSA/VDMA/DDR 地址一致性 | 版本、地址、时钟记录完整且互相匹配 | 停止下载，重建平台 |
| V2 | DDR pattern 读写 | 6 类 pattern 各 3 轮零错误 | 保存首错误地址和期望/实际值 |
| V3 | DDR 保持/刷新间接证据 | 1 s、5 s、30 s 保持后零错误 | 停止 VDMA 调试，回查 PS DDR 配置 |
| V4 | VDMA MM2S 寄存器 | 配置回读一致，无错误位 | 输出完整寄存器快照 |
| V5 | MM2S frame count | 10 秒约递增 600 帧，60 Hz 平台可接受 ±10% | 检查 VTC/HDMI handshake |
| V6 | DDR 到 HDMI 彩条 | 静态 640×480 八彩条正确稳定 | 先区分 DDR 数据、VDMA 读、HDMI 时序 |
| V7 | S2MM 独立数据 | 有 PL 测试图源时回读一致 | 若无源，只记录寄存器预检，不判 PASS |

## 必须保留的证据

每个硬件运行建立一个独立记录目录，例如：

```text
E:\competition\4_metrics\logs\2026-09-04_vitis_ddr_vdma_stage_test_runNN\
```

最低证据：

- 完整 UART 原始输出，不截断失败前后内容。
- Vitis/SDK 构建完整控制台输出。
- 下载或运行命令完整日志。
- HDMI 显示照片或截图，带分辨率与时间标记。
- DDR 测试若失败，记录首错误地址、地址分布、pattern 名称、期望值、实际值和重测结果。
- VDMA 失败时，记录 VDMACR、VDMASR、start address、stride、HSIZE、VSIZE、frame count 的完整十六进制快照。

## 结果占位

今日尚未执行新的 DDR、VDMA 或 HDMI 板级验证。

```text
V1: PENDING
V2: PENDING
V3: PENDING
V4: PENDING
V5: PENDING
V6: PENDING
V7: PENDING
```

最终结论必须以 `DDR_PASS`、`VDMA_MM2S_PASS`、`HDMI_COLORBAR_PASS` 和有源 `VDMA_S2MM_PASS` 等串口稳定标记为准。

## 2026-09-04 代码与构建验证

已完成：

- 串口无输出根因记录并入今日计划；`TXFULL` 正确掩码为 `0x10`。
- `app_component/src/main.c` 已实现 UART 直写、DDR pattern/保持测试、三帧 640×480 packed RGB888 彩条、VDMA MM2S-only 配置与状态监视。
- 当前实现按本 BD `TDATA_WIDTH=24` 使用 `HSIZE/STRIDE=1920`，S2MM 保持禁用。
- Ninja 交叉编译通过，`app_component.elf` size：`text=36220`，`data=1432`，`bss=22988`。
- 第一次构建曾出现 `arm-none-eabi-size not recognized`，原因是交叉工具链 bin 目录不在当前 shell PATH；补入 `F:\vivado2025\2025.2\Vitis\gnu\aarch32\nt\gcc-arm-none-eabi\bin` 后链接成功。该问题不是 C 源码错误。

## 2026-09-04 UART-first 修正与构建

根据用户反馈，执行顺序已改为先测串口：

- 新增 `RUN_UART_TEST`、`UART_TEST_HEARTBEATS`、`UART_TEST_SETTLE_SECONDS`。
- 上电先输出 5 次 `UART_OK INDEX=n`，再输出 `UART_TEST_PASS`。
- 随后 5 秒倒计时，再进入已有 DDR 阶段；DDR 通过后才进入 VDMA MM2S。
- 修复 Vitis clangd 提示的 `Wint-to-pointer-cast`：`uint32_t` 地址先转换为 `uintptr_t` 再转为指针。
- 重建通过，最新 `app_component.elf` size：`text=36540`，`data=1432`，`bss=22988`。
- 板级 UART-first 运行仍为 PENDING；不能根据构建通过宣称 UART、DDR 或 VDMA PASS。

## 2026-09-04 UART 再次无输出的分流

当前 COM6 只显示 `Opened with baud rate: 115200`，无应用输出。昨天的可用经验不是普通 Vitis Run，而是 XSCT 绕过流程：`connect` 后选择 Cortex-A9 `targets 2`，`stop`/`rst -processor`，手动 `source ps7_init.tcl` 并执行 `ps7_init`/`ps7_post_config`，先用 `mwr` 向 UART1 FIFO 写 `XSCT OK`，再 `dow app_component.elf` 和 `con`。这能区分是 GUI 启动链问题、应用问题还是 UART 硬件路径问题。

已固化 bypass 脚本：

```text
E:\competition\4_metrics\logs\2026-09-04_vitis_uart_bypass_run33\run_uart_bypass.tcl
```

执行前必须先终止当前 Vitis debug 会话，避免 JTAG 目标被 GUI 占用。然后运行：

```powershell
& F:\vivado2025\2025.2\Vitis\bin\xsct.bat E:\competition\4_metrics\logs\2026-09-04_vitis_uart_bypass_run33\run_uart_bypass.tcl
```

判定：

- COM6 先出现 `XSCT OK`：UART 硬件路径和 PS7 初始化通过；若后续无 `UART_TEST_BEGIN`，问题在应用下载/运行或当前固件。
- COM6 完全无 `XSCT OK`：不要继续调应用；先核对 COM6、USB UART、MIO48/49、PS7 初始化和是否有多个终端占用。
- 两种输出都出现：确认 bypass 流程可用，再记录当前 Vitis Run 与 XSCT 的具体配置差异。

## 2026-09-04 正常 Vitis 启动链根因修正

发现普通 Vitis launch 的 `ps7InitTclFile` 仍指向旧文件：

```text
app_component/_ide/psinit/ps7_init.tcl       2026-09-03 16:15
display_test_wrapper.xsa                     2026-09-03 23:18
display_test_platform/hw/sdt/ps7_init.tcl    2026-09-03 23:19
```

这就是“XSCT 手动流程可用、普通 Vitis 启动无输出”的主要原因：正常流程在 FSBL/应用前又执行了 DDR 修正前的旧 PS7 初始化，可能把 DDR 配置改回错误状态，导致应用在进入 `main()` 前失败。已将 launch 配置改为当前 XSA 导出的：

```text
display_test_platform/hw/sdt/ps7_init.tcl
```

进一步核对后，launch 引用的 `.bit` 也属于旧拷贝：

| 文件 | 时间 | SHA256 前缀 | 判定 |
|---|---:|---|---|
| `app_component/_ide/bitstream/display_test_wrapper.bit` | 2026-09-03 16:15 | `AB465271...` | 旧，禁止 launch 使用 |
| `display_test_platform/hw/sdt/display_test_wrapper.bit` | 2026-09-03 23:19 | `18BA5726...` | 与当前 XSA 对齐 |

因此已同时把 launch 配置修正为当前 `display_test_platform/hw/sdt/display_test_wrapper.bit` 和当前 `display_test_platform/hw/sdt/ps7_init.tcl`。FSBL 位于 `display_test_platform/export/display_test_platform/sw/boot/fsbl.elf`，时间为 2026-09-04 10:58，晚于当前 XSA，暂判定为已重建。正常 Vitis Run 的下一步验收是：不使用 XSCT 手动写入，直接 Run/Debug 后 COM6 出现 `UART_TEST_BEGIN`、5 次 `UART_OK` 和 `UART_TEST_PASS`。

继续审计发现 FSBL 虽然在 2026-09-04 10:58 重建，但它实际编译的 `zynq_fsbl/ps7_init.c` 仍是 2026-09-03 16:15 旧文件；当前 XSA 生成的 `hw/sdt/ps7_init.c` 为 23:19，两者 SHA256 不同。已将当前 XSA 生成的 `ps7_init.c` 对齐到 FSBL 源并重建。

FSBL 重建通过：

```text
text=55977  data=7344  bss=67988
zynq_fsbl/ps7_init.c SHA256 = 677E9388...  与 hw/sdt/ps7_init.c MATCH
zynq_fsbl/build/fsbl.elf SHA256 = 76CBC886...
export/.../sw/boot/fsbl.elf  已同步为 76CBC886...
```

同时将旧位置的 `.bit` 和 `ps7_init.tcl` 缓存同步为当前 XSA 产物，防止 IDE 后续重新生成 launch 时又回退到旧文件。现在正常流程四件套均为当前版本：

| Launch 依赖 | 状态 |
|---|---|
| `.bit` | 当前 XSA 对应 `18BA5726...` |
| FSBL | 当前 XSA `ps7_init.c` 重建后 `76CBC886...` |
| `ps7_init.tcl` | 当前 XSA 对应 `4059D0D4...` |
| `app_component.elf` | 当前源码构建 PASS |

最终仍必须通过 Vitis 正常 Run/Debug 复测；XSCT 只作为旁证，不算本次修复的验收。

## 2026-09-04 UART 自初始化修复

正常 Run 再次无输出后，为了避免应用串口输出继续依赖 launch 阶段的 PS7 初始化，已把 UART1 硬件初始化移入 `main()` 第一行：

- 解锁 SLCR；
- 启用 UART1 参考时钟，`UART_CLK_CTRL` 目标值 `0x00001002`；
- 配置 MIO48 为 UART1 TX，`0x000012E0`；
- 配置 MIO49 为 UART1 RX，`0x000012E1`；
- 锁定 SLCR；
- 配置 UART1 为 8-N-1，`BAUDGEN=0x7C`，`BAUDDIV=0x06`，115200 baud；
- 使能 RX/TX；
- 然后输出 `UART_TEST_BEGIN` 和 5 次 `UART_OK`。

这些寄存器值与 2026-09-03 direct XSCT 板级测试记录一致。该修复属于正常 Vitis Run 应用内的初始化，不属于绕过流程。

重建通过：

```text
text=36764  data=1432  bss=22988
```

下一次验收必须完全通过 Vitis 正常 Run/Debug 执行；COM6 只允许一个终端占用。若仍无输出，失败点已经不是 UART 参数依赖，需要停止 CPU 后记录 PC、LR、SP 和 UART1 寄存器，判断 ELF 是否被执行。

同时更新 fallback 脚本使用同一份新脚本。下一步必须通过 Vitis 正常 Debug/Run 复测；XSCT 只应作为旁证，不再作为最终串口验证。

板级运行尚未执行，因此不得根据编译通过宣称 DDR、VDMA 或 HDMI 显示 PASS。首次硬件运行必须完整保存 UART、Vitis/XSCT 控制台和显示器照片。

## 2026-09-04 PS-only 最小 UART 应用编译修复

工程：`E:\competition\2_fpga\1_zynqtest_2025\vitis`。

Vitis 构建失败的直接原因不是 UART 代码，而是应用 CMake 配置阶段引用了不存在的 `app_component/src/linker_files/lscript_a9.ld.in`；同时应用目录已有有效的 `src/lscript.ld`。本次修正为：只要该文件存在且没有显式传入自定义 linker，CMake 直接使用 `src/lscript.ld`，不再访问缺失模板。

为保持正常 Vitis/BSP 执行流程，还做了以下修正：

- 删除手动 `-nostdlib` 用的 `startup.c`，避免与 `libxilstandalone.a` 中的 `_vector_table` / `_start` 重复；
- `main.c` 改为调用 `xil_printf()`，由 standalone BSP 输出到 `STDOUT_BASEADDRESS = 0xE0001000`；
- 构建后统计 ELF 时使用编译器目录中的完整 `arm-none-eabi-size.exe` 路径，避免依赖 host shell 的 PATH。

清理后重新构建通过，完整原始日志保存在本目录 `zynqtest_2025_build_log.txt`：

```text
text=27273  data=1416  bss=22960
Entry point address: 0x100000
00100000 T _vector_table
00100ec8 T _start
001004a8 T main
```

当前只完成编译闭环；板级 UART、DDR 和后续阶段仍未通过本次新应用板级运行验证，不能宣称 PASS。

## 2026-09-04 PS-only UART 板级 PASS

使用 Vitis 正常流程运行后，COM6 `115200-8-N1` 连续收到：

```text
UART OK 0
UART OK 1
UART OK 2
UART OK 3
UART OK 4
```

原始截图证据：`E:\competition\7_logs\2026-09-04\zynqtest_uart_com6_pass.png`。

结论：PS-only 最小应用的 BSP 启动、链接脚本、ELF 下载执行和 UART1 输出链路板级 PASS。该结果只验证 UART，不推断 DDR、VDMA 或 HDMI 状态。

## 2026-09-04 UART 结论边界解释

PS-only UART PASS 证明的是：Zynq PS 供电/时钟可运行、MIO48/49 到 UART1 的外部通路正确、COM6 和 115200-8-N1 设置正确、当前 Vitis 正常 Run/Debug 能下载并执行最小 BSP ELF。

它不能证明主 HDMI 工程中的每一项 PS 配置都正确。原主工程早期无打印是多个问题叠加：

1. DDR 型号/时序配置曾与 EES-331 实际硬件不匹配；C 启动代码、栈、BSP 数据都可能依赖 DDR，因此可能在到达 `printf`/UART 输出前就失稳。
2. 主工程 Vitis Run 曾引用旧缓存：`_ide/psinit/ps7_init.tcl` 和 `_ide/bitstream/*.bit` 早于修正后的 XSA；FSBL 也曾用旧 `ps7_init.c` 重建，导致正常启动链重新写入错误 DDR 配置。
3. 早期裸 UART 代码把 UART 状态寄存器 `TXFULL` 误用为 `bit3`；该位实际是 `TXEMPTY`，正确 `TXFULL` 是 `bit4(0x10)`，因此程序曾停在 FIFO 等待循环，无法发出首个字符。
4. PS-only 工程移除了 PL bit/VDMA/DDR 缓冲/主工程旧 launch 产物这些变量，只保留最小 BSP 启动和 UART 输出，所以适合做隔离验证。

因此，正确结论不是“2025 Vitis 不可用”，也不是“主工程已经完整 PASS”，而是：2025 Vitis 和 PS 基础 UART 通路可用；主工程必须重新构建/运行，并继续按 UART、DDR、VDMA、HDMI 分层判定。

## 2026-09-04 主工程 Vitis 重建为最小 UART 复现

用户已删除原主工程 Vitis 目录，并重新从当前 `display_test_wrapper.xsa` 生成：

```text
E:\competition\2_fpga\0_diaplay_test\vitis
```

本次复现结果：

- `app_component/src/main.c` 与已通过板级验证的 PS-only UART 程序逐字节一致，SHA256 为 `4F4AAF03...`；
- `app_component/src/CMakeLists.txt` 与 PS-only 工程一致，SHA256 为 `BB43C508...`；
- 使用 `empyro build_bsp` 构建 standalone BSP，并把生成库/头文件同步到 export 域；
- 使用 `empyro build_app` 正常流程干净重建应用；
- `zynq_fsbl/ps7_init.c` 与当前 `hw/sdt/ps7_init.c` SHA256 均为 `677E9388...`；
- `_ide/psinit/ps7_init.tcl` 与 `hw/sdt/ps7_init.tcl` SHA256 均为 `4059D0D4...`；
- `_ide/bitstream/display_test_wrapper.bit` 与 `hw/sdt/display_test_wrapper.bit` SHA256 均为 `18BA5726...`；
- FSBL 干净重建通过，`zynq_fsbl/build/fsbl.elf` 与 export boot 目录下 `fsbl.elf` SHA256 均为 `2A28DE19...`。

应用干净构建通过：

```text
text=27273  data=1416  bss=22960
Entry point address: 0x100000
```

完整应用构建日志：`E:\competition\7_logs\2026-09-04\display_test_uart_rebuild_build_log.txt`。  
FSBL 重建日志：`E:\competition\7_logs\2026-09-04\display_test_fsbl_rebuild_build_log.txt`。

当前完成的是编译和启动链产物闭环；新主工程 UART 仍需板级运行确认，不能因工程复现成功而直接宣称板级 UART PASS。

## 2026-09-04 新主工程 UART 板级 PASS

用户确认新主工程 `E:\competition\2_fpga\0_diaplay_test\vitis` 已通过 Vitis 正常流程打印串口数据。

判定结论：

```text
DISPLAY_TEST_UART_BOARD_PASS
```

本次通过说明新 XSA 对应的 `.bit`、FSBL、`ps7_init.tcl`、standalone BSP、链接脚本、ELF 下载执行和 UART1 输出链路闭环正常。该结果仍只覆盖 UART，不推断 DDR、VDMA 或 HDMI。

证据状态：当前记录来自用户板级确认；后续硬件验证应继续保存完整 COM6 原始文本或截图，作为正式证据文件归档。

## 2026-09-04 分层验证固件代码就绪

主工程应用已从最小 UART 固件扩展为顺序化测试固件：

```text
UART → DDR 6 pattern × 3 rounds → DDR 1/5/30 s hold → colorbar fill/verify → VDMA MM2S → HDMI
```

关键实现：

- DDR 测试范围：`0x10000000 ~ 0x102FFFFF`，共 3 MiB；
- VDMA 三帧缓存：`0x10000000 / 0x10100000 / 0x10200000`；
- 显示格式：640×480 packed RGB888，每帧 921600 字节；
- VDMA 基址：`0x43000000`，MM2S/S2MM AXI-Stream 宽度 24 bit；
- DDR 任一读写/保持错误立即输出 `DDR_FAIL` 并停止；
- 彩条回读失败立即输出 `VDMA_MM2S_FAIL REASON=COLORBAR_VERIFY`；
- VDMA 启动后检查 frame count 递增和错误位；
- `VDMA_MM2S_PASS` 后进入 `HDMI_COLORBAR_RUNNING` 心跳，等待人工确认屏幕彩条。

干净重建通过：

```text
text=35693  data=1428  bss=22996
Entry point address: 0x100000
```

完整构建日志：`E:\competition\7_logs\2026-09-04\display_test_staged_fw_build_log.txt`。  
板级运行待执行，不能提前判定 DDR、VDMA 或 HDMI PASS。

## 2026-09-04 DDR PASS 与 VDMA 首轮误判分析

用户完成首次分层固件板测，完整 COM6 输出保存为：

```text
E:\competition\7_logs\2026-09-04\display_test_staged_board_uart1.txt
```

板级判定：

```text
DDR_PASS
```

DDR 六种 pattern、每种 3 轮读写全部无错误；1 秒到 30 秒保持回读也全部无错误。因此 DDR 读写与保持测试正式通过。

VDMA 输出为：

```text
VDMA_REG MM2S_CR=0x00010013 MM2S_SR=0x00010000
VDMA_COUNT FIRST=1 SECOND=1 SR=0x00011001
VDMA_MM2S_FAIL REASON=NOT_STREAMING
VDMA_REG MM2S_CR=0x00010012 MM2S_SR=0x00011001
```

逐位分析后确认这不是 VDMA/DDR 地址失败：

- SR `bit0=1`：完成一帧后通道 halt；
- SR `bit12=0x1000`：frame-count interrupt；
- SR `bit16=1`：frame count 为 1；
- CR `bit16=1`：frame-count threshold 为 1；
- CR 从 `RUN` 变为清除：这是 frame-count 模式完成一帧后的预期行为；
- 真正硬件错误掩码应为 `0x00000FF0`，旧固件误把 `0x00007000` 中断位也纳入错误判断。

因此首轮实际结果应为：MM2S 成功传输一帧后按配置停止；固件错误地把正常 frame-count 中断识别为 `NOT_STREAMING`。

已修正流程：

1. 先使能 frame-count 并确认至少完成一帧，输出 `VDMA_ONE_FRAME_PASS`；
2. 复位 MM2S 后改用 `RUN | CIRCULAR`，不再设置 frame-count；
3. 检查连续模式运行位保持且硬件错误掩码 `0x00000FF0` 为零；
4. 通过后再进入 HDMI 心跳观察。

修正后干净重建通过：

```text
text=35985  data=1428  bss=22996
Entry point address: 0x100000
```

构建日志：`E:\competition\7_logs\2026-09-04\display_test_vdma_fix_build_log.txt`。

## 2026-09-04 VDMA PASS、HDMI FAIL 与 ADV7511 配置修正

用户完成 VDMA 修正后的第二次分层固件板测，完整 COM6 输出保存为：

```text
E:\competition\7_logs\2026-09-04\display_test_staged_board_uart2.txt
```

板级判定：

```text
DDR_PASS
VDMA_ONE_FRAME_PASS
VDMA_MM2S_PASS
HDMI_COLORBAR_FAIL / HDMI_NO_DISPLAY
```

证据要点：

```text
DDR_HOLD_OK SECOND=30
DDR_PASS
VDMA_ONE_FRAME SR=0x00011001 COUNT=1 ERR=0x00000000
VDMA_ONE_FRAME_PASS
VDMA_CONTINUOUS SR=0x00011000 CR=0x00010003
VDMA_MM2S_PASS
HDMI_HEARTBEAT=1..11 FRAMES=1 SR=0x00011000
```

`VDMA_MM2S_PASS` 后显示器仍未点亮，因此故障范围收敛到 HDMI 输出链路；不能回退 DDR 或 VDMA。检查现有 ADV7511 初始化表后发现三个确定问题：

1. 缺少 `0x41=0x10`，发送器没有显式 power-up；
2. `0xAF` 只有 `0x10`，按 Linux ADV7511 驱动定义 `mode mask=0x2`，实际仍是 DVI mode，不是 HDMI mode；
3. AVI Infoframe 没有声明 YCbCr 4:2:2 / BT.709 / 640x480@60，也没有使能 AVI 包。

已按 HDMI 1.4 AVI Infoframe 规则更新初始化表：

```text
0x41=0x10          power up
0x52..0x5E         AVI infoframe
0x54=0x78          checksum
0x55=0x59          YCbCr 4:2:2 + active aspect valid
0x56=0x99          BT.709 + 4:3 + active 4:3
0x57=0x04          limited quantization
0x58=0x01          VIC 1 = 640x480@60
0x44=0x10          enable AVI infoframe
0xAF=0x12          HDMI mode
```

另外补充 `0xD6=0xC0`，将 HPD source 设置为 none，避免 HPD 自动控制把已配置发送器断电。初始化表从 18 项更新为 31 项。ModelSim 配置序列仿真结果：

```text
CFG_TEST_PASS: transactions=31 starts=31 stops=31
```

证据目录：

```text
E:\competition\7_logs\2026-09-04\hdmi_adv_cfg_fix_sim_run01
```

## 2026-09-04 第三次 HDMI 失败后的输入样式修正与 M_AXIS 证据强化

第二次 HDMI 复测仍无显示，但 `VDMA_ONE_FRAME_PASS` 已出现。进一步核对 ADV7511 Linux 驱动寄存器映射与 `rgb2ycbcr422` 打包方式，发现上一次配置仍有一个确定错误：

```text
0x16=0x30  YCbCr 422, 8 bit/component, INPUT STYLE=0
0x16=0x38  YCbCr 422, 8 bit/component, INPUT STYLE=1
```

`0x30` 的 style 字段是无效值；当前 RTL 输出为 `{Y, alternating Cb/Cr}`，对应 ADV7511 Style 1，因此必须使用 `0x38`。

同时补齐 AVI Infoframe 更新控制：

```text
0x4A=0x40  更新 AVI Infoframe
0x52..0x5E AVI Infoframe 内容
0x4A=0x00  使用更新后的 AVI Infoframe
0x44=0x10  使能 AVI Infoframe
```

初始化表现在为 33 项；`adv7511_iic_data_xfer` 的表索引扩宽到 6 bit，并修正 33 项时最后索引比较被截断的问题。ModelSim 结果：

```text
CFG_TEST_PASS: transactions=33 starts=33 stops=33
```

证据目录：`E:\competition\7_logs\2026-09-04\hdmi_adv_input_style_sim_run03`。

M_AXIS 证据判定说明：PS 不能直接读取 AXI-Stream 线上的波形或数据值；要观察 `M_AXIS_MM2S_TDATA/TVALID/TREADY` 必须增加 PL 侧采样逻辑、AXI GPIO 或 ILA。但可以通过 VDMA 寄存器做协议级判定：源数据由 PS 独立写入并回读校验；VDMA 单帧模式配置为 1 frame；只有当 MM2S 完整通过 M_AXIS 交付一帧后，frame count 才会变成 1 且通道按配置 halt。固件已改为最多 5 秒轮询该条件，成功后回读源数据，并输出：

```text
VDMA_STREAM_EVIDENCE SOURCE_BYTES=921600 AXIS_WORDS=307200
M_AXIS_MM2S_FRAME_DELIVERED SOURCE=PS_DDR FRAME_COUNT=1 ERR=0
```

应用重建通过：

```text
text=36465 data=1428 bss=22996
```

构建日志：`E:\competition\7_logs\2026-09-04\display_test_axis_evidence_app_build_log.txt`。

## 2026-09-04 第三次复测无显示的下载链路检查

用户报告第三次 HDMI 仍无显示。检查发现 Vitis launch 配置仍加载旧副本 bit：

```text
app_component/_ide/bitstream/display_test_wrapper.bit
LastWriteTime=2026-09-04 16:05:31
SHA256=01965B710144F2A2808C8031926DA2A6CDBCEC3AD3CB230F727AFA66FB8BC580

display_test_plat/hw/sdt/display_test_wrapper.bit
LastWriteTime=2026-09-04 16:28:10
SHA256=34ADC74044E8C9B84C383349A5EBC6E2E553472A3E5A7705863EE604B8E7CDE2
```

因此第三次复测尚未证明 `0x16=0x38` 和 AVI Infoframe 更新控制有效。已将 `launch.json` 改为直接加载：

```text
display_test_plat/hw/sdt/display_test_wrapper.bit
display_test_plat/hw/sdt/ps7_init.tcl
```

并同步副本完成校验。下一次必须先关闭旧 COM6/旧调试会话，重新 Run；UART 中应看到 `M_AXIS_MM2S_FRAME_DELIVERED`。若新 bit 下仍无显示，则需要增加 `cfg_done/cfg_error`、`v_axi4s_vid_out locked/underflow/overflow` 和 HDMI_INT 的 AXI GPIO 状态读取。

Vivado 重新综合、实现和 bitstream 已通过，关键结果：

```text
ADV_CFG_FIX_VIVADO_PASS
WNS=10.289 ns
WHS=0.024 ns
```

完整 Vivado 日志位于 `E:\competition\7_logs\2026-09-04\hdmi_adv_cfg_fix_vivado_run02`。新 XSA 已导出，Vitis 平台 SDT/bit/`ps7_init` 已重新生成到 16:05:31，FSBL 已从当前 `ps7_init.c` 清洁重建并同步到 platform export。应用构建通过，当前 ELF 与分层测试固件一致。下一步必须重新板测 HDMI；只有用户确认 640x480 八彩条后才能记录 `HDMI_COLORBAR_PASS`。

## 2026-09-04 纯 PL HDMI 彩条测试代码就绪

为绕开 PS/DDR/VDMA 交叉影响，新增无 Zynq 的 480p HDMI 隔离测试：

- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_colorbar_vtc_top.v`：100 MHz 输入用户已配置的 `clk_wiz_0` 25 MHz 输出，实例化 VTC、五条竖彩条和现有 `hdmi_out_adv7511`。
- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\vtc_480p_1ppc.v`：1 pixel/clock、640x480@60，H/V 同步均输出低有效，坐标与 DE 同拍。
- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_colorbar_vtc_top.xdc`：仅包含 M19 100 MHz、L18 低有效复位和 EES-331 HDMI 引脚。

当前静态核对通过：H/V 总时序为 800x525，DE 覆盖 640x480，五条彩条每条 128 像素，颜色按白、黄、青、绿、品红排列，亮度从左到右递减；ADV7511 继续使用 RGB888 转 YCbCr422 16-bit Style 1 和 33 项 I2C 初始化表。尚未综合、生成比特流或板级显示验证；不能据此判定 HDMI PASS。

## 2026-09-04 纯 PL 彩条首次板测无效

用户板测可点亮但颜色不匹配，且修改前后画面不变。检查 `display_test_zynq7020_school.xpr` 发现 `sources_1` 顶层仍为 `display_test_wrapper`，新增 `hdmi_colorbar_vtc_top` 未成为当前综合顶层；因此本次显示来自旧 BD/PS/VDMA 链路，不是纯 PL 彩条测试结果。该板测不能用于判定颜色转换或 ADV7511 配置。

用户随后确认实际综合工程是 `E:\competition\2_fpga\1_zynqtest_2025\project_1\project_1.xpr`。该工程顶层确认为 `hdmi_colorbar_vtc_top`，因此顶层无误。进一步核对 ADV7511/Linux 驱动寄存器映射，发现颜色错配的直接原因是初始化表字段错误：

- `0x16=0x38`：D7 为 0，ADV7511 仍按 RGB/YCbCr444 输入解释外部总线；YCbCr422 Style 1 应为 `0xB9`，其中 D7=1、D0=1。
- AVI Infoframe `0x55=0x59` 的 Y 字段声明为 YCbCr444；YCbCr422 应写 `0x29`。
- AVI Infoframe `0x57=0x04` 声明 VIC4（720p）；640x480@60 应写 VIC1 `0x01`。
- 上述 PB1/PB3 变更后，Infoframe checksum 由 `0x78` 修正为 `0xAB`。

已修改 `adv7511_init_table_pkg.sv`。当前证据支持“寄存器解释导致颜色错配”，而不是 ADV7511 内部测试图案覆盖外部像素；该初始化表中 `0x55~0x5E` 属于 AVI Infoframe 寄存器，不是内部彩条发生器。下一步必须在 `1_zynqtest_2025/project_1` 中 Reset Runs 后重新综合、实现、生成 bit，并确认新 bit 时间晚于所有源码时间。
