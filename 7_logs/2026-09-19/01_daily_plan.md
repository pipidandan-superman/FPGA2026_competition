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

## 白班追加（用户在场：G2 收敛 + 计划批准 + P1 开工）

1. ✅ G2 架构收敛研讨（8×16 基线/W 64b/X 128b/Kc=576|1024/双组 TDP/
   写侧排布/feeder 出口级/广播式+时序风险定档）→ 板测计划 §2；
2. ✅ P1-P3 执行计划制定并批准，**P0 四项全部取消**（B 底线对比作废，
   时序改绝对值判；今日文档 git 提交并入 P1.5）；
3. ✅ P1.1 run08 阵列宽字口改造单验 PASS ×3（846/4250/6881 与 run06
   逐数对齐，proto_err=0，V2.0 宽字契约冻结）；三跑两轮 TB 侧 FAIL
   修复（k0 块基址移交/G6 循环纪律）——README + 07 号日志在案；
4. ✅ P1.2 run09 bank+feeder 一体门 **PASS ×3**（v3：4×4 KC8=150 /
   8×16 KC64=271 / 8×16 KC576=1295 checks，errors=0，守恒精确，
   off-by-one 专项零错；v2 三个根因修毕：bank W 首拍写址 NBA 竞态 /
   TB 单元层越界 / ld_done 采样点；rd_busy 硬门控设计强化入案）；
5. ✅ P1.3 run10a 三体合并门 **PASS ×2（一跑零迭代）**：4×4=846 / 8×16=4250
   checks，errors=0，proto_err=0，与 run06/run08 **逐数严格对齐**
   （62/60/2 与 37/35/2；72/12 与 47/12）；随机流逐字承袭 ⇒ 同数据
   跨供数实现对照零差异；TB 三处自查（bank_err 前置声明 / ld_done
   窗中采样 / G6 rs1 抽取奇偶）——README + 09 号日志在案；
6. ▶ P1.4 run10b：OOC 综合 8×16 @ Kc=576/1024 双配置（BRAM36≈12、
   无 FF 爆炸、100MHz WNS≥0 绝对值）→ Kc 定档；
7. 白班不做：冻结工程/CSR RTL 不动；板上动作用户在场；综合仅 G2 规模。
