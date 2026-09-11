# EES-331 以太网起步清单（lwIP → UDP 发帧）

> 目标：板子通过网线向 AI PC 发送数据帧，跑通 `1_docs/interface.md` 协议 v1。
> 原则：以太网是 **PS 外设**，与 PL 无关——**不需要重新做 PL 工程/比特流**，PS 配置由 FSBL 在启动时加载。
> 执行人：AI PC 分工成员（自有 EES-331 板） ｜ 2026-09-07

## 0. 硬件与物料

| 项 | 状态 | 备注 |
|---|---|---|
| EES-331 板卡 + 电源 | ☐ | |
| JTAG 下载器（调试/下载用） | ☐ | |
| USB 转串口线（UART1，COM 口） | ☐ | 看 lwIP 日志必需 |
| **网线** | ☐ | 普通直通线即可 |
| **PC 有线网口** | ☐ | 笔记本若无 RJ45，买 USB 千兆网卡（~30元，免驱优先） |

## 1. Vivado：使能 ENET0（一次性）

当前 `display_test` 工程 PS 配置里 **ENET0 是关闭的**（`PCW_ENET0_PERIPHERAL_ENABLE=0`，已在 BD 中核实）。开启步骤：

1. 打开 `proj/display_test_zynq7020_school.xpr`（2025.2）
2. Open Block Design → 双击 Zynq PS7 核 → **MIO Configuration** 页
3. 勾选 **Ethernet 0**：IO = **MIO 16~27**（RGMII），**MDIO = MIO 52/53**（板卡 88E1518 PHY 硬件接线已定，照抄即可，依据：EES-331 手册 13 节/`7_logs/2026-09-07/ees331_eth_page16.png`）
4. Speed 选 1Gbps；Confirm 后 Validate BD（F4）
5. 重新生成输出产物 → Export XSA（含 bit 可选）

> 注意：Zynq-7000 的 PS 配置**不在 bitstream 里**，由 FSBL 启动时加载。所以 PL 没改就不用重跑实现/生成 bit，**只需重导 XSA + 重建 FSBL/平台**。

## 2. Vitis：lwIP Echo Server（链路验证）

1. 用新 XSA 重建 platform（SDT 流程，参考 HANDOFF 2026-09-04 的 sdt 经验）
2. 新建应用工程，模板选 **lwIP Echo Server**（platform 需勾选 lwip202 库）
3. 修改 `main.c`/`echo.h`：静态 IP 设为 **192.168.10.2**，网关/掩码 255.255.255.0（与 AI PC 约定网段，见 `1_docs/interface.md`）
4. Build → Run（JTAG 下载）

## 3. PC 侧配置

1. 控制面板 → 网络连接 → 有线网卡 → IPv4 → 静态 `192.168.10.1 / 255.255.255.0`
2. 串口终端打开 COM 口（115200-8-N1），看 lwIP 启动打印的 IP 与链路状态

## 4. 验证阶梯（每步判据）

| 步骤 | 操作 | PASS 判据 | Fail 排查 |
|---|---|---|---|
| L1 物理层 | 插网线 | PC 网络图标变化、板子 PHY Link LED 亮 | 换线/换口；确认 ENET0 已使能且 FSBL 为新版 |
| L2 IP 层 | PC `ping 192.168.10.2` | 通（lwIP 自动应答 ICMP） | 查子网/掩码；串口看 lwIP 是否打印 `Link up` |
| L3 TCP 回显 | PC `telnet 192.168.10.2 7`（或 echo 工具） | 发什么回什么 | lwIP echo 应用逻辑 |
| L4 UDP 帧回显 | Python UDP 测试脚本 | 收到回包 | 按防火墙放行；查端口号 |
| L5 协议帧 | 按 interface.md 发固定测试 JPEG | AI PC `inference_server.py` 打印收到帧 | 分片重组逻辑 |

## 5. 通过后：切换到发帧正式版

1. Echo/回显代码替换为协议 v1 发送端：从 DDR 读图像缓冲 → 打包（裸帧模式或 JPEG）→ 分片发送
2. 起步建议先发**固定测试 JPEG**（PC 端 `inference_server.py` 直接可用），OV5640 链路通了再切实时帧
3. 每步记录到 `7_logs/`（日期四件套），证据（串口日志/ping 截图/抓包）存 `4_metrics/logs/`

## 6. 风险提示

- **笔记本无 RJ45 是最大变量**，USB 网卡提前买；杂牌芯片免驱性差异大，优先 AX88179/RTL8153 方案
- 两人两块板各自调试互不影响；**联调时同一时刻只有一块板连 AI PC**
- Vitis 2025.2 的 lwIP 模板若找不到，先确认 platform 建立时勾选了 lwip 库；仍不行参考 HANDOFF 中 sdt 流程经验
