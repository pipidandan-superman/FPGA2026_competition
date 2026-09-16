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

## yolo CSR 寄存器图（0x43C1_0000 段内；单一事实源 = 本表，RTL = rtl/yolo_csr.v，驱动/TB 同步）

| 偏移 | 访问 | 名称 | 内容 |
|---|---|---|---|
| 0x00 | R | ID | 0x594F4C31 |
| 0x04 | R | VER | 0x0001_0000（A1） |
| 0x08 | W | CTRL | [0] START 门铃；[1] CLR_STATS（清 ldone 计数/all_done 粘滞/IRQ raw） |
| 0x0C | R | STATUS | [0] busy [1] dsc_ready [2] all_done 粘滞 [3] dsc_pend（门铃未受理）[31:16] ldone 计数 |
| 0x10 | RW | DESC0 | [10:0] oc，[31:16] n |
| 0x14 | RW | DESC1 | [11:0] k，[16] last，[17] first，[18] act |
| 0x18 | RW | DESC2 | [15:0] ih，[31:16] iw |
| 0x1C | RW | DESC3 | [15:0] ow，[31:16] ic |
| 0x20 | RW | DESC4 | [7:0] kh [15:8] kw [23:16] sh [31:24] sw |
| 0x24 | RW | DESC5 | [7:0] ph，[15:8] pw |
| 0x28 | RW | WBASE | W 行 DDR 基址 |
| 0x2C | RW | XBASE | X 平面 DDR 基址 |
| 0x30 | RW | YBASE | Y 平面 DDR 基址（行起始 = ybase + oc_g·n_total + n_tile·N_EDGE） |
| 0x34 | RW | BBASE | bias_eff 字（LE 4B）基址 |
| 0x38 | RW | MBASE | M 字（LE 4B）基址 |
| 0x3C | RW | SBASE | shift 字节基址 |
| 0x40 | RW | IRQ_EN | [0] layer_done [1] all_done |
| 0x44 | RW | IRQ_STAT | W1C [0]/[1] |
| 0x400+4i | W | LUT[i] | wdata[7:0]，i=0..255（只写窗口，读回 0） |

未映射偏移：OKAY、写忽略、读 0。软件合同：STATUS.dsc_pend=1 期间不得重写
DESC*/BASE*（阵列仅在受理沿采样影子寄存器）。V1.0（2026-09-16，M12 A1）。

## 借用的其它主工程参数（后续 RTL/驱动参考）

- PS7 DDR 基址 0x10000000（帧缓冲惯例沿用）
- VDMA 64KB 寄存器段布局（如需视频输出链路复用）
- action IP 的 AXI-Lite 从设备模式（4KB 段经验值 → 本工程放宽到 64KB）

## 变更纪律

本文件是 3_yolo_zynq 硬件地址合同的单一事实源；改地址 = 改本文件 +
RTL 参数 + 驱动三处同步，禁止只改一处。
