# EES-331 SD 启动文件修正记录

日期：2026-09-10。授权：用户“根据查验的问题完整修正”。适用目标：EES-331 最小 PS 系统的 SD → FSBL → U-Boot → Linux 启动链。

## 当前状态

候选镜像 `SD_BOOT_CANDIDATE_STATIC_PASS`，240 项检查通过。2026-09-10 16:09:58 +08:00 已部署 G 盘，结果 `SD_DEPLOY_READBACK_PASS`，四个新文件和两个保留文件哈希全部一致，卷缓存刷新成功。写后 `chkdsk G:` 只读检查未发现问题。冻结 `2_fpga/` 未修改；板测状态 `NOT_TESTED`。

部署原始证据：`deploy_result.json`、`deploy_20260910_160957_console.txt`、`chkdsk_after_deploy.txt`。工程技能路径审计 `skill_path_audit.txt` 为 pass=true。SD 根目录已无本次临时文件；备份保留在 PC 的 `sd_backup/`。

## 已修正的问题

| 审计发现 | 本次修正 |
|---|---|
| BOOT 缺 `[bootloader]`，ROM 所需的 FSBL 源偏移和长度为零 | 使用正确 BIF 重新打包；源偏移 0x1700、加载长度 0x18010，头校验通过 |
| 原 FSBL 未编入打印，不能以“没有横幅”判定其阶段 | 隔离复制 EES-331 XSA 生成的 FSBL/BSP，全部源码以 `FSBL_DEBUG_INFO` 重编；ELF 与实际 BOOT 载荷均有横幅/SD 模式字符串 |
| 卡上 BOOT 只有普通 ELF 数据，没有后续 Linux 引导链 | BOOT 包含可引导 FSBL、U-Boot（加载/入口 0x04000000）、控制 DTB（加载 0x00100000） |
| PYNQ-Z2 控制台 UART0 不对应 EES-331 UART1 | 控制 DTB 与 FIT 内 DTB 同步改 UART1，serial0 → e0001000，115200，Linux console=ttyPS0 |
| 原 DTB 使用 50MHz PS 时钟、512MiB DDR | 按当前 EES-331 XSA 设 33333333Hz、1GiB；FSBL 的 ps7_init.c 保持该 XSA 生成版本 |
| Ethernet PHY@1 位于错误的 /amba 树 | 放入实际 GEM0 节点，使用板测已有 PHY 地址 0；删除 Z2 专属复位属性 |
| 原 DTB 声明了最小 XSA 未启用的设备、旧 PL 节点 | 禁用 USB0/I2C/QSPI，移除 Z2 PL 节点；保留根节点下 zocl 支持，实际驱动启动待板测 |
| boot.scr 实际使用 image.ub 内 DTB | 重建 FIT 并更新 SHA1；BOOT 内、FIT 内和独立 system.dtb 三者相同 |
| boot.py 自动加载 Z2 base.bit | 换成仅打印状态的启动钩子，不自动配置 PL |

SD0 使用已有 MIO40..45/CD MIO0 配置，未盲改 PS 管脚；设备树为 4bit、50MHz 上限、禁止 1.8V 信令切换、忽略写保护。USB 等禁用是匹配当前最小硬件设计的结果，不代表这些功能已移植完成。

## 校验与来源

- `candidate_validation.json`：240 项独立二进制检查；`validate_candidate.py` 可复现。校验 BOOT/PHT 校验和、边界、ELF 的 LOAD 段与 BOOT 对应、OCM 地址、U-Boot 载荷一致、FIT 哈希/默认 conf-1/内核元数据、设备树 phandle/时钟/alias/symbol、boot.scr CRC，以及 boot.py 不加载 Overlay。
- `bootgen_read_console.txt`：Bootgen 2025.2 原生解析全部头表；`fsbl_build_console.txt`：完整重编日志。FSBL 源码来自 `2_fpga/3_pynq_test/vitis/ws_fsbl/pynq_plat/zynq_fsbl` 的隔离副本。
- `dtc_roundtrip_console.txt`：DTC 二进制回读零警告。`dtc_build_console.txt` 的源文件 numeric-phandle 警告来自原 DTS 反编译后没有标签引用注释；独立引用校验和二进制 roundtrip 已通过，未用屏蔽警告代替验证。
- U-Boot 是原版 `U-Boot 2022.01 (Apr 04 2022)` 载荷复用，**没有声称从源码重编**。`uboot_external_dtb_proof.json` 给出实际 ARM 指令：从 0x00100000 取 magic，与 0xd00dfeed 比较并返回该地址。重新封装的 ELF 是 EXEC、单 LOAD 段，入口/物理加载地址均 0x04000000；最终 BOOT 的 U-Boot 数据与原始 BOOT 中载荷逐字节一致。
- 官方源码参照：Xilinx `u-boot-xlnx/xilinx-v2022.1` 的 [board.c](https://github.com/Xilinx/u-boot-xlnx/blob/xilinx-v2022.1/board/xilinx/common/board.c)、[Zynq board.c](https://github.com/Xilinx/u-boot-xlnx/blob/xilinx-v2022.1/board/xilinx/zynq/board.c)、[clock driver](https://github.com/Xilinx/u-boot-xlnx/blob/xilinx-v2022.1/drivers/clk/clk_zynq.c)。本地副本在 `sources/`，外部 DT 选择结论还经实际二进制验证。
- PHY 地址依据：`../2026-09-08_mainproj_eth_loopback_integrate_run01/serial_c1_camera_full.txt` 中 `link speed for phy address 0: 1000`。Linux 下 PHY/网络驱动尚未实测。
- 保留原 Linux 内核，SHA256 `3d45ed1350bc1509f1f62d139fe1502b9da5437b86de0404aa1de1cbbfeb7364`；根分区没有写入。此前整卡读取无错、Linux 分区与镜像一致的证据在 `../2026-09-10_sd_card_full_audit_run01/REPORT.md`。该检查不是 e2fsck 或容量压力测试。

## 部署清单与回退

仅替换 G:/BOOT.BIN、G:/image.ub、G:/boot.py，新增 G:/system.dtb。boot.scr、REVISION 保留。实际启动使用 BOOT 内控制 DTB 和 FIT 内 Linux DTB，独立 DTB 仅保留为可检查工件。

| 文件 | 字节 | SHA256 |
|---|---:|---|
| BOOT.BIN | 1082696 | 3ea3eae30dba8646ddb597abf098594a99ed6c0250576bed12a9eca91c3902a0 |
| image.ub | 6459560 | 6c101d5352e8da48e9ee5493135621c0e62f148023fcf4826ebabbe4e0f194d0 |
| system.dtb | 14919 | 76e29723d185ac4a50700338bfcf872113a43409bbbe8eded34fbbd723ef6434 |
| boot.py | 227 | 42d702f74e73a7bf444c52000ca893c03e9166bd61371c8adf52d52f3b53e17f |

原 G 盘五个文件在 `sd_backup/`，原 BOOT 哈希 `eb88aa570030fa9d98f5b962c954ded787f0ccb85330326d029730654e466667`。这份备份恢复的是修复前故障现场，并非可启动基线。

部署命令：`powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/4_metrics/logs/2026-09-10_sd_boot_fix_run01/deploy_sd.ps1 -Mode Deploy`。

脚本先核对卡容量 15634268160、MBR 分区起点 4096/长度 136314880、读卡器身份与原文件哈希；暂存所有新文件并 Flush(true)，最后提交 BOOT，保留旧文件至最终读回通过后删除临时副本，并对 G 卷调用 FlushFileBuffers。它不是整套文件的原子事务；失败时保留现场与 PC 备份，不继续拔卡。

需要主动恢复原故障现场时：同一脚本 `-Mode Rollback`。只在已部署文件仍匹配清单时执行，恢复备份并删除新增 system.dtb；不会格式化或修改根分区。本轮不执行回退。

`candidate/BOOT_FSBL_DIAG.BIN` 仅含带打印的 FSBL，为分阶段诊断备用，**不是 G 盘默认启动镜像**。

## 板测边界与下一步

本轮离线通过不等于板级启动 PASS。安全移除 G 盘后插回板卡，先打开 COM6、115200-8-N-1、关闭流控，保持用户已经确认的 SD 拨码，再断电冷启动，保存从上电开始的完整 UART 文本。

预期依次看到 `Xilinx First Stage Boot Loader`、SD 模式与加载记录、U-Boot 横幅、Linux 启动与登录提示。FSBL 的横幅位于 PS 初始化之后：若仍完全静默，不能据此直接确定 DDR 故障；保留当前卡不再重烧，使用 JTAG 读取当次 BootROM/FSBL 执行位置。出现 FSBL 而无 U-Boot 则检查加载/交接日志；出现 U-Boot 而无 Linux 则检查 SD/FIT/控制台；进入 Linux 后再验收网络与 Jupyter。没有本轮板测记录前，PYNQ 完整功能、网络、USB和自定义 Overlay 均不标记 PASS。
