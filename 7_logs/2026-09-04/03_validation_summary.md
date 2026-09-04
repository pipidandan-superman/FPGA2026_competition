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
