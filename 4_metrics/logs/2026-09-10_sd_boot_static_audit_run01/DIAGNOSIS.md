# SD 启动静默静态审计（2026-09-10）

结果：`STATIC_BOOT_IMAGE_DEFECT_CONFIRMED`。当前用户确认 SW8 已为 SD 启动且上电成功，接受为排查前提。本轮没有连接板卡、重新烧卡、重编 FSBL 或修改冻结工程；板级启动状态仍待修复后实测。

## 1. 已证实的启动镜像缺陷

run03 的 `fsbl_only.bif` 只有 ELF 路径，没有 `[bootloader]` 属性。归档 `BOOT_MIN.BIN` SHA-256 为 `EB88AA570030FA9D98F5B962C954DED787F0CCB85330326D029730654E466667`，与当日日志中写入卡上 BOOT.BIN 的哈希一致。本轮未重新读取卡上文件，结论适用于该归档产物及日志记录的最后一次卡上版本。

对实际 BIN 按 little-endian 读取启动头：

| 字段 | 偏移 | run03 BOOT_MIN.BIN | 备份的原版 PYNQ-Z2 BOOT.BIN |
|---|---|---|---|
| sourceOffset | 0x30 | 0x00000000 | 0x00001700 |
| fsblLength | 0x34 | 0x00000000 | 0x00018008 |
| totalFsblLength | 0x40 | 0x00000000 | 0x00018008 |

Zynq Bootgen 官方源码 `ZynqBootHeader::Link` 在 `GetFSBLImageHeader()` 为空时调用 `SetBHForSinglePartitionImage()`，后者将上述字段清零；有 FSBL 时才填入加载位置和长度。因此该 BIN 虽然包含一个 ELF 分区并能由 Bootgen 生成，却没有为 SD 冷启动提供有效的 FSBL 加载描述。这是当前最小镜像不能正常引导目标 FSBL 的直接软件原因。ELF 文件存在、ARM 格式正确、BIN 拷贝哈希一致都不能替代启动头验收。

注意：FSBL 加载地址/入口地址为 0 在这里可以正常，不能把 0x38/0x3C 为零本身列为故障；故障证据是源偏移与长度为零。

官方代码通过 HTTPS 获取，副本为本目录 `bootheader-zynq.h`、`bootheader-zynq.cpp`：

- https://github.com/Xilinx/bootgen/blob/master/zynq/include/bootheader-zynq.h
- https://github.com/Xilinx/bootgen/blob/master/zynq/src/bootheader-zynq.cpp

## 2. 已证实的打印判据缺陷

实际构建的 `Makefile` 中 `CFLAGS` 为空，构建日志没有 `-DFSBL_DEBUG` 或 `-DFSBL_DEBUG_INFO`。`fsbl_debug.h:37-48` 在两者未定义时令 `fsbl_dbg_current_types=0`，关闭 FSBL 横幅与错误打印。

归档 ELF 与当前构建目录 ELF 的 SHA-256 均为 `11E7963B163BD58CEBF9E9322E77399454C1FCEBF6A8B7D25A7EA65735DA8E3C`。GNU strings 对 `Xilinx First Stage Boot Loader`、`Boot mode is SD`、`PS7_INIT_FAIL`、`FSBL Status` 的匹配数均为 0。源码、构建参数与实际二进制相互印证：即使修复启动头让这个 ELF 得以运行，也不能期待它显示既定横幅。

STDOUT 配置为 UART1 `0xE0001000`，未发现 stdout 误选 UART0 的静态证据。`main.c:239` 先执行 `ps7_init()`，`main.c:285` 才打印横幅。因此即使开启 DEBUG，如果停在 PS 初始化阶段，横幅仍不足以定位；后续需使用 JTAG 断点或 OCM 阶段标记确认入口、PS 初始化前后的位置。

## 3. 仅含 FSBL 不能启动 PYNQ

run03 BIF 只有 FSBL，没有 U-Boot 或裸机应用。修正 `[bootloader]` 并启用 DEBUG 后可作为 FSBL 诊断镜像，但不能当作完整 PYNQ 镜像。卡上留有 `image.ub` 不会让该 FSBL 自动承担 U-Boot 的 Linux 加载职责。后续应分开验收 FSBL 首级启动与完整 PYNQ 启动链。

## 4. 修正此前结论的证据边界

- run03 `00_manifest.md` 所称“定案 Z2 FSBL 死于 ps7_init DDR 训练”没有对应执行位置/训练失败证据，必须降级为未证实假设；本轮不改写旧原始证据。
- 原版 PYNQ-Z2 BIN 的上述头字段非零，因此本轮定位出的打包错误只解释 run03 替换后的最小镜像，不能反推原版两次静默也是同一原因。
- diag6 的 `BOOT_MODE=0` 是拨码修正前的历史读数，不能推翻用户当前确认；diag8 的 JTAG `DR shift through all ones` 只证明当时无法枚举目标，不能唯一归因为主板未供电。
- 本轮没有 SD 模式下最新 PC/寄存器和串口原始抓取，不宣称已证明 ROM 的实际停机位置或板级恢复。
- run03 关于“SD0 CD 不影响 FSBL 读卡”的绝对说法不成立：当前 `XPAR_XSDPS_0_HAS_CD=1`，底层 `XSdPs_CheckCardDetect()` 会在检测无卡时返回失败。实际 MIO0 接线是否正确未在本轮对照手册解析，因此仅保留为修复上述缺陷后若出现 SD 初始化失败的待查项，不列为已证实根因。

## 5. 最小修复与验证建议（尚未执行）

1. 在新的隔离证据目录中复用现有 XSA/FSBL 源码，先只修正 BIF 属性为 `[bootloader] <fsbl.elf 的绝对路径>`；验证新启动头 `sourceOffset`、`fsblLength`、`totalFsblLength` 非零，保留前后 BIN 与哈希。
2. 再单独启用 `-DFSBL_DEBUG_INFO` 并重新编译 FSBL；验证编译命令和实际 ELF 的横幅字符串，确认 stdout 为 UART1。重新打包并再次检查启动头；不能只改宏而复用旧 object。
3. 冷启动诊断时在 POR 前打开 COM6 115200-8-N-1，保存完整串口输出。出现 FSBL 横幅可证明执行已越过 `ps7_init()`，不等同于完整 PYNQ 启动成功。
4. 若仍静默，先恢复可靠 JTAG 枚举并读取本轮 SD 启动的 BOOT_MODE/PC/启动状态；在保留冷启动现场后再用受控 JTAG 加载或阶段断点区分 ROM 读卡、FSBL 入口、PS 初始化与 UART 路径。不要先跑 ps7_init.tcl 覆盖待诊断现场。
5. FSBL 验证通过后再打包适配板卡的 U-Boot，并验证设备树/内核链，最后验收 PYNQ。

## 复现与证据

- 复现：`powershell -ExecutionPolicy Bypass -File E:/competition/4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/audit.ps1`
- 原始输出：`audit_console.txt`（哈希、BIF、宏、启动头和字符串计数），`fsbl_strings.txt`，`fsbl_readelf.txt`。
- 未调用 MinerU：本轮只解释 Markdown 工程日志、代码、构建输出与 ELF/BIN；未读取或解释 PDF/Office/扫描文档内容。
- Web 搜索工具返回 HTTP 404；改用 HTTPS 直接读取 Xilinx 官方 Bootgen 开源代码，未采用第三方解释。
