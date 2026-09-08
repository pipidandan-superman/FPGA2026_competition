# 主工程（0_diaplay_test）以太网回环集成报告 V3.1

日期：2026-09-08
范围：仅 `vitis/app_component`；`proj/` 工程与 RTL 由用户自行修改（PS 使能 ENET0、新比特流、新 XSA）。

## 1. Zynq 以太网配置对比（display_test.bd vs eth_1G_test.bd）

21 项 PCW 键对比：17 SAME / 4 DIFF。
DIFF 4 项均为 eth 测试工程 BD 中缺省未出现的键（QSPI/SD0/USB0/Bank0 电压），非真实差异。
以太网关键配置完全一致：ENET0 使能、MIO16..27、1000 Mbps（ACT 125 MHz）、MDIO MIO52..53、复位 MIO47 Share reset、EMIO 关、UART1 MIO48..49、DDR MT41K256M16 RE-15E 1GB、Bank1 1.8V。
结论：`MAIN_ETH_CONFIG_EQUIVALENT_PASS` —— 主工程 PS 以太网配置与已验证回环工程等效。

## 2. 集成前的基线取证（冻结边界声明）

- main.c（V3.0 相机固件）SHA-256：`705B0317DC688022DF5956EC985A041D87E47D4348BFB6107C1D614D6CE5F9C0`
- display_test_wrapper.xsa（用户新导出）SHA-256：`30644B3158D86D0D27C34ED60626179B17046CDA7B3AF51F35431B18652D22D0`
- display_test.bd SHA-256：`2659E061665E2CC497858464774447F8DBAF3E535CBD520C0877453F847C7143`
- 注意：用户修改 PS 后，2026-09-07 冻结基线 camera-hdmi-visual-pass-20260907 的 BIT/ELF 配对不再代表当前工程状态；新验证周期以本次 XSA 为起点。

## 3. 代码变更

新增（与已验证的 eth_test_app 相同文件）：
- `udp_echo.c/h`：UDP 5000 回环 + 收发计数
- `platform.c/h`、`platform_zynq.c`：AMD 模板原样（xiltimer 50 ms tick、链路检测、RX 看门狗）
- `platform_config.h`：PLATFORM_EMAC_BASEADDR=XPAR_XEMACPS_0_BASEADDR

修改：
- `UserConfig.cmake`：USER_COMPILE_SOURCES 增加 platform.c、platform_zynq.c（udp_echo.c 已由 GUI 登记）
- `main.c` V3.0 → V3.1（593 → 729 行）：
  1. 文件头（含修订历史）+ 7 个新 include
  2. lwIP 全局（echo_netif/dhcp_timoutcntr/定时器标志）与 print_ip_settings
  3. `run_eth_loopback_init()`：init_timer（SDT 路径，**不开 D-Cache**，保持 V3.0 内存行为）→ lwip_init → xemac_add → netif up → UDP echo 5000 → `ETH_LWIP_OK` / `ETH_UDP_ECHO_OK` / `LOOPBACK_TEST_READY`
  4. `eth_service()` + `eth_service_ms(ms)`：100 ms 切片轮询 xemacif_input + 定时器标志 + 每 10 s HEARTBEAT
  5. main() 在 UART 自检通过后调 ETH 初始化（失败不阻断 HDMI 测试）
  6. `monitor_stability_60s` 的 `sleep(1)` → `eth_service_ms(1000)`；运行循环 `sleep(5)` → `eth_service_ms(5000)` —— 固件原有打印/判定全部保留

## 4. 未做 / 边界

- 未编译、未上板（由用户在 Vitis GUI Build + Run）。
- IP/MAC 沿用回环工程：192.168.240.10/24，网关 192.168.240.2，MAC 00:0A:35:00:01:02。
- ETH 初始化失败仅告警继续 HDMI 测试；ETH 就绪后 VDMA 全部原有判定不变。

## 5. 验收判据（板级）

- 串口顺序出现：UART_TEST_PASS → ETH_LOOPBACK_INIT_BEGIN → PHY 1000 Mbps → ETH_LWIP_OK → ETH_UDP_ECHO_OK → LOOPBACK_TEST_READY → VDMA_INITIAL_BEGIN（原有流程）
- PC `ping 192.168.240.10` 通
- PC UDP 5000 发包收到回显（NetAssist RX=TX），串口每 10 s `HEARTBEAT rx=/tx=/err=0`
- HDMI 心跳 `HDMI_HEARTBEAT / HDMI_RUNTIME_HEARTBEAT` 照常输出
- 全部满足 => `MAIN_ETH_LOOPBACK_PASS`（同时保留原 HDMI 判定链）

## 6. 板级验收回填（2026-09-08 12:23）

- 用户板测：NetAssist 192.168.240.2:5000 <-> 板卡 192.168.240.10:5000，发送 `你好` 3 包全部原样返回，计数 `3/3`，`RX:12 = TX:12`；同时摄像头画面经 VDMA→HDMI 正常显示。
- 截图：`netassist_mainproj_udp_loopback_pass_20260908.png`（SHA-256 `4AA8933B02B449F314D2E336908B41252FC9DE3DB91BF4E6B2742635AFF7CE0E`）。
- 板级产物（新验证基线）：
  - BIT `display_test_wrapper.bit` 4,045,696 B（12:09 生成）
  - ELF `app_component.elf` 851,088 B（12:23 构建）
  - XSA `display_test_wrapper.xsa` 578,739 B（12:09 导出）
  - 全部 SHA-256 见 `board_artifacts_sha256.txt`
- 结果：`MAIN_ETH_LOOPBACK_PASS` + 摄像头 HDMI 显示保持正常（用户目视确认；VDMA 判定链未发现 FAIL 打印）。
- 遗留：完整串口日志（含 ETH 心跳与 HDMI 心跳）待归档。
