# 09 号工作日志 — run10a：P1.3 三体合并门（2026-09-19 白班）

## 任务

P1.3（批准计划）：bank + feeder + array 三体字口对接，TB 块粒度装载时序，
复跑 run06 全矩阵，检查数严格对齐。档位 4×4 + 8×16（16×16 无 64b 写口
通路，覆盖冻结于 run08——计划已知）。

## 过程（编年）

1. 设计决策（开工前定稿）：TB 只做块粒度调度（装块→递交→等收口），
   组交替 b%2，顺序调度保 TDP 无冲突；checker/tile 清单/随机流逐字
   承袭 run08（数据逐字相同 ⇒ y 对拍即跨供数实现对照）；G5 抖动退役
   （feeder 为生产者）、G6 改 job 后定时杀；P_KC=1152（矩阵最深块，
   功能门参数，不影响 P1.4 综合定档）。
2. 写 `tb_yolo_gemm_merge.sv` V1.0 + 薄包装两档 + `sim_gemm_merge.tcl`
   （unisim+glbl 模式，DSP48E1 依赖）。
3. 自查修三处（全 TB 侧，未流出为错）：
   - `wire bank_err` 前置声明（10-3380）；
   - ld_done 采样改末拍 wr_beat 返回点同拍直读（脉冲窗正中，无沿竞态；
     中途一度想改 negedge 等待——对照 bank RTL 发现会落到脉冲窗外，
     属"想当然修正引入 bug"，靠读源码拦下）；
   - **G6 随机流奇偶**：run08 击杀前抽 `i=20+rand(rs1)%40`，固定拍数
     会少抽 2 次 rs1 → G7 起数据漂移。逐字照抄修复。
4. **一跑双档 PASS（零迭代）**：846/4250 checks，errors=0，proto_err=0，
   守恒精确，ld_done==blocks+2。

## 结论与沉淀

- P1.3 判据达成：全矩阵 PASS 且与 run06/run08 逐数对齐
  （846/4250；62/60/2 与 37/35/2；72/12 与 47/12）。
- 跨实现对照成立：同随机流同数据，TB 直驱（run08）与 bank+feeder
  真机构（本轮）输出零差异——G2 数据通路三层（bank/feeder/array）
  与既有阵列级 golden 的等价性就此闭合。
- 沉淀：TB 奇偶对齐是"逐字复用随机流"的隐藏契约——激励机制的任何
  改动（哪怕只是击杀拍数固定化）都要先问"少抽了哪颗种子"。

## 证据

- 控制台：`../../4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run10a_merge/`
  （merge_console.log 一跑直接 PASS ×2；README 含全表与 TB 结构）
- RTL 零改动（bank V1.1 / feeder V1.0 / array V2.0 均为已过门版）；
  TB 新增 `tb/tb_yolo_gemm_merge.sv`

## 下一步

P1.4（run10b）：OOC 综合 8×16，Kc=576 与 Kc=1024 两配置；判据
BRAM36≈12、无 FF 爆炸、100MHz WNS≥0 绝对值 → Kc 定档（计划决策点）。
