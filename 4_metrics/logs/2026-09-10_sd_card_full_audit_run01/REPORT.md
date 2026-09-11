# G 盘 SD 卡全面只读检查（2026-09-10）

## 结论

当前已确认的问题集中在启动文件制作和板卡适配：`BOOT.BIN` 没有有效的 FSBL 加载描述、关闭了 FSBL 调试打印，并缺少 U-Boot；保留的 `image.ub` 仍使用 PYNQ-Z2 设备树，UART、PS 输入时钟和内存容量均未适配 EES-331。不能只修 BIF 就宣称完整 PYNQ 可启动。

本轮未写卡、修复文件系统、重编工程、下载 FPGA 或连接板卡。全卡读取已完成：15,634,268,160 B、0 次读取错误、870.21 秒（约 14.5 分钟），结果 `FULL_MEDIA_READ_COMPLETE`。总体检查结果为 `FULL_SD_AUDIT_COMPLETE_WITH_BOOT_AND_PORTING_DEFECTS`，不代表板级启动通过。

全卡 SHA-256：`5ecfc64c109302c0a2e9cdda1cb4a318f09197c19f0468d90a033e2fd730dfce`。扫描所得本地 IMG SHA-256 为 `f17405d25298a2c5ea23ccf95f868b42b18f819ff9d7fe5d079ac9ef53415861`，与重新完整读取 ZIP 解压流所得值一致。原始结果：`scan_result.json`。

## A. 介质、分区与原版镜像一致性

- 设备：G: 对应 `PhysicalDrive1`，USB Generic STORAGE DEVICE，容量 15,634,268,160 B，MBR。
- MBR 的 512 字节与原版镜像完全相同，签名 55AA。第一分区活动标记 0x80、类型字段 0x0C、起始偏移 4,096 B、大小 136,314,880 B；第二分区类型 0x83、起始偏移 137,363,456 B、大小 7,721,444,352 B。分区没有越界或重叠。
- BPB 实际为 **FAT16**（33,241 个簇，每簇 4,096 B），两份 FAT 一致；MBR 类型字段虽然标成 FAT32 LBA，但原版镜像也是这样。先前日志简称 FAT32 不准确；不能把此原版就存在的类型字段差异当作本次新增根因。
- `chkdsk G:` 未使用 `/F`、`/R` 等修改参数，报告文件系统无问题。第一分区可读取所有根目录启动文件。
- 第二分区为 ext4。完整 7,721,444,352 B **逐字节与原版 IMG 一致**，SHA-256 为 `8825a8f5e0a439a286779453b008e9b73f322d4368fac2e199d933ab1841cf9e`。
- G 盘根目录除 BOOT.BIN 外，boot.py、boot.scr、image.ub、REVISION 均与原版 IMG 中的对应文件逐字节一致。新增 Windows System Volume Information 与启动分区 FAT/目录元数据差异存在，不表示启动载荷损坏。
- 原版 ZIP 重新计算 SHA-256，与下载记录匹配：`ea6372e2d95e241dc7f891d30abc8af2eaf6650c0c16788c27dafba97f41cf8b`。完整解压流读取通过 ZIP CRC，解压内容 SHA-256：`f17405d25298a2c5ea23ccf95f868b42b18f819ff9d7fe5d079ac9ef53415861`。与本地 IMG 的最终一致性见结尾验收。

证据：`partition_table.json`、`scan_console.txt`、`scan_segments_partial.json`、`archive_verification.json`、`chkdsk_readonly.txt`、`card_fs_metadata.json`、`boot_and_file_comparison.json`。

## B. 当前 BOOT.BIN：确定的首级启动缺陷

G:/BOOT.BIN 大小 91,856 B，SHA-256 `eb88aa570030fa9d98f5b962c954ded787f0ccb85330326d029730654e466667`。它与 run03 BOOT_MIN.BIN 相同。

| 字段 | 当前卡上 BOOT.BIN | 原版 PYNQ-Z2 BOOT.BIN |
|---|---|---|
| FSBL 源偏移（0x30） | 0 | 0x1700 |
| FSBL 长度（0x34） | 0 | 0x18008 |
| FSBL 总长度（0x40） | 0 | 0x18008 |
| 启动头 checksum | 正确 | 正确 |
| image header 实际组成 | fsbl.elf（2 个载入分区） | zynq_fsbl.elf、u-boot.elf、system.dtb |

AMD Bootgen 2025.2 的只读 `-read` 输出独立确认这些字段。当前文件是一个普通 ELF 被分成两个载入分区，而非两个独立程序；根因仍为 BIF 没有 `[bootloader]` 属性。**checksum 正确不等于启动描述有效**。

打印缺陷由上一轮源码/编译参数/同哈希 ELF 审计证实：FSBL_DEBUG 与 FSBL_DEBUG_INFO 都未开启，横幅与错误字符串没有编入。因此修正启动头后，还需开启 DEBUG 并重编，才能使用横幅作为判据。

当前没有 U-Boot，无法把执行链传递给 image.ub。把 image.ub 放在根目录不会自动补足这个环节。纯 PS Linux 启动不必为了形式完整而强塞一个不匹配的 PL bitstream。

证据：`card_bootgen_read.txt`、`original_bootgen_read.txt`、`boot_and_file_comparison.json`；上一轮 `../2026-09-10_sd_boot_static_audit_run01/DIAGNOSIS.md`。

## C. image.ub 完整，但设备树未适配

image.ub 与原版完全一致。FIT 内核 payload 和 DTB payload 的 SHA-1 均与容器内声明一致，未发现传输/烧录损坏。默认 FIT 配置 `conf-1` 选择 kernel-0 + fdt-0。

| 项目 | 卡上内置设备树 | EES-331 / 当前最小 XSA | 影响阶段 |
|---|---|---|---|
| 控制台 | stdout-path=serial0:115200n8；serial0→UART0@e0000000；UART1 disabled | J3 对应 UART1，MIO48/49；最小 FSBL stdout 为 0xE0001000 | Linux 控制台不会按现配置输出到 J3 UART1 |
| PS 输入时钟 | ps-clk-frequency=50,000,000 Hz | 33.333333 MHz | Linux 时钟计算与实际硬件不一致，可影响串口、SD 等外设时序 |
| 内存范围 | /memory reg=<0 0x20000000>，512 MiB | 板卡 1 GiB，最小 XSA DDR 32 Bit、MT41K256M16 RE-15E | 仍保留 Z2 内存描述；少声明内存本身不能解释 FSBL 前静默 |
| SD 控制器 | SD0@e0100000 okay，has-cd=1 | SD0 MIO40..45、CD=MIO0 | 控制器选取一致，MIO0 是手册明确示例，并非已证实错误 |
| USB | USB0 okay | 最小 XSA USB0=0 | 后续 USB 功能尚未一致配置 |
| 板卡标识/外设 | pynq_board=Pynq-Z2，原版音频/UIO/PHY 等节点 | EES-331 | 需逐项适配，不能等同已支持 EES-331 |

这里确认的是文件中现有配置；修复后 U-Boot 是否做运行时 fixup，还需实际启动日志或导出的运行时设备树证明，不能预设它会自动修正。

**不缺根目录独立 system.dtb 不是错误。** 当前 boot.scr 优先加载 image.ub 并执行 `bootm 0x10000000`，内核使用 FIT 内的 DTB。只在 G 盘根目录添加一个新 system.dtb，并不能证明这个优先路径会用它；需修改 FIT 内 DTB 并更新 hash/重打包，或者明确改变启动路径后验证。

原版 BOOT.BIN 自带的 system.dtb 与 image.ub 内 DTB **逐字节相同**，均为 19,792 B、SHA-256 `5222b2632370b80b52e3ae02e656f6f995d328dbf60d33aa5b464f4dc4703c2d`。如果恢复原版 BOOT.BIN，也会把上述旧适配配置一并带回。

证据：`embedded_device_tree.json`、`embedded_system.dtb`、`fit_structure.json`、`fit_hash_checks.json`、`original_boot_dtb_comparison.json`、`boot_script.txt`。

## D. 原版镜像为何不能直接套用

当前本地 PYNQ-v3.0.1 源码包的 Pynq-Z2/petalinux_bsp/hardware_project/pynqz2.tcl 明确配置：

- PS 晶振 50 MHz；UART0 启用在 MIO14..15，UART1 未启用。
- DDR 数据总线 16 Bit，器件 MT41J256M16 RE-125。

而当前 EES-331 最小 XSA 为：33.333333 MHz、UART1 MIO48..49、32 Bit DDR MT41K256M16 RE-15E。

源码包配置与现场 DTB 的 Z2 假设一致，但本轮没有把原版 FSBL 完整反汇编还原并证明它与此 Tcl 的构建来源一一对应。因此可以确定“原版软件未完成 EES-331 适配”，不能据此宣称“原版 CPU 实测停在 DDR 训练第某步”。原版静默存在 UART 路由和时钟/DDR 配置差异，早先只定案 DDR 的说法仍应撤回。

最小 XSA 的 SD0 MIO40..45、CD=MIO0、Bank1 1.8V、UART1 MIO48..49 与已核验手册一致；没有证据支持立即改这些配置或反复修改 SW8。最小平台 hw/ps7_init.c 与实际 FSBL 源 ps7_init.c 哈希同为 `353D35F807279393E3F8001922BA7A09A6C77E833B2443B3FB176495CC2B8023`；抽取到的重叠 DDR 参数与冻结基线没有差异，当前没有再发现“FSBL 源沿用旧 ps7_init.c”的证据。

证据：从源码包提取的 `pynqz2.tcl`、`system-user.dtsi`，当前 XSA 参数 `xsa_parameters.json`，手册 `mineru_reuse.json`。

## E. Linux/PYNQ 文件系统与自动启动

由于卡上根分区已逐字节等于原版 IMG，使用原版 IMG 的只读 ext4 解析检查其目录和关键文件，避免挂载或回放 journal。

- 超级块 magic=0xEF53、state=1、mount_count=0；当前卡直接读出的超级块也一致。这些为文件系统元数据，不等同于全套 e2fsck 验证。
- 完整目录遍历：21,862 个目录、177,234 个普通文件目录项、20,733 个符号链接；0 个目录解析异常。未逐文件执行程序。
- /sbin/init 可解析到 systemd，Python 3.10 可读取；PynqLinux 3.0（Ubuntu 22.04 基础）；内核模块目录为 5.15.19-xilinx-v2022.1。
- Jupyter、bootpy、resizefs 服务本体与 basic.target.wants 启用链接存在；初次只查 /etc/systemd/system/jupyter.service 未找到不代表服务缺失，实际位于 /usr/lib/systemd/system/。
- 原版初始镜像没有 /etc/fstab；resizefs.sh 后续会创建 swap 对应条目。这是原版内容，不是 G 盘单独丢文件的证据。
- G:/boot.py 的有效代码会执行 `BaseOverlay("base.bit")` 并操作 PYNQ-Z2 LED；bootpy.service 通过脚本读取启动分区 boot.py，根分区包含原版 Z2 base.bit。这是 **Linux 起来之后的板卡适配待办**，不是当前首级无输出的原因。后续 EES-331 初次启动应避免自动加载未适配的 Z2 overlay，待有适配的位流后再启用。
- 剩余未分配空间约 7.78 GB 是小于卡容量的原始镜像布局；resizefs 服务用于后续扩容，不应把未扩容当作不能启动的原因。

证据：`rootfs_inspection.json`、`rootfs_extended.json`、`rootfs_startup_scripts.json`、`card_fs_metadata.json`。

## F. 修复建议及验收顺序（尚未执行）

1. 保留现有文件和哈希，在隔离目录修正 BIF 的 `[bootloader]`，检查 FSBL source/length/total 非零且范围有效。
2. 单独启用 FSBL_DEBUG_INFO 并真正重编；确认新 ELF 中横幅存在、stdout 为 UART1。用 PS-only 诊断镜像先验收冷启动 FSBL，必要时在初始化前后设置 OCM 标记/断点。
3. FSBL 通过后，准备适配的 U-Boot 与其所用 DTB；随后修改 image.ub 内 DTB 的 UART、时钟、内存与外设配置，并验证 FIT hash 和实际选择的配置。
4. 初次 Linux 上板前处理 boot.py 自动加载 Z2 base.bit 的行为，先验收 Linux 串口与根分区，再验收网络/Jupyter，最后验收 EES-331 Overlay。
5. 串口在 POR 前打开，完整记录 FSBL→U-Boot→Kernel→登录或 Jupyter；每一阶段有独立 PASS 判据。软件修复后仍不能启动时，保留冷启动现场再诊断 PC、BootROM 状态、PS 初始化、UART/SD 寄存器。

本轮属于“全面检查”，未执行以上修复。冻结 FPGA 项目保持只读。

## G. 手册解析复用及检查限制

使用项目 MinerU 技能复用 `2026-09-08_eth_zynq_psw_check_mineru_run01`，未启动新的解析任务。

- 结果：MINERU_PARSE_PASS；输入 E:/competition/1_docs/pdf/EES-331 User Guide.pdf。
- 本次实算输入 SHA-256：`27C26F39F3E35132A89FAE2155FA23575E850B0A22E3D9DC64FD73186B3F5949`，与旧 manifest 相同。
- Markdown：[EES-331 User Guide.md](../2026-09-08_eth_zynq_psw_check_mineru_run01/EES-331%20User%20Guide/auto/EES-331%20User%20Guide.md)。
- content JSON：[EES-331 User Guide_content_list.json](../2026-09-08_eth_zynq_psw_check_mineru_run01/EES-331%20User%20Guide/auto/EES-331%20User%20Guide_content_list.json)。413 个内容项，Markdown/JSON 均完整存在。
- 质量：ChineseQuality=pass，Fallback=false；无新增质量警告。已查看解析产出的 SD 配置图，明确 MIO40..45/CD MIO0，并以 content JSON/Markdown 核对 PS 时钟、DDR、UART。

Windows 主机没有可用 WSL/e2fsck，本轮用隔离安装的 dissect.extfs 只读解析及整分区原版比对替代内容检查；**不声称运行过 e2fsck 或完成全部 ext4 一致性规则验证**。全卡读取不等于写入/保持/真实容量压力测试，也不验证板卡 SD 电气接口。没有新板测日志，不能把检查结果称为 SD 启动 PASS。
