# 2026-09-19 每日计划

## 当前项目状态判断（已核实事实，标注证据）

1. **PE/GEMM 仿真门全链收官（本日凌晨，无需重做）**：
   G0 oracle → ① PE → ② 双累加器 → level-2 MAC → ③a 共享尾（run05，
   713 checks / 0 err）→ **③b/④ 阵列三档 PASS（run06 V1.1 复跑）**：
   4×4=846 / 8×16=4250 / 16×16=6881 checks，errors=0，守恒与 blk_done
   计数三档全吻合。TAILW 死锁已修（y 拍计数判定），修复前 FAIL 证据与
   最小复现 FSM 追踪保留在 run06。
   证据 [run06](../../4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run06_array/)。
2. **CSR 板级线已闭环（勿动）**：板上挂 186154c5 版 overlay 可作叠加基线。
3. **git 分支定位已核实**：用户分支 = `codex/full/pipidandan-superman`，检出
   于 `E:/competition_worktrees/FPGA2026_competition/pipidandan-superman`，
   CSR RTL/文档/证据/overlay skill 均已在分支上（5007593..c7080d4）；
   尚缺 PE/GEMM 线（RTL+手册+run01-06 证据+日志）。

## 今日主要目标（用户睡前指令：上板准备 + 日志 + git 上传）

1. ✅ run06 TAILW 修复与三档复跑 PASS
2. run07：16×16 阵列 OOC 综合评估（真配置@100MHz / 核视图K64@100MHz /
   真配置@150MHz），产出资源+时序证据 + G2 必要性数据
3. GEMM 板测计划文档（明早晨板验的入口文档，G2/G4 缺口如实标注）
4. git 上传 PE/GEMM 线到用户分支（命名文件，绝不推 main）
5. 更新 handoff/readme/progress 与记忆

## 按优先级排列的任务清单

- [P0] run07 OOC 综合三配置 + README
- [P0] 板测计划文档（1_docs/）
- [P1] git：复制命名文件至 worktree → commit → push 用户分支
- [P1] 7_logs/2026-09-19 四件套 + 记忆更新
- [P2] run05/run06 README（已完成于凌晨补记）

## 今日明确不做的事项

- 不做 G2 W/X 真 bank / ping-pong 机构（手册门控，下一会话起点）
- 不做 G4 DMA/CSR 阵列接入
- 不动冻结 2_fpga 工程；不推 main；不动 CSR 已验证 RTL
- 不在无用户在场时做任何板上物理操作

## 预期交付物

- run07 综合证据目录（util/timing 报告 ×3 + 控制台 + README）
- 板测计划文档 + 四件套 + git 分支新提交
