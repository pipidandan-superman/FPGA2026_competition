# 2026-09-10 日计划

## 当前判断

- 远端 main 领先本地 26 个提交（两个 tag：`camera-hdmi-visual-pass-20260907`、
  `udp-color-fix-pass-20260908`），队友已交付：主工程以太网回环 → 板→PC UDP
  视频流（B1/C1）→ C1.1/C1.2 质量收敛（零丢帧）→ BGR 颜色修正（V1.2 exe）。
  当前板级基线 = `udp-camera-c12-pass-20260908`（C1.2，6.3 fps 版）。
- 用户物料已备：网线、16GB SDHC TF 卡。目标两步：①复现队友基线；
  ②准备 Python 上板部署。
- 关键风险预判：C1.2 冻结三元组中 BIT/XSA 可能未入库（PS 使能 ENET0 是
  09-08 队友在 Vivado GUI 中完成的，git 内 BD 仍是 ENET0=0 版）。

## 主目标

1. 同步队友工程到 `origin/main` 最新并完成复现准备（工件审计 + 工具包）。
2. 给出 EES-331 Python（PYNQ）上板部署方案并完成物料下载/校验。

## 优先任务

1. pull + 快进合并（不触碰本地未跟踪文件）。
2. 审计冻结 BIT/ELF/XSA 在仓库与本机的存在性和哈希一致性。
3. 复现工具包：编程脚本、板会清单、ENET0 重建备选脚本。
4. PYNQ 方案文档 + 官方镜像下载/校验/解压。

## 明确非目标（本轮不做）

- 不做任何板级动作（编程/串口/UDP 验收），等 BIT/XSA 到位。
- 不修改 `2_fpga/` 任何文件（冻结边界；含本地未跟踪的
  `ethernet_bringup_checklist.md` 的移动/删除）。
- 不启动 ENET0 重建脚本（需用户明确授权）。
- 不做 PYNQ 移植的任何写卡/改镜像动作（仅下载与文档）。

## 预期交付

- `4_metrics/logs/2026-09-10_repro_prep_run01/`：REPRO_STATUS、两个 Tcl、
  板会清单。
- `1_docs/PYNQ部署方案_EES331_2026-09-10.md` + 已校验镜像
  （`0_assets/pynq/`）。
- 本日四件套日志。
