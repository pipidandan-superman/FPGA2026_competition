# PS VDMA HDMI 改写计划

## 计划状态

本文档是 PS 侧改写计划，不是执行记录。当前不修改 `main.c`、PL、BD、VTC、ADV7511 RTL、约束和比特流。只有获得下一次明确执行授权后，才允许替换：

`E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`

当前已经确认本次使用的比特流就是 HSYNC/VSYNC 低电平版本，不再执行极性修改或重新生成比特流。当前比特流：

`E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.runs\impl_1\display_test_wrapper.bit`

SHA-256：

`0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`

BD/XCI 中的当前 VTC 配置为：

- `GEN_HSYNC_POLARITY=Low`
- `GEN_VSYNC_POLARITY=Low`

## 目标

只改 PS 应用，让 Zynq 先清空显示 DDR 区域，再填入颜色测试图，通过 AXI VDMA MM2S 循环读出并送到 PL 显示。测试期间 S2MM 必须保持停止，避免相机路径写入同一 DDR 区域造成花屏。

目标数据路径：

```text
PS 填 DDR -> AXI VDMA MM2S -> AXI-Stream -> Video Out -> HDMI ADV7511
```

明确不做：

- 不改 PL/BD/RTL/约束。
- 不重新综合、实现或生成比特流。
- 不启动 S2MM。
- 不做相机写入、双缓冲切换或动态图像。
- 不把编译通过、UART 配置通过或寄存器启动通过直接称为 HDMI 板级 PASS。

## 回滚点

替换前已有备份：

`E:\competition\4_metrics\logs\2026-09-07_ps_hdmi_vdma_run01\main_pre_ps_hdmi_vdma.c`

备份 SHA-256：

`4AC73C2C9C4C8B1D6273F08F3CAC6FF608AAE90B1BD0F330FA22A424ACA87B79`

当前 `main.c` 与该备份一致，SHA-256 也为：

`4AC73C2C9C4C8B1D6273F08F3CAC6FF608AAE90B1BD0F330FA22A424ACA87B79`

如果测试失败，只允许在明确授权后用备份文件恢复 `main.c`，不要回退或重建 PL 工程。

## 帧缓冲和地址映射

固定使用以下映射：

| 项目 | 值 |
| --- | ---: |
| 显示缓冲基址 | `0x10000000` |
| 单槽间距 | `0x00100000` |
| 帧槽数量 | 3 |
| 需要清空总长度 | `0x00300000`，即 3 MiB |
| 有效帧大小 | `640 * 480 * 3 = 921600` 字节 |
| 行步距 / HSIZE | `1920` 字节 |
| VSIZE | `480` |

三个 MM2S 起始地址：

| 槽号 | 起始地址 |
| --- | ---: |
| Frame 0 | `0x10000000` |
| Frame 1 | `0x10100000` |
| Frame 2 | `0x10200000` |

每个槽的间距是 1 MiB，大于有效帧 921600 字节；槽间 padding 也必须清零。MM2S 只配置有效几何 `1920 x 480`，padding 不参与有效传输，但清零可避免后续误配置或调试读取时引入歧义。

## VDMA 地址映射

PS 应用继续使用当前 BSP 的：

`XPAR_AXI_VDMA_0_BASEADDR = 0x43000000`

关键寄存器：

| 寄存器 | 偏移 |
| --- | ---: |
| MM2S CR | `0x43000000 + 0x00` |
| MM2S SR | `0x43000000 + 0x04` |
| MM2S FRMSTORE | `0x43000000 + 0x18` |
| MM2S VSIZE | `0x43000000 + 0x50` |
| MM2S HSIZE | `0x43000000 + 0x54` |
| MM2S STRIDE | `0x43000000 + 0x58` |
| MM2S Start Address 1 | `0x43000000 + 0x5C` |
| MM2S Start Address 2 | `0x43000000 + 0x60` |
| MM2S Start Address 3 | `0x43000000 + 0x64` |
| S2MM CR | `0x43000000 + 0x30` |
| S2MM SR | `0x43000000 + 0x34` |

使用的关键位：

- `CR.RUN = 0x00000001`
- `CR.CIRCULAR = 0x00000002`
- `CR.RESET = 0x00000004`
- `SR.ERROR_MASK = 0x00000FF0`
- `SR.IRQ_MASK = 0x00007000`
- `SR.HALTED = 0x00000001`

本次测试 MM2S CR 只写 `RUN | CIRCULAR`，不使用一次传输模式，也不启用 S2MM。

## 颜色格式

当前 PL 转换器把 AXI-Stream 的 `RGB888` 解释为从高到低 `R[23:16], G[15:8], B[7:0]`。VDMA 从 DDR 读出的字节顺序是小端地址递增，因此 PS 必须让每个像素的 DDR 字节顺序为：

```text
低地址: B, G, R :高地址
```

如果按 32 位小端写 DDR，应写成：

```c
pixel = 0x00RRGGBBUL;
```

对应的测试条颜色：

| 条号 | 可见颜色 | 32 位写入值 | DDR 字节顺序 |
| ---: | --- | ---: | --- |
| 0 | White | `0x00FFFFFF` | `FF FF FF` |
| 1 | Black | `0x00000000` | `00 00 00` |
| 2 | Red | `0x00FF0000` | `00 00 FF` |
| 3 | Blue | `0x000000FF` | `FF 00 00` |
| 4 | Green | `0x0000FF00` | `00 FF 00` |

每个色条宽度为 `640 / 5 = 128` 像素。三个帧槽填充完全相同的图案，便于验证 MM2S 三帧循环时不引入颜色或地址偏差。

PL 中的 `pix_frame_display` 可能仍叠加原有白色窗口或方块，这不属于 PS 颜色失败，判断颜色时必须区分背景色条和既有叠加层。

## PS 执行流程

### 1. 启动和基线打印

打印固件版本和关键常量，至少包含：

- `PS_HDMI_VDMA_PLAN_V1`
- `FB_BASE=0x10000000`
- `FB_REGION_BYTES=0x00300000`
- `WIDTH=640`
- `HEIGHT=480`
- `STRIDE=1920`
- `VDMA_BASE=0x43000000`
- 当前比特流 SHA-256

### 2. 先停止并复位两个 VDMA 通道

1. 读取并打印 MM2S、S2MM 的 CR/SR 原始值。
2. 复位 S2MM，等待 `CR.RESET` 自清零。
3. 复位 MM2S，等待 `CR.RESET` 自清零。
4. 写 S2MM SR 清除 error/irq 状态。
5. 写 MM2S SR 清除 error/irq 状态。
6. 再次读取 S2MM CR/SR，确认 S2MM 没有 RUN。

S2MM 只允许复位和状态清理，任何路径都不得置位 S2MM `CR.RUN`。

### 3. 清空 DDR 显示区域

1. 使用 32 位写，把 `0x10000000` 开始的 `0x00300000` 字节全部写 `0x00000000`。
2. 对同一范围执行 D-cache flush。
3. 再执行 D-cache invalidate，确保后续验证读取 DDR 实际内容。
4. 逐 32 位读回比较，必须全部为 0。
5. 打印：

```text
DDR_CLEAR_PASS BASE=0x10000000 BYTES=3145728
```

任何读回非零都立即打印失败地址、期望值、实际值，然后停止；不能继续填图或启动 MM2S。

### 4. 填充颜色测试帧

1. 对三个槽都填充相同的 White / Black / Red / Blue / Green 图案。
2. 每个像素按 32 位值 `0x00RRGGBB` 写入。
3. 只写每个槽的有效 `921600` 字节，不把下一槽开头覆盖；槽间 padding 已在上一步清零。
4. 对 `0x10000000` 到 `0x10300000` 之前的有效写入范围执行 D-cache flush 和 invalidate。
5. 逐像素读回三个槽，验证颜色值、行尾、槽尾边界。
6. 打印：

```text
COLOR_PATTERN_PASS FRAMES=3 PIXELS=921600 BYTES=2764800
```

这里的有效像素总数是 `640 * 480 * 3 = 921600` 像素，有效字节数是 `3 * 921600 = 2764800` 字节。

### 5. 配置 MM2S

配置顺序必须是地址和几何先有效，最后写 VSIZE 触发运行：

1. 确认 MM2S 已复位完成。
2. 清 MM2S SR 的 error/irq 状态。
3. 写 MM2S `FRMSTORE = 3`。
4. 写三帧地址：
   - `0x10000000`
   - `0x10100000`
   - `0x10200000`
5. 写 `STRIDE = 1920`。
6. 写 `HSIZE = 1920`。
7. 写 MM2S `CR = RUN | CIRCULAR`。
8. 最后写 `VSIZE = 480`。
9. 回读 CR、SR、FRMSTORE、三个地址、stride、HSIZE、VSIZE 并打印。

标记：

```text
VDMA_S2MM_STOPPED
VDMA_MM2S_CONFIG_PASS
```

### 6. 首帧确认

启动后轮询 MM2S SR：

- 如果出现 `SR.ERROR_MASK` 非零，立即停止并打印全部寄存器。
- 等待帧计数出现首次完成事件，或至少等待超过一个 640x480@60 帧周期后再检查运行状态。
- 确认 MM2S CR 仍保持 RUN、SR 无错误。
- 打印：

```text
VDMA_MM2S_FIRST_FRAME_PASS SR=0x... COUNT=...
```

### 7. 60 秒稳定性监视

1. 每秒读取一次 MM2S SR/CR。
2. 每秒打印 heartbeat、累计帧计数和 SR。
3. 每次都检查 S2MM CR，确认仍未启动。
4. 连续 60 秒无错误后打印：

```text
VDMA_MM2S_NO_ERROR_60S
PS_HDMI_VDMA_TEST_PASS
```

稳定性判定还必须配合肉眼或照片确认；只有 UART 60 秒无错误，不能单独作为 HDMI 显示板级 PASS。

## 失败处理

出现以下任一情况立即停止，不继续执行下一步：

- DDR 清空读回非零。
- 颜色图案读回错误。
- MM2S 复位超时。
- S2MM 意外进入 RUN。
- MM2S 出现 error、halted 或 CR RUN 丢失。
- 60 秒内出现 tearing、滚动、失步、颜色闪变或花屏。

失败 UART 至少打印：

```text
PS_HDMI_VDMA_FAIL STEP=<step>
MM2S_CR=... MM2S_SR=... S2MM_CR=... S2MM_SR=...
ADDR1=... ADDR2=... ADDR3=...
FRMSTORE=... STRIDE=... HSIZE=... VSIZE=...
```

如果监视器显示红色和蓝色互换，优先复核 DDR 颜色写入是否是 `0x00RRGGBB`，不要先改 PL 转换器。如果完全不同步，停止后比对当前低电平极性比特流、UART 寄存器和照片，不在同一轮实验里叠加新变量。

## 构建和板级验证

执行授权后的顺序：

1. 用替换后的 `main.c` 重新编译 Vitis `app_component`。
2. 记录编译命令、完整输出、返回码和 ELF SHA-256。
3. 编译零错误只是进入硬件测试的条件，不算 PASS。
4. 确认板上是当前比特流，且 SHA-256 等于本文档记录的 `0A9CBC...C271F7`。
5. 通过 JTAG 加载新 ELF，打开 UART 保存完整原始输出。
6. 观察 HDMI 至少 60 秒，拍摄照片并归档。
7. PASS 必须同时满足：
   - DDR clear PASS；
   - 颜色源数据读回 PASS；
   - S2MM 停止；
   - VDMA MM2S 首帧 PASS；
   - 60 秒 UART 无错误；
   - 屏幕稳定显示 640x480p60；
   - White / Black / Red / Blue / Green 颜色正确；
   - 无花屏、撕裂、滚动或失步。

原始 UART、编译日志、ELF/比特流哈希和照片必须放到新的：

`E:\competition\4_metrics\logs\2026-09-07_<run-name>\`

并由当天 `7_logs/2026-09-07/03_validation_summary.md` 链接。

## 授权边界

本文档批准后仍不等于执行授权。写入 `main.c` 前需要用户再次明确同意，例如要求“按计划替换 PS 代码”。执行时只替换 `app_component/src/main.c`，不触碰其他工程文件。

## 11:45 执行状态更新

用户已授权按本计划写入 PS 代码。`E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c` 已替换为计划实现，SHA-256 为 `11754557F07AA3A379038967DD1E8EE1723ADDC392716BF9F928ADE022E28A5E`。截至该时间未编译、未下板、未声称 UART/HDMI PASS。本文档以上内容保留执行前的改写要求，用于核对代码和后续验收。
