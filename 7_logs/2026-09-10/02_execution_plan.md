# 2026-09-10 执行计划

## 执行顺序

1. **同步**：`git fetch` → 确认本地未跟踪文件与 incoming 无冲突 →
   `merge --ff-only origin/main`（结果：23a874e → c60291a）。
2. **工件审计**：
   - 读 `c12_final_artifacts_sha256.txt` / `c12_freeze_artifacts_sha256.txt` /
     `board_artifacts_sha256.txt` 与 09-07 FROZEN_ARTIFACT_MANIFEST；
   - `git ls-files` 全仓追踪 `.bit/.xsa/.elf`；
   - 本机 `sha256sum` 比对（BIT/XSA/ELF/exe 四处）。
3. **工具链确认**：解析开始菜单快捷方式 → 实际安装根
   `E:/WorkApps/Xilinx/Vivado_2025_2/2025.2/`（Vivado+Vitis 2025.2、bootgen；
   XSCT 已不存在）。
4. **工具包产出**：写 REPRO_STATUS / prog_frozen_bit.tcl /
   enable_enet0_export_xsa.tcl / BOARD_ACCEPTANCE_CHECKLIST 到
   `4_metrics/logs/2026-09-10_repro_prep_run01/`。
5. **PYNQ 准备**：确认官方直链（download.amd.com/opendownload/pynq/
   pynq_z2_v3.1.1.zip）→ 后台下载 → 校验 → 解压 → 解析镜像分区表与
   FAT 引导目录 → 写部署方案 `1_docs/PYNQ部署方案_EES331_2026-09-10.md`。
6. **日志**：本四件套。

## 涉及模块/工具

- git、sha256sum、curl、unzip、python（MBR/FAT 解析）
- Vivado/Vitis 2025.2（仅确认安装，本轮未运行）
- 仓库资产：`2_fpga/0_diaplay_test/`（读）、`3_host/udp_video/dist/`（校验）、
  `4_metrics/logs/2026-09-08_mainproj_eth_loopback_integrate_run01/`（读）

## 风险与对策

| 风险 | 对策 |
|---|---|
| BIT/XSA 不在仓库 | 已确认为事实；主路径=队友补传+哈希校验；备选=授权后 Tcl 重建（ENET0 使能清单见脚本注释） |
| 快捷方式路径失效 | 直接解析 .lnk → 发现指向 `E:/WorkApps/...` 旧布局 → 用目录枚举定位真实安装根 |
| 镜像下载中断 | curl `-C -` 断点续传；Content-Length 比对 + zip 内文件大小核对 |
| 误写冻结区 | 全部产物写入 run 目录 / 1_docs / 7_logs / 0_assets（gitignored） |

## 回退

- 若队友无法短期补传 BIT/XSA → 用户可授权运行
  `enable_enet0_export_xsa.tcl`（产新哈希，按新验证 run 处理）。
- 若 PYNQ v3.1.1 移植受阻 → 方案文档已预留 v2.7 镜像回退路线。
