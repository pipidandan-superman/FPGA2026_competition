# G 盘 SD 卡文件检查

时间：2026-09-10 15:30 +08:00。结果：`SD_CARD_G_BOOT_DEFECT_CONFIRMED`。

本轮直接读取 G 盘，未写卡、修复文件系统、弹出设备、重编或连接板卡。

## 磁盘与文件

- G: 位于磁盘 1，USB Generic STORAGE DEVICE，容量 15,634,268,160 B（16GB 卡），MBR。
- 第 1 分区：130 MiB，卷标 PYNQ，分区类型 FAT32 XINT13；Get-Volume 的 FileSystem 字段返回 FAT。Windows 显示 Healthy/Online，只是枚举状态，不能替代全卡介质和文件系统检测。
- 第 2 分区：7,721,444,352 B，无盘符，Windows 类型显示 Unknown；本轮未读取其文件系统内容。

| 根目录文件 | 字节数 | 检查 |
|---|---:|---|
| BOOT.BIN | 91,856 | 与 run03 的 BOOT_MIN.BIN 逐字节相同，启动头存在确定缺陷 |
| boot.py | 991 | 完整读取并计算 SHA-256 |
| boot.scr | 2,776 | 完整读取并计算 SHA-256、保存前 64 字节 |
| image.ub | 6,464,328 | 完整读取并计算 SHA-256、保存前 64 字节 |
| REVISION | 83 | Release 2022_10_22 93ddd21 |

文件存在/可读与计算哈希不代表已经验证其板卡兼容性或与官方镜像逐字节一致。

## BOOT.BIN 直接证据

SHA-256：`EB88AA570030FA9D98F5B962C954DED787F0CCB85330326D029730654E466667`。

- 与 `2026-09-10_pynq_fsbl_rebuild_run03/BOOT_MIN.BIN` 逐字节对比：True。
- 0x30 sourceOffset = 0；0x34 fsblLength = 0；0x40 totalFsblLength = 0。
- `Xilinx First Stage Boot Loader`、`Boot mode is SD`、`U-Boot` 字符串均不存在。
- 结合上一轮 BIF/编译/ELF 审计，此卡上的文件就是缺 `[bootloader]`、未启用 FSBL DEBUG、只有 FSBL 分区的诊断版本。字符串缺失只是补充证据，分区组成由归档 BIF 和逐字节相等确定。

结论：此前基于日志的“卡上可能仍为错误镜像”已升级为 G 盘现场读取确认。首先应修正启动文件；当前没有新的证据指向拨码、供电或 SD 卡硬件故障。完整 PYNQ 还需要适配的后续引导组件；本轮没有完成板级启动验证。

复现脚本：`check_sd.ps1`；完整原始输出：`console.txt`；全部根目录文件 SHA-256：`file_hashes.json`。

关联分析：`../2026-09-10_sd_boot_static_audit_run01/DIAGNOSIS.md`。
