# ViTA Zynq PS 配置清单报告

- 报告日期：2026-09-03
- 配置来源：主工程冻结硬件平台 `D:/VitA/6_proj/vitis/vita_wrapper.xsa`（Vivado 2020.2 导出）
- 提取方式：解包 XSA 内的 `vita.hwh`，逐项读取 `processing_system7_0` 的 937 个 PS7 参数与 BD 地址映射
- 与历史整理文档的关系：本报告是 2026-08-18 板级验证基线之后的当前主工程实际配置；历史文档见第 10 节

## 1. 结论摘要

| 项目 | 当前主工程配置 |
|---|---|
| 器件 | xc7z020clg484-1（Zynq-7020，CLG484，速度等级 -1） |
| PS IP | xilinx.com:ip:processing_system7:5.5，BD 单元 `processing_system7_0` |
| 晶振 | 33.333333 MHz |
| APU/CPU | 666.666687 MHz |
| DDR | DDR3，MT41K256M16 RE-15E，32 bit，533.333333 MHz，1 GiB |
| FCLK_CLK0 | 使能，100 MHz（唯一输出到 PL 的 FCLK） |
| 使能外设 | 仅 UART1（MIO 48..49，115200） |
| PS-PL | M_AXI_GP0（32 bit @100 MHz）+ S_AXI_HP0（64 bit @100 MHz） |
| 中断 | IRQ_F2P 禁用，采用轮询 |
| BD 地址映射 | AXI DMA `0x40400000`；控制 IP `0x43C00000` |

## 2. 证据与哈希

| 项 | 值 |
|---|---|
| 主工程 XSA | `D:/VitA/6_proj/vitis/vita_wrapper.xsa` |
| XSA SHA-256 | `A05C954AA65F4980587C8214491D9B66C0BCC41E228B1C64FB06507DF3E6ABA1` |
| 与 HANDOFF.md 记录 | 一致（冻结构建产物） |
| 关联 BIT SHA-256 | `1FF38EAC9D3A1DDED4ABDFFE47EB6D00231FA568B77932AF6FCEE85416815C70` |
| 关联 ELF SHA-256 | `A53D3C80C2722FEF1D3540553F088E17B9823D37B73978594BDDDA1EECCC20B8` |
| XSA 内文件 | `vita.hwh` / `vita.bda` / `ps7_init.tcl` / `ps7_init.c/h` / `vita_wrapper.bit` |
| PS7 参数总数 | 937（hwh 全量提取） |

## 3. 器件与工具链

| 项 | 值 |
|---|---|
| FPGA | Zynq-7000 xc7z020clg484-1 |
| PL 资源规模 | LUT 53200 / FF 106400 / BRAM 140 / DSP 220 |
| Vivado 版本 | 2020.2 |
| Board part | 未设置（标准器件工程） |
| 包装 | clg484 |

## 4. PS 时钟配置

### 4.1 PLL 链

| 时钟域 | 参数 | 结果 |
|---|---|---|
| 输入晶振 | `PCW_CRYSTAL_PERIPHERAL_FREQMHZ` | 33.333333 MHz |
| IO PLL | FBDIV = 48 | 1600 MHz |
| ARM PLL | FBDIV = 40 | APU 666.666687 MHz |
| DDR PLL | FBDIV = 32，DDR 分频 2 | DDR 533.333333 MHz |

### 4.2 FCLK 输出

| 项 | 配置 | 结果 |
|---|---|---|
| FCLK_CLK0 | 使能；时钟源 IO PLL；DIVISOR0 = 4，DIVISOR1 = 4 | 100.000000 MHz |
| FCLK_CLK1..3 | 均禁用（`PCW_EN_CLK1..3_PORT = 0`） | 无输出 |
| FCLK_RESET0_N | 使能（`PCW_EN_RST0_PORT = 1`） | 驱动 `proc_sys_reset` 的 `ext_reset_in` |
| FCLK_CLK0 缓冲 | `PCW_FCLK_CLK0_BUF = FALSE` | BD 内由 interconnect/模块自身时钟输入直接使用 |

BD 中 `FCLK_CLK0` 共 16 处扇出，覆盖：GP0 ACLK、interconnect 全部 ACLK、AXI DMA 的 Lite/MM2S/S2MM 时钟、`vita_axil_ctrl_0` S_AXI_ACLK、`p18_msa_accel_0` ACLK、`rst_fclk0` slowest_sync_clk。即全部 PL AXI 逻辑同为 100 MHz 单时钟域。

### 4.3 PS 内部外设实际时钟（ACT）

| 外设 | ACT 频率 | 状态 |
|---|---:|---|
| APU | 666.666687 MHz | 使能 |
| UART | 100.000000 MHz | UART1 使能 |
| PCAP | 200.000000 MHz | 使能 |
| DCI | 10.158730 MHz | 自动 |
| QSPI/ENET/SDIO/SPI/CAN | 10 MHz 占位 | 已禁用 |

## 5. DDR 配置

| 项 | 值 |
|---|---|
| 类型 | DDR 3 |
| 颗粒 | MT41K256M16 RE-15E（16 bit 颗粒） |
| PS 数据宽度 | 32 Bit（两片 16 bit 拼位宽） |
| 单颗容量 | 4096 Mbit |
| 速度档 | DDR3_1066F |
| 频率 | 533.333333 MHz |
| Burst Length | 8 |
| CL / CWL | 7 / 6 |
| tRCD / tRP | 7 / 7 |
| tRC / tRASmin / tFAW | 49.5 / 36.0 / 45.0 ns |
| Bank/Row/Col 地址位 | 3 / 15 / 10 |
| 容量映射 | 0x00000000 - 0x3FFFFFFF（1 GiB） |
| ECC | 禁用 |
| 温度档 | Normal（0-85 摄氏度） |
| Write Leveling 训练 | 使能（1） |
| Read Gate 训练 | 使能（1） |
| Data Eye 训练 | 使能（1） |
| Vref | 使用外部 Vref（`USE_INTERNAL_VREF = 0`） |

## 6. MIO 与外设

### 6.1 电压配置

| 项 | 值 |
|---|---|
| MIO Bank 0 | LVCMOS 3.3 V |
| MIO Bank 1 | LVCMOS 1.8 V |

### 6.2 唯一使能的外设：UART1

| 项 | 值 |
|---|---|
| 外设 | UART 1 |
| 引脚 | MIO 48（TX，out）/ MIO 49（RX，in） |
| 波特率 | 115200 |
| IO 电平 | LVCMOS 1.8 V |
| 上拉 | 使能 |
| Slew | slow |
| UART 时钟 | 100 MHz |

### 6.3 显式禁用的外设

UART0、QSPI、Ethernet 0/1、USB 0/1、SD 0/1、SPI 0/1、CAN 0/1、I2C 0/1、GPIO（MIO/EMIO）、WDT、TTC 0/1、PJTAG、NAND、SMC 均为禁用状态（对应 `PERIPHERAL_ENABLE = 0`，引脚 `<Select>` 未分配）。

## 7. PS-PL 接口配置

| 接口 | 状态 | 位宽 | 时钟 | ID 宽度 | 用途 |
|---|---|---|---|---|---|
| M_AXI_GP0 | 使能 | 32 bit | 100 MHz | 12 | PS 到 AXI-Lite 控制链（DMA 寄存器 + vita_axil_ctrl） |
| S_AXI_HP0 | 使能 | 64 bit | 100 MHz | 6 | PL DMA 到 DDR 高性能通路 |
| M_AXI_GP1 | 禁用 | - | - | - | 未使用 |
| S_AXI_GP0/GP1 | 禁用 | - | - | - | 未使用 |
| S_AXI_HP1/HP2/HP3 | 禁用 | - | - | - | 未使用（HP0 单通路承载 DMA） |
| S_AXI_ACP | 禁用 | - | - | 3 | 未使用 |
| PS 内建 DMA 0..3 | 禁用 | - | - | - | PL DMA 由 AXI IP 承担 |
| IRQ_F2P | 禁用 | - | - | - | 应用层采用轮询 |
| EMIO GPIO | 禁用 | - | - | - | 未使用 |

## 8. BD 地址映射（当前主工程）

| 从设备 | 基址 | 范围 | 说明 |
|---|---|---|---|
| `axi_dma_0` | 0x40400000 | 0x40400000 - 0x4040FFFF（64 KiB） | AXI DMA 控制寄存器 |
| `vita_axil_ctrl_0` | 0x43C00000 | 0x43C00000 - 0x43C00FFF（4 KiB） | ViTA 控制/状态寄存器 |
| DDR | 0x00000000 | 0x00000000 - 0x3FFFFFFF（1 GiB） | PS DDR，DMA 描述符与数据缓冲 |

## 9. 与 2026-08-18 板级验证基线的差异

历史板级验证基线（EES-331 GEMM 参考设计）与当前 ViTA 主工程的差异：

| 项 | 板级验证基线（旧 GEMM 参考） | 当前 ViTA 主工程 |
|---|---|---|
| FCLK_CLK0 | 50 MHz | 100 MHz |
| HP 通路 | HP0 + HP1（均 64 bit） | 仅 HP0（64 bit） |
| QSPI | 使能（MIO 1..6） | 禁用 |
| Ethernet 0 | 使能（MIO 16..27，MDIO 52..53） | 禁用 |
| USB 0 | 使能（MIO 28..39） | 禁用 |
| SD 0 | 使能（MIO 40..45） | 禁用 |
| UART1 | 使能（MIO 48..49，115200） | 使能（不变） |
| DDR3 参数 | 同 | 同（不变） |
| MIO Bank 电压 | 3.3 V / 1.8 V | 同（不变） |
| IRQ_F2P | 禁用（轮询） | 禁用（轮询） |
| DMA 地址 | 0x40400000 | 0x40400000（不变） |
| 控制寄存器 | 0x43C00000（GEMM） | 0x43C00000（vita_axil_ctrl） |

保持不变的板级关键子集：DDR3 颗粒/位宽/频率/训练参数、MIO Bank 电压、UART1 配置。

## 10. 历史整理文档位置

| 文档 | 路径 | 内容 |
|---|---|---|
| 板级验证基线 | `D:/VitA/11_process/reference/zynq_ps/20260818_ees331_board_verified/ZYNQ_PS_CONFIG_BASELINE.md` | EES-331 板级验证的 GEMM 参考全量 PS 配置（时钟/DDR/MIO/外设/地址映射/一致性检查） |
| 最小应用验证 | `D:/VitA/11_process/reference/zynq_ps/20260818_ees331_board_verified/VITA_MINIMAL_APPLY_VERIFICATION.md` | 将板级关键子集（DDR/电压/UART1）应用到 `vita.bd` 的 26 项参数核对记录 |
| 根因报告 | `D:/VitA/1_doc/2026-08-20_vita_ps_dma_root_cause_report.md` | PS-DMA 挂死根因与修复（FCLK0 使能结论反转过程） |
| 实施计划 | `D:/VitA/1_doc/2026-08-20_vita_ps_dma_implementation_plan.md` | PS-DMA 分层验证计划 |
| 交接 | `D:/VitA/HANDOFF.md` | 当前冻结构建产物哈希与验证边界 |

## 11. 校验说明

- 本报告数值全部来自 `vita_wrapper.xsa` 内嵌 `vita.hwh` 的 PS7 参数实测提取，非手工转抄。
- `PCW_FPGA0_PERIPHERAL_FREQMHZ = 100` 与 `PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ = 100.000000` 交叉印证 FCLK0 实际 100 MHz。
- IO PLL 1600 MHz、除数 4x4 与 2026-08-21 板级运行时寄存器回读（0xF8000170 = 0x00400400）一致。
- M_AXI_GP0 与 S_AXI_HP0 频率参数（`PCW_M_AXI_GP0_FREQMHZ = 100`、`PCW_S_AXI_HP0_FREQMHZ = 100`）与 FCLK0 时钟域一致。
