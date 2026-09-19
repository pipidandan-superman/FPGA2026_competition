# run26 B3 桥门——用户暂停点状态存档（2026-09-19 深夜）

## 0. 暂停背景

用户在 run26 执行中途叫停：**"我要修正计划"**。本日志为暂停点的完整现场存档；
恢复执行须以用户修正后的计划为准，本文件所述"下一步"仅为技术续点，不构成
重启授权。

上游状态：P1.1 合同已冻结（`1_docs/yolo_b3_dma_gemm_contract_20260919.md`，
D1-D4 全部按推荐拍板）；P1.2 = run26（桥 RTL V1.1 + G4 TB 块级门）。

## 1. 产物清单（均已落盘）

| 文件 | 状态 |
|---|---|
| `1_docs/yolo_b3_dma_gemm_contract_20260919.md` | 已冻结（D1 移除回环/D2 S2MM 直连/D3 LUT 镜像+CSR/D4 双源互斥） |
| `2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_top.v` | **V1.1 完整**：10 个流端口、桥声明块、0x54 BRGSTAT/0x58 STALLCNT（读清）、core 装载口双源复用、粘滞错误族、y 前插打包+hold+32 字 FIFO+tlast；含编译修复 1 处（`yfifo_pop` 声明先于使用，VRFC 10-3380）与自审修复 1 处（FIFO 满仓同拍弹出静默丢字：`yfifo_push = ypk_wv_r & (~yfifo_full | yfifo_pop)`） |
| `2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_b3_bridge.sv` | 已建（场景 S1-S7 + DMA BFM + y 流检查器）。**当前盘上状态**：S3 断言清理 ✅、探针收敛 ✅、S5a err_clr 修复 ✅ 已应用；**S7 恢复修复已诊断未应用**（暂停时被拒） |
| `4_metrics/logs/2026-09-19_yolo_gemm_b3_run26_bridge_contract/` | 证据目录：`sim_gemm_b3_bridge.tcl` + `build_log.txt`（第二轮完整日志）+ `build_log2.txt`（第三轮探针日志）+ xsim 工作产物 |

## 2. 三轮仿真实况

- **第 1 轮**（未留档于 build_log，被覆盖）：编译失败 `VRFC 10-3380 identifier 'yfifo_pop' used before declaration`（top.v:336）→ RTL 声明顺序修复。
- **第 2 轮**（build_log.txt）：
  - **S1 槽路径回归 PASS**（checks=128 双检：ycap 回读 + y 流字节/tlast）——B1 语义零漂移；
  - **S2 流单块 PASS**（checks=256）——DMA 流装载全链首证；
  - **S3 双组重叠 PASS**（STALLCNT 增量 = 0）——装载/计算同刻零反压证明；
  - **S4 同组重载反压 PASS，STALLCNT=62**（>0 证明反压 + 读清回 0）；
  - S5a FAIL 1 项：run_job_wait 绊线捕获 STATUS=0x138 的 bit8 ld_pend_err——**该位正是场景故意注入的冲突响应**（流窗内 WCTL 丢弃→置错，D4 合同行为正确），TB 缺一次取证后的 err_clr；
  - S7 FAIL：恢复 tile 的 tile_done 轮询超时（STATUS 恒 0）。
- **第 3 轮**（build_log2.txt，加探针）：定位 S7 根因（见 §3）；tile#8/9/10（停 sink 的 3 个 tile）全部正常流出 y、y_ovf 置位正常。

## 3. 关键发现（S7 根因，已实锤）

**soft_rst 清 bank 装载标志——组须重装载后才能再跑 job**：

- 证据链：`yolo_gemm_bank.sv:155-156` `w_loaded/x_loaded <= 2'b00`（随 `rst_i`）；
  core 封装 `rst_i = core_rst = rst | (soft_cnt != 0)`（top.v:286）；feeder 的
  `w_grp_ld_i = w_loaded_o` 是发行前置 → soft_rst 后标志为 0 → feeder 收下 job
  后永远等装载 → array 不 busy、无 tile_done、**STATUS 全 0 静默**（run_job_wait
  轮询 100000 次超时的机理）。
- S6 恢复场景走了重装载所以通过；S7 恢复场景漏了重装载 → 超时。**RTL 行为符合
  V1.0 语义（soft_rst=core 全复位，RAM 内容不清但装载元数据失效），非 RTL bug**。
- **对 B3 驱动的合同含义**：§5.3 每 tile 时序本来就含装载，不受影响；但任何
  soft_rst 恢复路径后必须重装载才能递交 job（已判明，待转录进合同或驱动文档）。

## 4. 暂停时已定稿未应用的 TB 修复（S7 恢复段）

在 `axi_write(A_CTRL, 32'h2); gapn(8);` 之后：

1. 加正控制：读 LDSTAT（0x3C，[5:4]=w_loaded、[7:6]=x_loaded）断言 soft_rst 后
   为 0（把 §3 语义钉进门）；
2. `push_expected` 之后补 `dma_load_block(64, 0, 0, 0)`（同数据重装载——Wm/Xm
   镜像未动，tile4 期望不变）再 start。

应用后预期：七场景全绿（S1-S6 已绿 + S7 闭环），随后按正典收口：README/守恒
对账复核 → 7_logs 收官日志 → git（命名文件 + add -f 申报）。

## 5. 续点纪律

- 用户修正计划优先；上述技术续点（§4）仅在其与修正后计划不冲突时执行；
- 板上动作（run29 及以后）一律用户在场；
- 未提交 git：本轮新产物（合同/V1.1 RTL/TB/证据目录）全部在主树工作区，
  按纪律走命名文件提交，不触 635 条未提交历史。

---
**[2026-09-20 收官更新]** 本日志所述暂停状态已被覆盖：V1.2 五项修复（R1-R5，含 S7 重装载修复与 R5 tlast 真缺陷三路合并）已全部落盘并 S1-S7 全绿，packer+静态 CSR 检查闭环，**run26 = PASS**。详见 ../2026-09-20/05_run26_closeout.md 与证据目录 README。日志原文保留作历史现场，不再作为当前态引用。
