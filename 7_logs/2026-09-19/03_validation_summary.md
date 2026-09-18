# 2026-09-19 验证摘要

## 开始前已验证的事实（承前，证据在案）

- G0/①②/MAC/③a 五门全 PASS（run01-run05，checks 169025 等）。
- CSR 板级 L1-L4 闭环，板上 186154c5 基线。

## 今日完成

### 1. run06 阵列门复跑（V1.1 修复后）——PASS ×3 ✅

| 档位 | checks | errors | tiles started/done/aborted | blocks_fed/blk_done |
|---|---|---|---|---|
| 4×4 | 846 | 0 | 62/60/2 | 72/12 |
| 8×16 | 4250 | 0 | 37/35/2 | 47/12 |
| 16×16 | 6881 | 0 | 30/28/2 | 40/12 |

控制台：`4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run06_array/arr_console.log`
（`EES_VIVADO_RESULT PASS` ×3；守恒与 blk_done 计数吻合）。
修复前 FAIL 证据 + dbg/ 最小复现 FSM 追踪同目录保留。

### 2. run07 OOC 综合评估——部分完成（G2 证据已封闭）⚠ 如实

- 配置 A（2304@100MHz）：**中止于 RTL Optimization Phase 2 后段**——宿主
  内存临界（Vivado 峰值 15,155 MB），后台任务被系统回收、孤儿进程已终止；
  util/timing 报告未生成。**G2 立项证据已足**：`W_buf_reg/X_buf_reg with
  294912 registers` 各一（异步读 reg 阵列无法推断 RAM）→ 590k FF >
  器件 106.4k，物理不可容纳；综合器本身 15GB 内存无法完成 = 工具链层面
  亦不可行。**A 无需重跑（结论已封闭）。**
- 配置 B（K64 核视图）：未运行——留晨间第一动作（用户在场时数分钟），
  取 MAC 网格+尾+FSM 本征资源/时序底线（G2 后对比用）。
- 配置 C（150MHz 探针）：未运行（可选）。
- 控制台（含终止记录）：`4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run07_syntheval/syn_console.log`

## 判定标准（事先声明）

- 三档仿真 PASS 标准：errors=0 且守恒 started−aborted==done 且
  blk_done_seen==exp_blk_done —— 已达成。
- 综合评估标准修订（终态）：A 的目的 = G2 证据（已达成：294912×2 寄存器
  警告 + 15GB 内存实测 + 590k>106.4k 算术结论）；B/C 的 WNS/DSP 底线
  数据留晨间补跑后再判。
- 板测（明日晨）：见板测计划文档；本日无板上操作。

## 未验证/留待后续

- G2 真 bank 机构（本综合 A 配置的 590k FF/294912×2 寄存器证据即其立项依据）
- G4 DMA/CSR 接入与系统级时序（PS 100 MHz 域）
- 板级功能（等 G2/G4 完成后整体上板）
