# PL 地址映射合同 — 3_yolo_zynq（G3 前置）

来源（只读借用，未改动主工程）：
- `2_fpga/0_diaplay_test/release/action_v1_uart_run02/display_test_axi_action_uart.hwh`
- `2_fpga/0_diaplay_test/pynq/current.hwh`（旧 overlay，无 action IP，对照用）

## 主工程已占用区间（必须避开）

| 实例 | IP | 区间 |
|---|---|---|
| processing_system7_0 | PS7 DDR | `0x1000_0000 – 0x1FFF_FFFF`（512MB，帧缓冲） |
| axi_vdma_0 | axi_vdma | `0x4300_0000 – 0x4300_FFFF`（64KB） |
| axi_action_0 | video_axi_action_uart_top | `0x43C0_0000 – 0x43C0_0FFF`（4KB） |

## 本工程（yolo 加速器）分配

| 用途 | 区间 | 说明 |
|---|---|---|
| yolo 寄存器组（AXI-Lite） | `0x43C1_0000 – 0x43C1_FFFF`（64KB） | 紧邻主工程 action IP 之后的 GP0 空闲段；描述符/门铃/中断状态 |
| yolo 权重/激活 DMA（AXI-HP） | DDR 内 carve-out，运行时由驱动分配 | 经 S_AXI_HP0 回 DDR，与帧缓冲同物理内存空间但由软件分区管理 |

依据：Zynq-7 M_AXI_GP0 映射窗口 `0x4000_0000–0x7FFF_FFFF`；上述选择
避开主工程全部已占用段；与主工程合并进同一 bitstream 时无冲突。
**RTL 顶层 C_BASEADDR 参数化，不硬编码。**

## 借用的其它主工程参数（后续 RTL/驱动参考）

- PS7 DDR 基址 0x10000000（帧缓冲惯例沿用）
- VDMA 64KB 寄存器段布局（如需视频输出链路复用）
- action IP 的 AXI-Lite 从设备模式（4KB 段经验值 → 本工程放宽到 64KB）

## 变更纪律

本文件是 3_yolo_zynq 硬件地址合同的单一事实源；改地址 = 改本文件 +
RTL 参数 + 驱动三处同步，禁止只改一处。
