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
  B/C 留晨间）证据在 `4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run07_syntheval/`。

## 下一步最应优先执行的动作（按手册门控顺序）

0. （晨间，用户在场，可选）补跑 run07 配置 B 取核视图底线：
   `cd 4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run07_syntheval && vivado.bat -mode batch -source syn_gemm_ooc.tcl`（A/C 两行临时注释；A 结论已封闭勿重跑）；
   ——注意：昨夜 A 因宿主内存耗尽被终止，勿无人值守重跑 A/C。
1. **G2：W/X 真 bank（ping-pong）机构**——用 run07 配置 A 的证据立项
（294912×2 寄存器 / 590k FF > 106.4k 器件 / 15GB 内存不可完成）；替换 rtl/GEMM/yolo_gemm_array.sv 中的 ③ 档功能缓冲（W_buf/X_buf），
cell/tail/FSM 契约不动；TB 复用 tb_yolo_gemm_array（加载时序改 bank 装载）。
之后 G4（DMA/CSR 接入）→ G7（系统综合+上板）。

## 刚开始时不要做的事情

- 不要重构已过门的 cell/tail/FSM RTL（③④ 已冻结）；
- 不要绕过 G2 直接把功能缓冲版阵列上板；
- 不要动冻结 2_fpga 工程、CSR 已验证 RTL、板上 186154c5 基线；
- 不要推 main；git 只走命名文件。

## 成功标准（下一会话）

- G2 bank RTL + TB 门仿真 PASS（复用 run06 阶段矩阵）；
- 综合对比：bank 版 LUTRAM 显著下降、时序不劣化；
- 证据齐套（run 目录四件：tcl/console/README + 报告）。

## 阻塞

无。（若晨间板验发现综合证据问题，先修证据链再开 G2。）
