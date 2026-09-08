# Zynq PS 配置对照报告：2_eth_onlytest_zynq7020 vs EES-331 硬件手册

日期：2026-09-08
对象：`E:\competition\2_fpga\2_eth_onlytest_zynq7020\project_1\project_1.srcs\sources_1\bd\eth_1G_test\eth_1G_test.bd`
（BD 仅含 processing_system7:5.5 一个 IP，纯 PS 以太网测试工程，无 PL IP、无 XDC、vitis/sim 目录为空）

## MinerU 证据

- 输入：`E:\competition\1_docs\pdf\EES-331 User Guide.pdf`
- 输入 SHA-256：`27C26F39F3E35132A89FAE2155FA23575E850B0A22E3D9DC64FD73186B3F5949`
- 结果标记：`MINERU_PARSE_PASS`（exit 0，41.4 s，Markdown + content JSON，86 图，无 fallback，中文质量 pass，首选源 content_list_json）
- 输出：本 run 目录 `EES-331 User Guide/auto/EES-331 User Guide.md`

## 手册硬件事实（来源：提取 Markdown + 官方配置截图）

| 项目 | 手册值 |
|---|---|
| 以太网 | PS 端 ENET0，PHY 88E1518，信号 MIO16~MIO27，MDIO MIO52/MIO53 |
| PHY 复位 | 官方 Vivado 配置截图含 Ethernet PHY reset，MIO47，Share reset pin |
| DDR3 | 1GB，型号 MT41K256M16 RE-15E，挂 PS DDR 控制器 |
| UART1 | MIO48=TX、MIO49=RX，经 J3 USB3.0 引出（兼调试口） |
| UART0 | MIO50/51（本工程未启用，非问题） |
| MIO Bank0/500 | 3.3V |
| MIO Bank1/501 | 1.8V |
| 主控 | XC7Z020 CLG484-1 |

## 逐项对照结果

| # | 配置项 | 工程 BD 值 | 手册要求 | 判定 |
|---|---|---|---|---|
| 1 | ENET0 使能 | `PCW_ENET0_PERIPHERAL_ENABLE=1`，IO=`MIO 16 .. 27` | ENET0 MIO16~27 | ✅ |
| 2 | 速率 | 1000 Mbps（ACT 125 MHz） | 88E1518 千兆 PHY | ✅ |
| 3 | MDIO | ENET0_GRP_MDIO=`MIO 52 .. 53` | MIO52/MIO53 | ✅ |
| 4 | PHY 复位 | `PCW_ENET0_RESET_ENABLE=1`，RESET_IO=`MIO 47`，Share reset pin | 官方配置截图同 | ✅ |
| 5 | DDR 颗粒 | `PCW_UIPARAM_DDR_PARTNO=MT41K256M16 RE-15E`，HIGHADDR=0x3FFFFFFF（1GB），ACT 533.33 MHz | 同型号 1GB | ✅ |
| 6 | UART1 | `MIO 48 .. 49`，MIO 树 48=tx、49=rx | 48=TX、49=RX | ✅ |
| 7 | Bank1 电压 | `PCW_PRESET_BANK1_VOLTAGE=LVCMOS 1.8V` | Bank1/501=1.8V | ✅ |
| 8 | MIO 树一致性 | MIO_TREE_SIGNALS：16=tx_clk，17-20=txd[0:3]，21=tx_ctl，22=rx_clk，23-26=rxd[0:3]，27=rx_ctl | RGMII 布局 | ✅ |

## 结论

`ETH_ZYNQ_PS_CONFIG_CHECK_PASS`：该工程 Zynq PS（processing_system7 5.5）的以太网、MDIO、PHY 复位、DDR 颗粒、UART1、Bank1 电压配置与 EES-331 硬件手册及官方图形化配置一致，8/8 项通过。

## 边界与提醒（非 FAIL）

1. 本结论仅覆盖 PS 配置静态检查；未做综合/实现/板级链路验证。
2. RGMII 延迟（TX/RX skew）不属 PS7 MIO 配置项，88E1518 的 RGMII delay 模式需在软件侧通过 MDIO 配置 PHY 寄存器（或核对原理图 PHY 硬件 bootstrap），上板调试时注意。
3. Bank0（3.3V）无显式 PCW 值，采用默认；与手册一致。
4. 工程无 PL 侧约束与 Vitis 内容，符合"PS-only 以太网测试"定位，但意味着无板上自证证据。
