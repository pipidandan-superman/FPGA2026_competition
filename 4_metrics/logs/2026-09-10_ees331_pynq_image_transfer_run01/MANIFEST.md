# 队友 EES-331 PYNQ 镜像转移与核验（2026-09-10）

- 来源：微信传输 `C:\Users\aaacharon\Downloads\ees331_pynq_v3.0.1_ps_sd_20260910.zip`
- 动作：转移至工作区 `0_assets/pynq/ees331/`（zip 原件保留在 Downloads），
  解压、哈希、引导文件提取、设备树核验。本轮无板级动作。

## 1. 文件与哈希

| 文件 | 大小 | SHA-256 |
|---|---|---|
| zip（原样） | 1,809,286,566 B | `4558c5ff0e863c87a1523a27a976a08ed7f7a0452e4883ae457b814f056adc51` |
| `ees331_pynq_v3.0.1_ps_sd_20260910.img` | 7,858,807,808 B | `203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a` |

## 2. 镜像结构（MBR）

| 分区 | 类型 | 容量 | 内容 |
|---|---|---|---|
| p1 | FAT16 (0x0C) | 128 MiB | BOOT.BIN / BOOT.SCR / IMAGE.UB / BOOT.PY / SYSTEM.DTB / REVISION |
| p2 | ext4 (0x83) | 7.19 GiB | Linux 根文件系统（mmcblk0p2） |

引导文件提取（`boot_files/`，哈希见 `extract_boot_files_output.txt`）：

| 文件 | 大小 | SHA-256 |
|---|---|---|
| BOOT.BIN | 1,082,696 B | `3ea3eae3...902a0` |
| BOOT.SCR | 2,776 B | `7013e149...359f4` |
| IMAGE.UB | 6,459,560 B | `6c101d53...f194d0` |
| BOOT.PY | 227 B | `42d702f7...3b53e17` |
| SYSTEM.DTB | 14,919 B | `76e29723...6434` |
| REVISION | 83 B | `4890cc06...b19` |

## 3. 设备树核验（`inspect_dtb_output.txt`）——全部 PASS

| 检查项 | 结果 |
|---|---|
| 根节点 | `model = "EES-331 Zynq-7020 PS-only PYNQ bring-up"`，`compatible = "ees,ees-331 xlnx,zynq-7000"` ✅ |
| 控制串口 | UART1 `serial@e0001000` status=okay @115200（UART0 禁用）；`aliases: serial0 → serial@e0001000`，故 `console=ttyPS0` 实际落在 UART1（MIO48/49）✅ |
| 内存 | `/memory@0` reg = 0x00000000_40000000 = **1 GiB** ✅ |
| 以太网 | GEM0 `ethernet@e000b000` status=okay，rgmii-id，PHY 地址 0；GEM1 禁用 ✅ |
| SD 卡 | SD0 `mmc@e0100000` status=okay（root=/dev/mmcblk0p2）✅ |
| pynq_board | `"EES-331"` ✅ |

## 4. BOOT.PY 定位

```python
"EES-331 startup hook for the PS-only PYNQ bring-up image."
"Automatic loading of the PYNQ-Z2 base overlay is disabled."
```

即队友交付的是 **PS-only 启动镜像**：BOOT.BIN 仅 FSBL+U-Boot（1.08 MB，
头部 AA995566 Zynq-7000 签名确认；无比特流），PL 上电空载，待后续以
overlay 方式加载 EES-331 版 bit。与 C1.2 裸机基线互不冲突。

## 5. 结论与边界

- `EES331_PYNQ_IMAGE_VERIFY_PASS`（镜像级核验；板级启动验证待烧卡上电）。
- BOOT.BIN 内 FSBL 的 PS 初始化（DDR/MIO/ENET0/SD0 寄存器序列）无法在
  主机侧静态核验，属首次上电验证项。
- 根文件系统内容（内核版本、PYNQ 库、python 包）未在主机侧解包检查，
  上板后用 `uname -a` / `pip list` 验证。
- 本镜像基于 PYNQ `Release 2022_10_22 93ddd21`（REVISION 文件），与
  `0_assets/pynq/pynq_z2_v3.1.1.img`（官方 v3.1.1 原版）并存，前者为当前
  唯一上板目标。

## 6. 下一步（等 TF 卡插入）

写卡脚本 `flash_ees331_pynq.ps1`（本目录）：USB 总线 + 10–64GB 容量唯一
命中 TF 卡 → raw 写入镜像 → 读回全盘校验。写完插板、SD 启动模式、
串口验收（见 `BOARD_ACCEPTANCE_CHECKLIST.md` 追加节）。
