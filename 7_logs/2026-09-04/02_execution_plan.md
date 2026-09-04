# 执行计划

## 阶段 0：平台一致性检查

1. 记录本次要下载的 `.bit`、`.xsa`、Vitis 平台名、生成时间和 Vivado/Vitis 版本。
2. 核对当前 BD 中 `axi_vdma_0` 基址是否仍为 `0x43000000`；以生成后的 `xparameters.h` 为准，不用硬编码替代。
3. 核对 DDR 有效地址 `0x00100000` 至 `0x1FFFFFFF`；测试区固定使用 `0x10000000` 起，并确认不与当前链接脚本栈、堆、代码或保留外设缓冲重叠。
4. 核对显示时序为 640×480@60，PL 输入像素时钟与 HDMI/VTC/VDMA 参数一致。

## 阶段 1：DDR 数据完整性与保持测试

### 测试实现

- 当前实现集中在 `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`，保留 `RUN_DDR_TEST` 和 `RUN_VDMA_MM2S` 编译期开关。
- 使用 `Xil_DCacheFlushRange()`/`Xil_DCacheInvalidateRange()` 管理测试区缓存，或先关闭 D-Cache 简化第一版判定。
- 已实现测试范围为 `0x10000000` 起 `0x00300000` 字节，按 1 MiB 间距覆盖三个 640×480 packed RGB888 帧缓冲。
- pattern：
  1. `0x00000000`
  2. `0xFFFFFFFF`
  3. `0xAAAAAAAA`
  4. `0x55555555`
  5. 地址指纹 `(address ^ 0xA5A5A5A5)`
  6. 递增计数

### 阶段 0：UART 前置测试

当前默认流程先运行 UART，再进入 DDR：

1. 打印测试头和 `V1_PLATFORM`。
2. 打印 `UART_TEST_BEGIN COUNT=5`。
3. 每秒输出一次 `UART_OK INDEX=n`。
4. 输出 `UART_TEST_PASS`。
5. 等待 5 秒，倒计时 `NEXT_STAGE_IN=n`，随后进入 DDR。

观察规则：

- 只看到测试头但没有 `UART_OK`，说明早段执行或 UART FIFO 等待异常。
- 看到 5 次 `UART_OK` 且有 `UART_TEST_PASS`，才允许继续判定后续 DDR/VDMA 结果。
- 若只想隔离 UART，将 `RUN_DDR_TEST` 和 `RUN_VDMA_MM2S` 都改为 `0`。

### 执行顺序

1. 写入 pattern。
2. flush 到 DDR。
3. invalidate CPU 缓存。
4. CPU 回读逐字比较。
5. 每个 pattern 连续测试至少 3 次。
6. 短时保持 1 s、5 s、30 s 后重复回读，输出错误地址数量、首错误地址和期望/实际值。

### 判定

- PASS：所有 pattern 三轮零错误，三次保持测试零错误，UART 输出 `DDR_PASS`。
- FAIL：出现任一固定地址、固定位型错误；UART 输出 `DDR_FAIL`，冻结后续阶段。

### 当前代码实现差异

当前 BD `xparameters.h` 显示 `XPAR_AXI_VDMA_0_MM2S_TDATA_WIDTH=24`，因此当前实现使用 packed RGB888：

- 三个帧地址为 `0x10000000`、`0x10100000`、`0x10200000`；
- `FRAME_BYTES=921600`；
- `VDMA HSIZE=1920`；
- `VDMA STRIDE=1920`；
- `VDMA VSIZE=480`。

`RUN_DDR_TEST=0` 可执行 DDR-only 分支；`RUN_VDMA_MM2S=0` 可阻止 VDMA/HDMI 启动。默认两阶段顺序执行，但 DDR FAIL 时不会启动 VDMA。

### DDR 刷新说明

PS DDR controller 的刷新由 `ps7_init`/FSBL 阶段配置，应用软件通常无法直接读到一个“刷新成功”标志。这里的软件判定采用长保持回读作为间接证据。若短时读写 PASS 但保持测试周期性失败，应回到 `ps7_init`、DDR 时序、板级供电和温度环境检查，而不是继续调 VDMA。

## 阶段 2：VDMA MM2S 寄存器与读通道预检

1. 复位 MM2S，等待 reset bit 自清除。
2. 写 `START_ADDR_1/2/3`、`FRMDLY_STRIDE`、`HSIZE`；最后写 `VSIZE` 启动。
3. 回读全部寄存器并与期望值比较。
4. 读取 `VDMASR`，确认无 `DMAINTERR/SLVERR/DECERR/SOFINTERR/EOFINTERR/SGINTERR`。
5. 每 0.5 s 或 1 s 读取一次 frame count，至少连续 10 次递增；建议 60 Hz 下约 10 s 内递增约 600 帧。
6. UART 输出 `VDMA_MM2S_PASS` 或 `VDMA_MM2S_FAIL`，失败时打印寄存器快照。

## 阶段 3：DDR 彩条直送 HDMI

1. 只填充 `FRAME_BUFFER_1`；`FRAME_BUFFER_2/3` 可填充不同边框或同一彩条用于后续确认。
2. VDMA 只启动 MM2S，S2MM 保持 reset/disable。
3. 当前 BD 的 stream `TDATA_WIDTH=24`，因此基线参数为 packed RGB888：
   - `HSIZE=1920`，对应 640 像素 × 3 字节；
   - `STRIDE=1920`；
   - `VSIZE=480`；
   - 起始地址 `0x10000000`。
4. 先验证静态彩条稳定显示，无水平错位、颜色通道互换、绿边、雪花、撕裂或周期性黑屏。
5. 再切换到只改低 8 位颜色或每秒切换两个固定帧，确认 DDR 更新能反映到 HDMI，但此阶段仍不接入摄像头。
6. 通过判定：肉眼彩条正确，10 分钟观察内无错误状态，frame count 持续递增，UART 输出 `HDMI_COLORBAR_PASS`。

## 阶段 4：VDMA S2MM 独立验证

1. 当前 BD 若有 PL 测试图源，将其接到 S2MM stream 输入；若无，应新增最小固定色/彩条 AXI-Stream 源，不要先接 OV5640。
2. CPU 先填充已知负样本，例如 `0xDEADBEEF`。
3. 启动 S2MM 后等待帧计数递增。
4. flush/invalidate 对应帧缓存后回读，比较已知图案或像素位置抽样。
5. PASS 条件：frame count 递增、无 VDMA 错误、回读图案与 PL 源一致。
6. 若无 PL 测试图源，本阶段只记录“S2MM 寄存器可配置且无错误”，不得把摄像头到 DDR 数据通路判定为通过。

## 阶段 5：整机进入摄像头链路

仅当 DDR、MM2S-to-HDMI、S2MM-to-DDR 均有独立 PASS 后：

1. 恢复 OV5640 时钟、复位、IIC 初始化。
2. 先打印 OV5640 ID 和关键寄存器回读。
3. 启动 S2MM，采样三缓冲 frame count。
4. CPU 抽样检查帧缓存非全零、非全一、逐帧变化。
5. HDMI 显示摄像头图像。
6. 最后才调试 AXI Lite 叠加、CNN、上位机协议等功能。

## 关键文件

- `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true\7_proj\vmda_HDMI_cam\vitis\cam_vdma_hdmi\src\cam_vdma_hdmi.c`
- `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true\7_proj\vmda_HDMI_cam\vitis\vdma_ctrl\src\main_vdma_read.c`
- 当前平台 `xparameters.h`
- 当前平台 `lscript.ld`
- 当前 BD 地址编辑器报告或 `xparameters.h` 导出证据

## 风险与回退

- **地址/版本不一致**：每次重建 XSA 后重新生成平台，禁止混合使用旧 bit 与新 XSA。
- **缓存误判**：DDR 测试和 S2MM 回读必须先 flush/invalidate；怀疑缓存时关闭 D-Cache 复测。
- **颜色格式错位**：区分 24 位 packed RGB 和 32 位 AXI 对齐格式；第一版先使用当前 BD 实测有效的 stride/HSIZE 组合，不做格式重构。
- **HDMI 时序已错**：若 DDR 彩条正确但屏幕仍异常，先抓 HDMI/VTC 波形或示波器确认同步/DE/像素时钟，不回退去调摄像头。
- **显示异常无法自动化判定**：以截图、录屏时间戳和完整 UART 日志作为共同证据。
