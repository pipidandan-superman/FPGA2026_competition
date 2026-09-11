# 复现准备状态报告（C1.2 基线，2026-09-10）

- 执行人：AI 侧成员（aaacharon 机器）
- 目标基线：`udp-camera-c12-pass-20260908`（C1.2 最终固化，6.3 fps 版）
- 本报告性质：pull 后的工件审计 + 复现工具准备；**本轮无板级动作**。

## 1. 目标基线（固化三元组）

来源：`4_metrics/logs/2026-09-08_mainproj_eth_loopback_integrate_run01/`
`c12_final_artifacts_sha256.txt`（§26 "C1.2 最终固化（6.3 fps 版）"）。

| 工件 | SHA-256 | 大小 | 仓库状态 |
|---|---|---|---|
| BIT `display_test_wrapper.bit` | `7cb11f7df165476eb86e3d8c43cc251fb1c454ecd64b905f0931ad971ec192e7` | 4,045,696 B | **不在仓库（缺失）** |
| ELF `app_component.elf` | `3e295d51186135e4d9dfbba4b6c3637f3e7aece9135f2c124c29ce9ff1d963a9` | 861,424 B | ✅ 已有，`2_fpga/0_diaplay_test/vitis/hw_20260908_eth/app_component.elf` |
| XSA `display_test_wrapper.xsa` | `30644b3158d86d0d27c34ed60626179b17046cda7b3af51f35431b18652d22d0` | 578,739 B | **不在仓库（缺失）** |

注意：`7_logs/2026-09-08/04_next_start_guide.md` 中"固化后交接"引用的 ELF
`6eb0097c...` 是 09-08 当天 14:51 的早期构建；最终固化以 §26 的 `3e295d51...`
为准（本机已核验一致）。两对不可混用。

## 2. 本机核验结果（2026-09-10）

| 工件 | 本机 SHA-256 前缀 | 判定 |
|---|---|---|
| `2_fpga/0_diaplay_test/vitis/hw_20260908_eth/app_component.elf` | `3e295d51` | **PASS**，与 c12_final 清单一致 |
| `2_fpga/0_diaplay_test/proj/.../impl_1/display_test_wrapper.bit`（本地遗留） | `34adc740` | **过时**（09-06 zip 恢复版），≠ 目标基线，不可使用 |
| `2_fpga/0_diaplay_test/vitis/display_test_wrapper.xsa`（本地遗留） | `51351996` | **过时**，≠ 目标基线，不可使用 |
| `3_host/udp_video/dist/EES331_UDP_Viewer.exe` | `a4b75ed3` | **PASS**，即 BGR 修正版 V1.2 上位机 |
| 仓库内 BD（`proj/.../display_test.bd`） | — | `PCW_ENET0_PERIPHERAL_ENABLE=0`：**git 里是使能以太网之前的版本** |

## 3. 缺件影响与获取路径

XSA 是关键缺件：Vitis 2025.2 建 platform、加载 ELF、以及后续 PYNQ 移植的
FSBL 都从 XSA 出发；没有它，ELF 无法加载（2025.2 已移除 XSCT，无法绕过
platform 直接 dow ELF）。

BIT 是板级复现的另一半：PS 配置不在 bitstream 里，但 PL（摄像头→VDMA→HDMI）
在该 bit 中。

获取路径（二选一）：

1. **首选：向板卡队友索取两个文件**（其机器上均有，哈希见上表，到手先校验）：
   - `display_test_wrapper.bit`（4,045,696 B）
   - `display_test_wrapper.xsa`（578,739 B）
2. **备选：本机重建**（需用户明确授权，见同目录
   `enable_enet0_export_xsa.tcl` 头部说明）：git 中的 BD 是 ENET0 关闭版，
   需按 09-08 集成记录打开 ENET0（MIO16..27 RGMII、MDIO MIO52..53、
   1 Gbps、复位 MIO47）后重新导出 XSA / 生成 bit。重建产物哈希不会与
   队友的完全一致，须作为**新的独立验证 run** 记录，不得声称等同于
   `7cb11f7d` 配对。

## 4. 本机工具链（已核实）

| 工具 | 路径 | 备注 |
|---|---|---|
| Vivado 2025.2 | `E:/WorkApps/Xilinx/Vivado_2025_2/2025.2/Vivado/bin/vivado.bat` | HW Manager 编程 BIT |
| bootgen 2025.2 | 同目录 `bootgen.bat` | PYNQ BOOT.BIN 制作用 |
| Vitis 2025.2 | `E:/WorkApps/Xilinx/Vivado_2025_2/2025.2/Vitis/bin/vitis.bat` | GUI Build/Run ELF |
| XSCT | **无**（2025.2 已移除） | ELF 加载走 Vitis GUI Run |

## 5. 复现验收判据（摘自 §19/§20/§26，板会时逐项打钩）

串口（COM，115200-8-N1）顺序出现：

```
UART_TEST_PASS → ETH_LOOPBACK_INIT_BEGIN → PHY 1000M → ETH_LWIP_OK
→ ETH_UDP_ECHO_OK → UDP_TX_INIT_OK → LOOPBACK_TEST_READY
→ VDMA_INITIAL_BEGIN → HDMI_HEARTBEAT
→ UDP_TX frame=N packets=640（逐帧递增）→ HEARTBEAT rx=/tx=/err=
```

PC 侧（静态 IP `192.168.240.2/24`，放行 UDP 5000）：

- `ping 192.168.240.10` 通
- `EES331_UDP_Viewer.exe`（V1.2）显示相机实时画面，完整帧递增，
  帧率 ~6.3 fps 累计均值，丢帧/CRC 错=0（C1.2 门限），重复/坏头=0
- HDMI 显示器同显相机画面（如无画面：显示器切输入源后按一次板卡复位）

全部满足 → 记 `REPRO_C12_PASS`，原始串口日志与 GUI 截图归档至
`4_metrics/logs/2026-09-10_<板测run名>/`。

## 6. 同目录工件

| 文件 | 用途 |
|---|---|
| `prog_frozen_bit.tcl` | Vivado HW Manager 编程冻结 BIT（首选路径 A） |
| `enable_enet0_export_xsa.tcl` | 备选路径 B：ENET0 使能 + 导出 XSA（**未授权不得运行**） |
| `BOARD_ACCEPTANCE_CHECKLIST.md` | 板会操作清单（从上电到验收打钩） |
