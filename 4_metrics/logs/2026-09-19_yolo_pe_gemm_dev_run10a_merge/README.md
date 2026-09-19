# run10a — P1.3【V4】bank+feeder+array 三体合并门（2026-09-19 白班）

## 结论：PASS ×2（首跑零迭代）

| 档位 | checks | errors | proto_err | tiles S/D/A | blocks/blk_done | ld_done | 守恒 |
|---|---|---|---|---|---|---|---|
| 4×4  (P_KC=1152) | **846**  | 0 | 0 | 62/60/2 | 72/12 | 74 | started−aborted==done ✓ |
| 8×16 (P_KC=1152) | **4250** | 0 | 0 | 37/35/2 | 47/12 | 49 | ✓ |

**与 run06/run08 逐数严格对齐**（846/4250；tiles 62/60/2 与 37/35/2；
blocks 72/12 与 47/12）——计划判据"复跑 run06 全矩阵 + 检查数严格对齐"达成。
且随机流与 run08 逐字一致 ⇒ 数据逐字相同 ⇒ 本次 y 对拍同时是
**跨供数实现**（TB 直驱宽字 vs bank+feeder 真机构）的对照实验，双实现零差异。

## 被测对象（三体真线，全为已过门 RTL，本轮零 RTL 改动）

- `rtl/GEMM/yolo_gemm_bank.sv` V1.1（run09 修复版：w_wa 首拍写址旁路）
- `rtl/GEMM/yolo_gemm_feeder.sv` V1.0（唯一 k 计数、组 MUX、rd_busy 硬门控）
- `rtl/GEMM/yolo_gemm_array.sv` V2.0（run08 冻结宽字纯消费者）
- TB：`rtl/GEMM/tb/tb_yolo_gemm_merge.sv` V1.0（薄包装 4×4/8×16，P_KC=1152）

## TB 结构（相对 run08 的变化，其余逐字保留）

1. **TB 只做块粒度调度**：`bank_load(len,k0,grp)` 把 Wm/Xm 镜像切片经 64b
   流式写口装 bank（W 整拍 / X lo+hi 两拍，wr_first 于 k=0 W 拍、wr_last 于
   末拍 X-hi 拍）；`job_feed` 递交 feeder 作业；`wait_done` 等 blk_done/tile_done。
   feeder↔bank、feeder↔阵列全部真线，TB 不接触字流。
2. **组交替 g=b%2**（W/X 同组）；顺序调度（装 b → 递 b → 等收口 → 装 b+1），
   TB 不制造 TDP 冲突访问（真实重叠覆盖已在 run09 R2/R8）。
3. **16×16 不跑**：W 字 128b 无 64b 写口通路（G2 基线 8×16；16×16 阵列级
   等价覆盖由 run08 冻结 6881 checks）——计划已知且接受。
4. **G5 生产者抖动退役**（tile 保留维持矩阵对齐）：合并系统生产者是
   feeder，无 valid 抖动源；消费侧停拍覆盖在 run09 R4。
5. **G6 击杀改 job 递交后定时杀**：整块 1000 字装 g0 → 手动递交
   （不计 blocks_fed，同 run08 语义）→ `i=20+rand(40)` 拍后 rst 杀 2 拍
   → 在飞期望作废 → gapn(6) 残影窗 → run_tile(27)。
6. **新增仪器**：bank_err 上升沿计错；ld_done_seen 守恒
   （== blocks_fed+2，两 G6 手动装载）。

## TB 侧三个纪律点（本轮自查发现，未流出为错）

- **随机流奇偶**：run08 G6 每次击杀前抽 `i=20+{$random(rs1)}%40` 一次——
  固定拍数会少抽 2 次 rs1 使 G7 起数据漂移、破坏"数据逐字相同"对照声明。
  修复：逐字照抄该抽取并用作击杀时刻。rs5 仅抖动使用，退役无影响。
- **ld_done 采样**：脉冲在 wr_last 接收拍 NBA 置 1、次拍清零；末拍
  wr_beat 返回点恰为脉冲窗正中，同拍直读（无沿竞态）。`@(posedge)`
  读旧值虽可行但依赖活动区时序，不取。
- **`wire bank_err` 前置声明**（10-3380：引用先于声明的 wire 报错）。

## 证据

- 控制台（本次唯一一跑，直接 PASS）：`merge_console.log`
  （`EES_VIVADO_RESULT PASS` ×2；4×4 $finish@1,061,130ns、
  8×16 $finish@925,550ns；xsim 峰值内存 ~23MB）
- tcl：`sim_gemm_merge.tcl`（xvlog pack + 8×sv + glbl；xelab
  `-L unisims_ver -L unisim` ×2；xsim ×2；DSP48E1 需 unisim+glbl）

## 对计划的回填

- P1.3 行（"字口对接，TB 块粒度装载时序，复跑 run06 全矩阵 | run10a |
  全矩阵 PASS"）：**完成**（4×4+8×16 两档；16×16 按 G2 架构不适用，
  覆盖冻结于 run08）。
- 下一步 P1.4（run10b）：OOC 综合 8×16 @ Kc=576 / Kc=1024 两配置，
  判据 BRAM36≈12、无 FF 爆炸、100MHz WNS≥0 绝对值 → Kc 定档。
