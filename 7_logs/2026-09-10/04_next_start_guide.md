# 2026-09-10 下次启动指南

## 第一步（更新：SD 卡已清空恢复，镜像烧录暂停）

- SD 卡已按用户指令清空并重建为全容量 FAT32（F: `EES331_SD`，14.54GB）。
- 烧录 PYNQ 镜像（`0_assets/pynq/ees331/ees331_pynq_v3.0.1_ps_sd_20260910.img`）
  暂停；恢复时**首选 Win32DiskImager**（用户已有安装包），本机 raw 磁盘
  WriteFile 存在未解的 ACCESS_DENIED（详见 03_validation_summary V7）。
- C1.2 裸机复现仍等队友补传 BIT（`7cb11f7d`）+ XSA（`30644b31`），校验后按
  `BOARD_ACCEPTANCE_CHECKLIST.md` 第一部分执行。

## 成功判据

1. `EES331_PYNQ_BOOT_PASS`：烧卡（读回校验）→ 上电 → ssh → `import pynq`。
2. `REPRO_C12_PASS`：验收清单全绿 + 原始证据归档。

## 阻塞项与最小有用动作

- 阻塞 1：raw 写卡被拒（未解）。最小动作：用 Win32DiskImager 烧一次；
  若被拒，检查本机安全软件的"USB 管控/写保护"设置或换读卡器/直插口。
- 阻塞 2：C1.2 冻结 BIT/XSA 不在仓库。最小动作：向队友索要（附哈希前缀）。
