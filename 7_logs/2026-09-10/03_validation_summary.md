# 2026-09-10 验证摘要

## 已验证事实

### V1 仓库同步（PASS）

- `git fetch` → main 落后 origin/main 26 提交；本地唯一未跟踪文件
  `2_fpga/0_diaplay_test/doc/ethernet_bringup_checklist.md` 与 incoming 无
  路径冲突（`git diff --name-only main origin/main | grep ethernet_bringup`
  为空）。
- `merge --ff-only` 成功：`23a874e → c60291a`（含 tag
  `camera-hdmi-visual-pass-20260907`、`udp-color-fix-pass-20260908`）。

### V2 C1.2 冻结工件审计（关键发现）

| 工件 | 清单期望 SHA-256 前缀 | 本机实际 | 判定 |
|---|---|---|---|
| ELF `2_fpga/0_diaplay_test/vitis/hw_20260908_eth/app_component.elf` | `3e295d51` | `3e295d51` | **PASS**（git 内唯一在库的最终固件） |
| BIT `display_test_wrapper.bit`（`7cb11f7d`） | `7cb11f7d` | 无此文件 | **缺失**（`git ls-files` 证实 .bit 不在库） |
| XSA `display_test_wrapper.xsa`（`30644b31`） | `30644b31` | 无此文件 | **缺失**（.xsa 不在库） |
| 本地遗留 BIT `proj/.../impl_1/display_test_wrapper.bit` | — | `34adc740` | 过时（09-06 zip 版），不可用 |
| 本地遗留 XSA `vitis/display_test_wrapper.xsa` | — | `51351996` | 过时，不可用 |
| 仓库 BD `display_test.bd` | — | `PCW_ENET0_PERIPHERAL_ENABLE=0` | git 内是以太网使能前版本 |
| 上位机 `3_host/udp_video/dist/EES331_UDP_Viewer.exe` | `a4b75ed3`（09-08 色差修复报告） | `a4b75ed3` | **PASS**（BGR 修正版 V1.2） |

结论：复现必须先补齐 BIT+XSA（队友机器上有，哈希见
`4_metrics/logs/2026-09-10_repro_prep_run01/REPRO_STATUS.md` §1）。

### V3 工具链定位（PASS）

- Vivado 2025.2：`E:/WorkApps/Xilinx/Vivado_2025_2/2025.2/Vivado/bin/vivado.bat`（含 `bootgen.bat`）
- Vitis 2025.2：`E:/WorkApps/Xilinx/Vivado_2025_2/2025.2/Vitis/bin/vitis.bat`
- XSCT：2025.2 已移除（bin 目录枚举无 xsct*）→ ELF 加载走 Vitis GUI Run
- 注意：开始菜单快捷方式指向 `E:\WorkApps\Xilinx\2025.2\...` 为失效路径，
  实际布局见上

### V4 PYNQ 镜像物料（PASS）

- 官方直链（pynq.io/boards.html 提取）：
  `https://download.amd.com/opendownload/pynq/pynq_z2_v3.1.1.zip`
- 下载完成：1,926,017,023 B == HTTP Content-Length（精确一致）
- zip SHA-256：`d7774bb6c56b79ea67e4dbfadca443c51ae6152b8c71799e79dd81e4782d6b03`
- 解压 PASS：`pynq_z2_v3.1.1.img` 8,337,309,696 B，SHA-256
  `4a6ac1cdbb413d768fcb059b7182e1f53aa7f728b898b7f5061cbb0b7cc93aab`
- 镜像结构核实（MBR/FAT 解析）：part1 FAT16 引导区 128MiB
  （`BOOT.BIN` 1,165,852 B / `BOOT.PY` 991 B / `BOOT.SCR` 3,473 B /
  `IMAGE.UB` 7,147,780 B）+ part2 ext4 7.64GiB
- 路径：`0_assets/pynq/`（gitignored，不入库），哈希文件同目录

## 本轮验证目标之外的产出（链接）

- `4_metrics/logs/2026-09-10_repro_prep_run01/REPRO_STATUS.md`
- `4_metrics/logs/2026-09-10_repro_prep_run01/prog_frozen_bit.tcl`
- `4_metrics/logs/2026-09-10_repro_prep_run01/enable_enet0_export_xsa.tcl`（未授权不运行）
- `4_metrics/logs/2026-09-10_repro_prep_run01/BOARD_ACCEPTANCE_CHECKLIST.md`
- `1_docs/PYNQ部署方案_EES331_2026-09-10.md`

### V5 烧卡工具核验（PASS，当日追加）

- 对象：微信收到的 `win32diskimager-1.0.0-install.exe`（12,567,188 B，未签名——官方发布本就不签名）
- 本机 SHA-256：`a51c9fc75c9caa44df03502838f229a70d484963f54675c241799093a59d8874`
- 比对基准：Chocolatey 官方包 `win32diskimager.install/1.0.0.20181220` 内嵌
  `checksum = 'a51c9fc75c9caa44df03502838f229a70d484963f54675c241799093a59d8874'`（sha256，指向 SourceForge 官方 URL）
- 判定：`WIN32DISKIMAGER_GENUINE_PASS`；该工具非 AMD 官方出品（第三方开源），
  已在 `1_docs/PYNQ部署方案_EES331_2026-09-10.md` §2 更新工具行。

### V6 队友 EES-331 PYNQ 镜像转移与核验（PASS，当日追加）

- zip `4558c5ff...` → 解压 img `203e9f79...`（7,858,807,808 B），
  转移至 `0_assets/pynq/ees331/`。
- 引导文件提取 + 设备树六项核验全 PASS（详见
  `4_metrics/logs/2026-09-10_ees331_pynq_image_transfer_run01/MANIFEST.md`）：
  UART1 控制台（serial0 别名指向 UART1，`console=ttyPS0` 落位正确）、
  1 GiB 内存、GEM0+PHY0 rgmii-id、SD0、pynq_board=EES-331、
  BOOT.PY 显式禁用 base overlay（PS-only 镜像定位）。
- BOOT.BIN 1.08MB，AA995566 Zynq-7000 签名，无比特流。
- 判定：`EES331_PYNQ_IMAGE_VERIFY_PASS`；板级启动验证待烧卡。
- 写卡脚本 `flash_ees331_pynq.ps1` 已就绪（admin+唯一 USB 盘+读回校验）。

### V7 烧卡尝试与恢复（当日追加，按用户指令终止）

- 尝试链：PowerShell FileStream（run1/2，静默退出且**写入了镜像前部数据**——
  卡被重写为镜像分区表，Windows 只显示 128MiB FAT16 引导分区"129MB"）
  → python ctypes v1（run3/4，`open_osfhandle` EBADF：CreateFileW 句柄哨兵
  比较错误，已修）→ 纯 ctypes v2（run5，卷 GUID 路径尾反斜杠导致
  WinError 2，已修）→ run6：盘句柄打开成功但 **WriteFile WinError 5
  （拒绝访问）**。
- 关键事实：文件级写入 F: 正常、管理员组成立、UAC 提权有效
  （wipe 脚本 elevated=True）、无 RemovableStorageDevices 策略——
  raw 磁盘写入被拒的机理未定（疑与本机某过滤驱动相关），属未解项。
- 按用户指令（停止烧写、清空 SD 卡）：`wipe_sd.ps1` 执行
  Clear-Disk → 全容量分区 → FAT32 格式化（`EES331_SD`，F:，14.54GB 全部可用）。
  判定：`SD_WIPE_DONE`；镜像烧录**未完成**，镜像文件与核验证据保留在
  `0_assets/pynq/ees331/` 与本 run 目录。
- 下次烧卡建议：优先 Win32DiskImager（走卷设备 \\.\F: 路径，可能绕开
  raw 磁盘写入拦截）；若同样被拒，则排查本机安全类软件的 USB 写入管控。

## 最终结果

- 同步：`SYNC_PASS`；工件审计：`AUDIT_PASS（发现 2 缺件）`；
  工具链：`TOOLCHAIN_LOCATED`；镜像：`PYNQ_IMAGE_READY`。
- 板级复现：**PENDING（等 BIT/XSA）**——无板级动作，本轮不产生板级 PASS。
