# 2026-09-19 执行方案

## 分步方案（凌晨自主执行，用户睡眠中）

### 1. run06 TAILW 死锁修复（已完成）
- 根因：掩码 tile 末有效元素的 y_last 单拍脉冲在 FSM 仍处 S_TAIL 时打完，
  TAILW 晚入 → 电平等待错过 → 死锁。定位证据：run06/dbg 最小复现追踪。
- 修复：FSM 自计 y 拍 `ycnt`（任意态递增、首块接受清零），
  TAILW 离开判据 `ycnt >= n_valid_cnt`。V1.1。
- 验证：三档复跑全 PASS（846/4250/6881，0 err）。

### 2. run07 OOC 综合评估
- 脚本：`4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run07_syntheval/syn_gemm_ooc.tcl`
  （非工程模式 synth_design -mode out_of_context，-generic 三配置）
- 配置 A：P_TO=16 P_TN=16 P_KMAX=2304 @ 10.000 ns（真配置，含功能缓冲代价）
- 配置 B：P_KMAX=64 @ 10.000 ns（核视图：MAC 网格+尾+FSM 本征时序）
- 配置 C：P_KMAX=2304 @ 6.667 ns（余量探针）
- 判读：A 的 LUT/LUTRAM 增量 = G2 真 bank 的必要性数据；
  B 的 WNS = 核心数据通路时序健康度；DSP 数预期 128（cell）+ 尾乘法。

### 3. GEMM 板测计划文档（1_docs/yolo_gemm_board_test_plan_20260919.md）
- 如实陈述：③④ 仿真门已过；上板还差 G2（bank）与 G4（DMA/CSR 接入），
  明早晨验的内容 = 综合证据评审 + 板测计划评审 + G2 开工决策。

### 4. git 上传（用户分支 codex/full/pipidandan-superman）
- worktree：`E:/competition_worktrees/FPGA2026_competition/pipidandan-superman`
- 命名文件复制（rtl/GEMM 全部、两手册+图集+量化审查、run01-07 证据
  README+tcl+控制台、7_logs/2026-09-19、板测计划）→ add 命名路径 →
  commit → push origin codex/full/pipidandan-superman。
- 4_metrics 大文件（xsim.dir/*.pb/vivado*.backup）不传，只传
  README/tcl/console/*.rpt 类小文件（沿用 ae8da88 "显式选择,非批量" 先例）。

### 5. 记忆与交接
- 更新 memory/pe-gemm-oracle-state.md → 阵列门收官状态；
  MEMORY.md 索引行同步。

## 模块/职责划分

- RTL（只读，已冻结于仿真门）：rtl/GEMM/ 五文件 + tb 五文件
- 证据：4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run01..07
- 文档：1_docs/ 三份手册 + 图集 + 板测计划

## 风险点及失败回退

- 综合若 LUTRAM 爆炸/超时：A 失败不阻塞 B/C；证据照存，结论改写为
  "G2 前综合不可行"同样有效。
- git push 若 SSH 失败：本地 commit 保留，晨报说明，用户在场时重推。
- -generic 选项若不被 2025.2 接受：改薄包装顶层文件再跑。
