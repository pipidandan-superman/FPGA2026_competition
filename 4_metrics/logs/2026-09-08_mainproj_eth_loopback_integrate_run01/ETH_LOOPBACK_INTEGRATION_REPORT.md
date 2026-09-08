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

## 7. 阶段 B1 发送端追加（2026-09-08 下午，V3.1 → V3.1.1）

- 新增 `udp_video_tx.c/h`：板→PC UDP 视频发送端（阶段 B1）。
  - 帧源：合成图案（5 彩条 + 移动列，type=0x02）；C1 阶段以 DDR 快照替换 `build_pattern_frame`，API 不变（`UDP_TX_USE_CAMERA` 门控预留）。
  - 打包：32 B 头（SOF/EOF 标志、frame_id、packet_id 0..639、packet_count、stride、timestamp、整帧 CRC32）+ 1,440 B 载荷，共 640 包/帧，与设计文档 §4 逐字段一致。
  - 目标：`192.168.240.2:5000`；本机源端口 5001（避开回环 echo 的 5000）。
  - 节奏：每 2 个慢定时器 tick（1 s）一帧起步；爆发内每 32 包 yield 一次（`udp_video_tx_yield` → main.c `eth_service_base`），保证 ARP/RX 存活且无递归。
- `main.c` 结构调整：`eth_service` 拆为 `eth_service_base`（定时器+RX 排水+echo 心跳）+ 发送轮询；ETH 初始化处调用 `udp_video_tx_init`。
- `UserConfig.cmake`：GUI 已自动登记全部源文件。
- 代码哈希：见 `b1_sender_sha256.txt`（udp_video_tx.c `A9446508...`）。
- 边界：未编译未上板。板会验收判据：GUI（EES331_UDP_Viewer.exe）出现移动彩条，`完整帧` 以 ~1 fps 递增、`丢帧/CRC 错` = 0；同时 HDMI 心跳照常。B1 通过后方进入 C1（真实相机帧）。

## 8. 首轮板测问题定位与修复（2026-09-08 13:2x，V3.1.1 → V3.1.2）

### 首轮板测事实（用户串口日志）

- ETH 初始化全部正常（PHY 1000M / ETH_LWIP_OK / UDP_TX_INIT_OK），但**整个 13+ 秒捕获中没有出现任何 `UDP_TX frame=` 与 `HEARTBEAT rx=` 行**——发送条件永远不满足，一帧未发，这就是"上位机收不到"的直接原因。
- 定时器标志从未置位 ⇒ platform ScuTimer（xiltimer）中断路径在本 SDT 构建中未生效（此前回环 PASS 只依赖 RX 中断+轮询，未覆盖该路径，故一直未暴露）。
- 次要发现：`VDMA_S2MM_FAIL SR=0x15810`（SOFEarly/IRQErr 类错误）+ 每秒 CAMERA_STREAM_FAIL、MM2S_FRAMES 停在 1——相机流未进入 S2MM（本轮疑似相机未连接/未出流；genlock 联动导致 HDMI 帧计数冻结，属 S2MM 停止的伴生现象）。

### BD 前后对比（排除时钟嫌疑）

git 旧 BD vs 用户新 BD：172 处差异全部为 ENET0/MDIO/GPIO-EMIO/MIO 配置；**时钟相关仅 PCW_ACT_ENET0_FREQMHZ 10→125 MHz（ENET0 自身激活），FCLK/PLL 零变化** ⇒ PS 修改未影响 PL 相机时钟链。（旧 BD 存档 `display_test_bd_old_from_git.txt`）

### 修复（V3.1.2）

- `main.c`：新增 `eth_ms_now()`（ARM Global Timer 毫秒时基，XTime_GetTime/COUNTS_PER_SECOND）；`eth_service_base` 直接按 250/500 ms 调度 `tcp_fasttmr/tcp_slowtmr`，不再读取 ScuTimer 中断标志（该路径证明不可靠）；发送轮询改毫秒时基。
- `udp_video_tx.h/c`：`udp_video_tx_poll(now_ms)` + `UDP_TX_FRAME_INTERVAL_MS 1000`（1 fps）。
- 依据：Global Timer 路径已被证明工作（HDMI_HEARTBEAT 每秒打印即由其驱动的 sleep/usench）；GEM RX 中断已被回环 PASS 证明工作。

### 板会复测判据

串口 ~1 s 出现 `UDP_TX frame=0 ...` 且逐秒递增；GUI 显示移动彩条、完整帧 ~1/s 递增、丢帧/CRC=0。相机 S2MM 错误单列排查（见下）。

### 相机问题排查清单（下一板会）

1. 确认相机供电/排线是否就位（本轮 S2MM 立即报 SOF 类错误，疑似无有效流或流几何不完整）；
2. 若相机在位仍报错：核对 12:23 那次成功运行与本轮的硬件差异（仅 ELF 不同）→ 排查 ELF 变化影响；
3. HDMI 当前应为冻结帧（genlock 等 S2MM），属 S2MM 停止的伴生现象。

## 9. V3.1.2 编译错误修复（2026-09-08 13:29）

- 错误 1：`xtime_l.h: No such file or directory` —— 该 SDT BSP 不含 xtime_l.h；核对 BSP 后发现 `XTime/XTime_GetTime/COUNTS_PER_SECOND` 均声明于 `xiltimer.h`（COUNTS_PER_SECOND=CPU 时钟/2，即 ARM Global Timer，纯轮询读取、不依赖中断——usleep 即以同机制工作）。已改 include。
- 错误 2：`udp_video_tx.c:208 'tx_last_tick' undeclared` —— 上一轮批量替换漏掉 init 函数内一处；已改为 `tx_last_ms = 0`。
- 全部陈旧符号（xtime_l/tx_last_tick/TcpFastTmrFlag/TcpSlowTmrFlag）复查为零残留；括号平衡核查通过。
- 状态：`V312_SYNTAX_FIXED`，待用户重新 Build。
