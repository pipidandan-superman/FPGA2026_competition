# GitHub 个人分支上传结果（UDP 色差修复 + 固化）

- 日期：2026-09-08
- 分支：`codex/full/pipidandan-superman`（`fc76580..75ac99a`）
- 远端：`github.com:pipidandan-superman/FPGA2026_competition.git`
- tag：`udp-color-fix-pass-20260908`（指向 75ac99a，已推送）
- 方式：干净 worktree（`E:\competition_worktrees\FPGA2026_competition\pipidandan-superman`）显式选文件，未使用 `git add .`；未触碰 `main`，未触碰 `2_fpga` 冻结基线。

## 提交清单

| 提交 | 内容 |
|---|---|
| `58caa58` fix: decode UDP camera frames as BGR (VDMA little-endian byte order) | `3_host/udp_video/udp_video_gui.py`（V1.2）、`udp_video_rx.py`（V1.1）、`dist/EES331_UDP_Viewer.exe`（31,187,867 B，SHA-256 `a4b75ed3...`，大二进制按规则 8 声明：本竞赛板会实际使用的接收工具，需随分支自包含）、设计文档 v1.1 §10 字节序勘误 |
| `75ac99a` evidence: archive UDP color-swap root cause, fix verification and final board visual pass | `4_metrics/logs/2026-09-08_udp_color_swap_fix_run01/`（RUN_REPORT、两个验证脚本、verify_console.log、pyinstaller_rebuild.log（两者经 .gitignore 显式白名单）、用户确认截图、19.5 MB 最终板级录屏（规则 8 声明）、哈希清单）+ `7_logs/2026-09-08/` 四件套 + `.gitignore` 白名单两行 |

## 验证与边界声明（供 PR 复用）

- 已验证：根因证据闭环（寄存器无责/VDMA 小端打包/上位机解码假设错误）；localhost 端到端注入测试 `ALL_COLOR_SWAP_FIX_TESTS_PASS`；重建 exe 板级实时流目视 PASS（用户录屏：192.168.240.10，6.25 fps，色彩自然，丢帧/CRC ≈1% 与 C1.2 基线一致）。
- 未验证/边界：目视验收，无定量色彩测量；完整串口归档仍欠；HDMI 链路本次零改动（其 PASS 状态沿用 2026-09-07 冻结）。
- 冻结工件：`2_fpga` 的 BIT/XSA/ELF 与 OV5640 寄存器表零改动；板端配对仍为 C1.2（`udp-camera-c12-pass-20260908`）。
- 回滚方法：分支回退到 `fc76580`（或重新运行旧版 exe），板端无需任何动作。

## PR

gh CLI 不可用，PR 由用户在网页创建：
`https://github.com/pipidandan-superman/FPGA2026_competition/compare/main...codex/full/pipidandan-superman`
建议标题：`fix: UDP camera frame BGR decode (color swap) + freeze evidence`
评审人：member-b（xiaokaiyuan）。
