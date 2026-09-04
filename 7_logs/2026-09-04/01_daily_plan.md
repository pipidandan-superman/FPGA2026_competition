# 2026-09-04 Vitis 分层联调计划

## 当前判断

串口链路已有 `BOARD_TX_PASS` 证据，可以继续作为调试输出通道。HDMI 输出侧已有 RTL/ModelSim、ADV7511 配置仿真、综合实现与时序收敛证据，但 DDR、VDMA 和 HDMI 的整机数据通路还没有分层板级闭环。

昨天串口无输出由两个叠加问题组成：先确认 EES-331 DDR 型号/配置选择错误，导致应用或调试会话可能因 DDR 访问异常而失稳；随后最小 raw TX 应用仍卡在 UART 等待循环，根因是 `UART1_SR_TXFULL` 被误写为 `bit3(0x08)`。该位实际是 `TXEMPTY`，`TXFULL` 是 `bit4(0x10)`。改成 `bit4` 并用 XSCT 下载运行后，COM6 连续收到 `UART OK`，raw UART TX 板级 PASS；完整 RX echo 仍未验证。

当前 `app_component/src/main.c` 已改为阶段化测试固件：先执行 3 MiB DDR 六种 pattern、各三轮读写，再执行 1/5/30 秒保持回读；`DDR_PASS` 后才填充三帧 640×480 packed RGB888 彩条并只启动 VDMA MM2S。S2MM 保持复位/禁用，OV5640 不启动。当前 BD 的 MM2S/S2MM stream 数据宽度均为 24 bit，因此本工程 `HSIZE/STRIDE` 使用 `640*3=1920` 字节，而不是 32 bit 对齐流程的 `2560` 字节。

应用已再调整为 `UART → DDR → VDMA MM2S`。上电先输出 5 次 `UART_OK`，随后打印 `UART_TEST_PASS`，再等待 5 秒进入 DDR。这样既能先确认串口链路，又不要求每次都在源码里手动切换阶段。若当前只想隔离串口，可临时设置 `RUN_DDR_TEST=0`、`RUN_VDMA_MM2S=0`。

参考工程 `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true\7_proj\vmda_HDMI_cam\vitis` 提供两类重要资产：

- `cam_vdma_hdmi/src/cam_vdma_hdmi.c`：640×480、RGB888、`0x10000000` 起三缓冲、VDMA 双通道与彩条流程。
- `vdma_ctrl/src/main_vdma_read.c`：独立 MM2S 彩条直显、DDR 写入后回读校验、VSIZE 最后启动 VDMA 的流程。

用户提出的顺序理解如下：先验证 DDR 自身读写与保持能力，再确认 VDMA 寄存器和传输状态，再只启动 MM2S 把 DDR 中预填彩条直送 HDMI，最后等上述稳定后再进入摄像头与其余功能。这个顺序正确，应再细化为“DDR 稳态保持/VDMA 读通道/VDMA 写通道”三个独立判定，避免摄像头数据同时掩盖多个问题。

## 今日主要目标

1. 固化 DDR、VDMA MM2S、VDMA S2MM、HDMI 彩条直显的验证顺序和 pass/fail 判据。
2. 明确新建或复制的 Vitis 测试应用边界，禁止直接污染 2020 已上板参考工程。
3. 准备好下一步可直接执行的最小测试项：DDR pattern 读写与保持测试、MM2S-only HDMI 彩条、MM2S 帧计数与错误状态观测。

## 优先任务

- **P0**：核对本次测试使用的 bit/XSA 平台版本、时钟、VDMA 地址、DDR 范围一致。
- **P1**：建立 `ddr_vdma_stage_test` 独立 Vitis 应用模板，从参考工程复制必要寄存器定义，不修改原工程。
- **P2**：实现并运行 `DDR_INTEGRITY` 阶段：地址范围 `0x10000000` 起，避开栈/代码区域；全零、全一、`AAAA5555`、`5555AAAA`、地址指纹和递增数据回读。
- **P3**：实现并运行 `VDMA_MM2S_REG` 阶段：复位、配置回读、启动状态、错误位清零后持续观测。
- **P4**：实现并运行 `DDR_TO_HDMI` 阶段：只配置 MM2S，写入 640×480 八彩条，观察 HDMI 显示与 MM2S frame count。
- **P5**：显示稳定后，另做 `VDMA_S2MM` 阶段：优先使用 PL 测试图源替代 OV5640；若当前 BD 无测试图源，则只先完成寄存器状态预检，不宣称 S2MM 数据通路通过。

## 今日非目标

- 不调试 OV5640 寄存器配置和曝光参数。
- 不调试 CNN、AXI Lite 数字叠加、上位机通信或任务闭环。
- 不在同一个固件中同时打开摄像头、S2MM、CNN 和显示路径。
- 不覆盖或重命名 `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true` 内的已验证参考工程。

## 预期交付

- 今日四份工程日志与下一步启动指引。
- 后续每次硬件验证保留完整 UART、构建、下载和截图证据。
- 各阶段输出统一使用可检索标记：`DDR_PASS/DDR_FAIL`、`VDMA_MM2S_PASS/VDMA_MM2S_FAIL`、`HDMI_COLORBAR_PASS/HDMI_COLORBAR_FAIL`。
