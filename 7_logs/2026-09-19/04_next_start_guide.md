# 2026-09-19 下次启动指南

## 第一步（会话开始时）

1. 读本目录 `03_validation_summary.md`（阵列门 PASS + run07 综合结果）；
2. 读 [GEMM 板测计划](../../1_docs/yolo_gemm_board_test_plan_20260919.md)
   与 [GEMM 设计手册](../../1_docs/yolo_gemm_design_manual_20260918.md)；
3. 核对 git 分支状态（用户分支 codex/full/pipidandan-superman 是否已推）。

## 主线状态（勿重做）

- **③④ 阵列门三档 PASS（run06 V1.1）**：4×4/8×16/16×16 共 11977 checks
  0 errors。TAILW 死锁修复细节见 run06 README（y 拍计数判定）。
- **GEMM 上板准备（run07）**：16×16 OOC 综合评估（A 中止但 G2 证据已封闭，
  B/C 已随 P0 取消）证据在 `4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run07_syntheval/`。
- **P1.1 run08 阵列宽字口 V2.0 PASS ×3（2026-09-19 白班）**：与 run06 逐数
  对齐（846/4250/6881，proto_err=0），宽字纯消费者契约冻结。证据
  `4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run08_array_v2/`（含两轮 TB
  侧 FAIL 档案：k0 块基址移交、G6 循环纪律）。
- **P1.2 run09 bank+feeder 一体门 PASS ×3（2026-09-19 白班）**：
  4×4 KC8 / 8×16 KC64 / 8×16 KC576 = 150/271/1295 checks，errors=0，
  守恒精确，off-by-one 零错。bank V1.1（w_wa 首拍写址旁路）+ feeder V1.0
  （唯一 k 计数、rd_busy 硬门控、无 k0——块基址活在装载顺序）。证据
  `4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run09_bank_feeder/`。
- **P1.3 run10a 三体合并门 PASS ×2（2026-09-19 白班，一跑零迭代）**：
  4×4=846 / 8×16=4250 checks，errors=0，proto_err=0，与 run06/run08
  **逐数严格对齐**（tiles 62/60/2 与 37/35/2；blocks 72/12 与 47/12；
  ld_done 守恒 74/49）。随机流逐字承袭 ⇒ 同数据跨供数实现对照零差异。
  RTL 零改动；16×16 无 64b 写口通路不跑（覆盖冻结 run08）。证据
  `4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run10a_merge/`。

## 下一步最应优先执行的动作（按手册门控顺序）

0. ~~run07 配置 B 补跑~~（2026-09-19 用户定：**P0 全部取消**，不执行；
   G2 综合按时序绝对值判 WNS≥0）。
1. **P1.4（run10b）OOC 综合 8×16**：Kc=576 与 Kc=1024 两配置各一跑，
   判据 BRAM36≈12、无 FF 爆炸、100MHz WNS≥0 绝对值、无新关键告警
   → **Kc 定档（计划决策点）**。随后 P1.5 收口（日志+README+memory+
   git：G2 结果与 09-19 文档至用户分支 codex/full/pipidandan-superman，
   命名文件，绝不推 main）→ P2（P2.1 DMA 选型决策文档需用户评审）。
   完整计划 `1_docs/yolo_gemm_g2g4g7_execution_plan_20260919.md`
   ——**已批准（2026-09-19，P0 取消），按 P1→P3 依次执行**（仿真/综合
   自主连续，板上动作用户在场）。

## 刚开始时不要做的事情

- 不要重构已过门的 cell/tail/FSM RTL（③④ 已冻结）；
- 不要绕过 G2 直接把功能缓冲版阵列上板；
- 不要动冻结 2_fpga 工程、CSR 已验证 RTL、板上 186154c5 基线；
- 不要推 main；git 只走命名文件。

## 成功标准（下一会话）

- P1.3 已达成（846/4250 双档 PASS 且逐数对齐，2026-09-19 白班收口）；
- P1.4 OOC 综合双配置（Kc=576/1024）出资源+时序报告，BRAM≈12、
  100MHz WNS≥0，Kc 定档有据；
- 证据齐套（run 目录四件：tcl/console/README + 报告）。

## 阻塞

无。（若晨间板验发现综合证据问题，先修证据链再开 G2。）

---

# 第二班次增量（IP 重做链 run11–run16 收官后）

## 下次开始时优先阅读

1. `4_metrics/logs/2026-09-19_yolo_gemm_ip_run16_ooc_syn_bmg/README.md`
   （时序决策点 A/B/C 及依据——**唯一挂起决策**）
2. `4_metrics/logs/2026-09-19_yolo_gemm_ip_run15_core_bmg/README.md`
   （core V1.1 单体门 = 上板例化单元的功能证据）

## 第一步要执行的操作

等用户对 run16 WNS=−4.728 的决策（A 加深+收窄 / B 算术收窄 /
C 降频）。决策前尾 RTL 冻结；B1 上板准备（yolo_gemm_top.v 纯
Verilog 顶层 + 块级 CSR 仿真门）不受阻塞，可按用户节奏先行。

## 刚开始时不要做的事

- 不要擅自改尾流水/算术（决策点未决）
- 不要动 run11-15 已冻结 TB/README（历史证据）
- 板上动作需用户在场

## 成功标准（下一班次）

- 决策落定并闭环（若改 RTL：run13/14/15 相关门重跑全绿 + run16 重综
  WNS≥0 或降频方案获认）；或 B1 顶层件 + 块级门先行绿。

## 阻塞

仅决策点挂起（用户）；无技术阻塞。

## 第三班次增量（WNS A+B 闭环后）

1. **B1 准备（已授权，第一动作）**：`yolo_gemm_top.v` 纯 Verilog-2001
   BD 顶层（挂 axi_csr、CSR 搬数、小 KC 金向量）+ 块级 CSR 驱动仿真门。
   例化基线 = core V1.1（tail V2.2 D+5 / array V2.2 / bank V2.0.1）。
   注意：.v 顶层例化 .sv 子模块的 BD 兼容性需在 Vivado 里实证一次。
2. git：run17-20 + RTL V2.2 变更具名提交用户分支（随 B1 或立即）。
3. 已闭环勿重做：run11-16（IP 重做链）+ run17-20（A+B 收敛链）。
