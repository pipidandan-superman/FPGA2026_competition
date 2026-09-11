# 板会复现操作清单（EES-331，C1.2 基线复现）

> 目标：在自有 EES-331 板上复现队友的 `udp-camera-c12-pass-20260908` 板级状态。
> 前置：`REPRO_STATUS.md`——需要队友补传 BIT + XSA（ELF 已在 git）。
> 执行人：AI 侧成员 ｜ 2026-09-10

## 0. 物料

| 项 | 状态 |
|---|---|
| EES-331 板卡 + 电源 + OV5640 摄像头 + HDMI 显示器 | ☐ |
| JTAG 下载器 + USB 转串口线 | ☐ |
| 网线（直通）+ PC 有线网口 | ☐ |
| `display_test_wrapper.bit`（`7cb11f7d...`，4,045,696 B） | ☐ 待队友补传 |
| `display_test_wrapper.xsa`（`30644b31...`，578,739 B） | ☐ 待队友补传 |
| ELF 已在仓库：`2_fpga/0_diaplay_test/vitis/hw_20260908_eth/app_component.elf`（`3e295d51...`） | ☐ 已就位 |

## 1. 收件校验（到手先做）

```
sha256sum display_test_wrapper.bit   # 期望 7cb11f7d...192e7
sha256sum display_test_wrapper.xsa   # 期望 30644b31...22d0
```
不匹配 → 停，找队友核对，不得继续。

## 2. PC 网络配置

1. 有线网卡静态 IPv4：`192.168.240.2` / `255.255.255.0`（网关可空）
2. 防火墙：对专用网络放行 UDP 5000（或临时关闭该配置文件的防火墙）
3. 串口终端打开板卡 COM 口：`115200-8-N1`

## 3. 编程 BIT（Vivado HW Manager）

```
E:/WorkApps/Xilinx/Vivado_2025_2/2025.2/Vivado/bin/vivado.bat -mode tcl \
  -source 4_metrics/logs/2026-09-10_repro_prep_run01/prog_frozen_bit.tcl \
  -tclargs <bit 绝对路径>
```
PASS 判据：控制台出现 `PROGRAM_DONE display_test_wrapper.bit`。☐

## 4. Vitis：platform + ELF（一次性，XSA 到位后做）

1. Vitis 2025.2 → 新建 platform，XSA 指向收到的 `display_test_wrapper.xsa`
   （或按队友 09-08 流程：`hw_20260908_eth` 已有 platform 结构则直接指定 XSA）
2. 新建/导入 `app_component` 应用（源码：`2_fpga/0_diaplay_test/vitis/app_component/src/`）
3. Build → Run（JTAG 下载 ELF 运行）
   - 注：ELF 也可直接用仓库里已核验的 `hw_20260908_eth/app_component.elf`，
     Run 时选择下载该 ELF 即可，无需重编译。

## 5. 串口验收标记（按序出现打钩）

```
☐ UART_TEST_PASS
☐ ETH_LOOPBACK_INIT_BEGIN
☐ PHY 1000M（链路协商）
☐ ETH_LWIP_OK
☐ ETH_UDP_ECHO_OK
☐ UDP_TX_INIT_OK
☐ LOOPBACK_TEST_READY
☐ VDMA_INITIAL_BEGIN
☐ HDMI_HEARTBEAT（周期出现）
☐ UDP_TX frame=N packets=640（N 递增）
☐ HEARTBEAT rx=/tx=/err=（周期出现）
```

## 6. PC 侧验收

```
☐ ping 192.168.240.10 通
☐ EES331_UDP_Viewer.exe 打开，数据源 192.168.240.10:5000
☐ 显示相机实时画面（非彩条、非黑帧）
☐ 完整帧持续递增，帧率（累计均值）≈6.3 fps
☐ 丢帧=0、CRC 错=0、重复/坏头=0（≥5 分钟）
```

上位机必须用 BGR 修正版 V1.2 exe：
`3_host/udp_video/dist/EES331_UDP_Viewer.exe`（SHA-256 前缀 `a4b75ed3`，已核验）。

## 7. HDMI 目视（可选，与 UDP 流独立）

显示器切到板卡 HDMI 输入；无画面则按一次板卡复位后再看。
☐ 相机画面正常显示。

## 8. 收尾

- 全部满足 → 记 `REPRO_C12_PASS`；原始串口日志、GUI 截图、哈希归档
  `4_metrics/logs/2026-09-10_<run名>/`，链接进 `7_logs/2026-09-10/03_validation_summary.md`。
- 任一不满足 → 停在该步取证（串口全文 + 截图），不得跳步；对照
  `2026-09-08` 各 run 报告排查（端口 5000、BGR 字节序、BIT/ELF 配对纪律）。

---

# 追加：PYNQ 镜像首启验收（ees331_pynq_v3.0.1_ps_sd_20260910）

> 前置：镜像已转移并核验（`4_metrics/logs/2026-09-10_ees331_pynq_image_transfer_run01/MANIFEST.md`），
> 写卡用同目录 `flash_ees331_pynq.ps1`（自动识别+读回校验）。

## F1 写卡

```
☐ TF 卡插入读卡器（8–128GB USB 盘唯一命中）
☐ 管理员 PowerShell 运行 flash_ees331_pynq.ps1 -Image <img 路径>
☐ WRITE_DONE + VERIFY_PASS（全盘读回哈希一致）
```

## F2 上电启动（SD 启动模式，按板手册核对拨码）

```
☐ 串口（COM，115200-8-N1）出现 U-Boot 输出
☐ 内核启动日志（console 落在 UART1 → ttyPS0）
☐ 到登录提示 / PYNQ 欢迎信息
```

## F3 网络与 Python（PC 静态 IP 192.168.240.2/24，网线直连）

```
☐ ping 通板卡（先看串口里 DHCP/静态得到的 IP；默认 DHCP，
   若直连拿不到地址，用 f1 中的办法先给 PC 网口开 DHCP 或按方案文档 S5 改 netplan）
☐ ssh xilinx@<ip>（默认密码 xilinx）
☐ python3 -c "import pynq,numpy; print(pynq.__version__)"
☐ 浏览器 http://<ip>:9090 Jupyter（密码 xilinx）
```

## F4 收尾

- 全部满足 → `EES331_PYNQ_BOOT_PASS`，串口日志/截图归档当日新 run 目录。
- PL 联动（overlay 加载 EES-331 bit、HDMI/摄像头）属下一阶段，不在本轮验收。
