# eth_test_app V1.0 代码交付报告（UART 串口检测 + UDP 回环）

日期：2026-09-08
目标：`2_fpga/2_eth_onlytest_zynq7020/vitis/eth_test_app`（平台 `eth_test`，XSA `eth_1G_test_wrapper.xsa`，PS-only ENET0/88E1518）

## 已确认的工作区状态

- 平台 `eth_test`：ps7_cortexa9_0/standalone，BSP 含 standalone、scugic、scutimer、uartps、emacps、xiltimer；**尚未添加 lwip220**。
- PC 侧网卡：Realtek 2.5GbE，链路 1.0 Gbps，静态 `192.168.240.2/24`（截图证据，超出计划文档 192.168.1.x 网段，板卡 IP 相应改为 192.168.240.10）。
- Vitis 2025.2 GUI 已打开该工作区（进程 F:\vivado2025\2025.2\Vitis）。

## 交付文件（eth_test_app/src）

| 文件 | 来源 | SHA-256 前缀 |
|---|---|---|
| main.c | 新编写（项目头，四阶段启动） | 1fd8b07b… |
| udp_echo.c/h | 新编写（RAW API UDP 回环） | f4f6dd08… / 22fc453d… |
| platform_config.h | 新编写（PLATFORM_EMAC_BASEADDR=XPAR_XEMACPS_0_BASEADDR） | 3bbd4b63… |
| platform.c / platform.h / platform_zynq.c | 逐字节复制自 Vitis 2025.2 lwip_echo_server 模板（保留 AMD BSD 头） | — |

## 设计要点

- 四阶段启动标记：`STAGE0_UART_OK` → `STAGE1_LWIP_OK` → (STAGE2 = ICMP ping 由 lwIP 自动应答) → `STAGE3_UDP_ECHO_OK` → `LOOPBACK_TEST_READY`；每 10 秒打印 `HEARTBEAT rx=/tx=/err=` 统计。
- 静态 IP 192.168.240.10/24，网关指向 PC 192.168.240.2；MAC 00:0A:35:00:01:02；lwip220 默认 RAW_API（NO_SYS=1，lwip_init + xemac_add + 主循环 xemacif_input，与官方模板一致）。
- UDP 回环：绑定 UDP 5000（对齐实施计划 Wireshark 过滤端口），udp_recv 回调内 udp_sendto 原样回包，计数收发包/字节/错误；前 3 包与每 50 包打印来源 IP:port。
- 复用模板 platform.c/platform_zynq.c：scutimer 50 ms 中断驱动 TcpFastTmrFlag/TcpSlowTmrFlag，每秒 eth_link_detect + RX 路径看门狗（SI #692601 软件规避）。

## 用户 GUI 步骤（唯一前置动作）

1. Vitis GUI → Platform `eth_test` → ps7_cortexa9_0 → standalone 行 "＋" → 添加库 `lwip220`（参数保持默认 RAW_API）。
2. Build Platform → Build eth_test_app → Run（COM 终端 115200-8-N1，UART1 经 J3）。

## 验收判据（板级）

- `UART_BANNER_PASS`：出现 STAGE0/1/3 与 LOOPBACK_TEST_READY。
- `ICMP_LOOPBACK_PASS`：PC `ping 192.168.240.10` 通（RTT < 1 ms，1 Gbps 链路）。
- `UDP_LOOPBACK_PASS`：PC 向 192.168.240.10:5000 发包收到相同回包；HEARTBEAT rx=tx 计数同步增长、err=0。

## 边界

代码仅完成静态编写与模板一致性核对，未编译、未上板；不声明任何功能性 PASS。
