# 2026-09-19 凌晨自主批工作日志：PE/GEMM 阵列门收官 + 上板准备

（用户睡前指令：完成 GEMM 上板准备；更新日志/handoff/readme/progress；
关键成果上传个人分支——overlay skill、AXI 寄存器设计、本次 GEMM。）

## 1. run06 TAILW 死锁修复 → 三档 PASS

- 现象：首跑（`arr_console_prefail_v1.log`）三档值检查全对但首个掩码 tile
  后级联超时；dbg 最小复现（4×4 K=27 行掩码 0111，`dbg/dbg_console.log`
  FSM 逐拍追踪）钉死：末有效元素 y_last 单拍脉冲 c=420 呈现时 FSM 仍在
  S_TAIL（ti=14 跳无效槽），TAILW c=423 才进入，电平等待必然错过。
- 修复（`yolo_gemm_array.sv` V1.1）：`ycnt` 计已呈现 y 拍（任意态递增、
  首块接受清零），`S_TAILW: if (ycnt >= n_valid_cnt)`。对拍序不敏感：
  掩码 tile 进 TAILW 时已达标首拍即走，全有效 tile 在 TAILW 等满。
- 复跑：4×4=846 / 8×16=4250 / 16×16=6881 checks，errors=0，守恒与
  blk_done 三档吻合（`arr_console.log`，PASS ×3）。
- 顺带修：`tail_y_valid` 声明提前（always 块内引用后置声明 wire 也犯
  VRFC 10-3380）；临时 `tb_dbg_arr.sv` 删除（dbg 证据留 run06）。

## 2. run07 OOC 综合评估（16×16）

- 脚本 `syn_gemm_ooc.tcl`：非工程 synth_design -mode out_of_context，
  -generic 三配置 A(2304@10ns)/B(K64@10ns)/C(2304@6.667ns)。
- 已见关键证据（config A 综合 WARNING）：
  `W_buf_reg with 294912 registers` / `X_buf_reg with 294912 registers`
  ——③ 档功能缓冲异步读无法推断 RAM，映射纯 FF+巨多路器，590k FF 超
  XC7Z020 的 106.4k → **物理不可上板，G2 真 bank 唯一路径**。
- **终态（如实）**：配置 A 中止于 RTL Optimization Phase 2 后段——宿主
  内存临界（Vivado 峰值 15,155 MB），后台任务被会话系统回收，孤儿
  vivado.exe(PID 47720) 手动终止以防整夜内存耗尽；按纪律不自行重启。
  B/C 未运行，B 留晨间（用户在场数分钟）。**A 的目的（G2 证据）已达成**：
  294912×2 寄存器警告 + 590k FF > 106.4k 算术结论 + 15GB 工具链不可行
  实测——A 无需重跑。终止记录已追加进 syn_console.log。

## 3. 板测计划

`1_docs/yolo_gemm_board_test_plan_20260919.md`：晨验清单 = ①基线回归
（186154c5，可选 ~10min）②run06/run07 证据评审 ③G2 开工决策；
G2/G4 缺口如实标注；本批零板上操作、零新生成比特流。

## 4. 日志/交接更新

- 7_logs/2026-09-19 四件套 + 本日志；
- progress.md：更新行 + 一句话现状 + H14（CSR 线补录）+ H15（PE/GEMM 线）
  + 硬件边界段刷新；
- HANDOFF.md 顶部新条目；README.md 新动态段；
- 记忆 pe-gemm-oracle-state.md 重写为收官态 + MEMORY.md 索引行同步；
- run05/run06 README 补记（含全部调试记录与教训）。

## 5. git 上传（用户分支）

- 分支核实：`codex/full/pipidandan-superman` @
  `E:/competition_worktrees/FPGA2026_competition/pipidandan-superman`；
  overlay skill 与 CSR/AXI 寄存器设计**已在分支**（f542dc3/5007593/
  ae8da88/c7080d4，diff 核实无差异）——无需重传。
- 本批增量：rtl/GEMM 全目录（diff -r 核实 identical）、1_docs×5、
  run01-06+manual/figures/quant-audit 证据小文件（显式清单，
  排除 xsim.dir/*.pb/backup/*.jou/工具内部日志）、7_logs/2026-09-19、
  progress/README/HANDOFF、run07（综合完成后补）。
- 提交与推送：命名路径 add → commit → push origin（main 不动）。

## 6. 教训沉淀（本批新增）

1. **跨模块单拍脉冲不得作 FSM 电平等待条件**（除非证明脉冲必在等待窗内）；
   计数/粘滞判定才是结构安全写法。
2. xsim 的 use-before-declaration 检查覆盖 always 块内 wire 引用——
   声明必须物理先于所有引用点。
3. 异步读 reg 阵列在综合器视角 = 纯寄存器堆：功能占位缓冲必须在
   手册里显式标注"非综合目标"（本线已如此），综合证据要按此解读。
