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
- 配置 B（K64 核视图）：**已取消**——2026-09-19 用户定 P0 全部取消，
  G2 综合门改按 100MHz WNS≥0 绝对值判，无 B 底线对比。
- 配置 C（150MHz 探针）：已取消（同上）。
- 控制台（含终止记录）：`4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run07_syntheval/syn_console.log`

### 3. 白班：G2 架构收敛 + 执行计划批准 + P1 开工 ✅

- G2 全部口径收敛入档板测计划 §2（8×16/W64b/X128b/Kc/双组 TDP/
  feeder/广播式+时序风险定档），日志见 `06_g2_design_convergence.md`；
- 执行计划 `1_docs/yolo_gemm_g2g4g7_execution_plan_20260919.md` 批准，
  **P0 四项取消**，自 P1 起执行；
- **P1.1 run08 阵列宽字口改造单验——PASS ×3（三跑收口，V2.0 契约冻结）✅**
  与 run06 逐数对齐（同随机流同 tile 清单）：

  | 档位 | checks | errors | proto_err | started/done/aborted | blocks/blk_done | y |
  |---|---|---|---|---|---|---|
  | 4×4 | 846 | 0 | 0 | 62/60/2 | 72/12 | 846 |
  | 8×16 | 4250 | 0 | 0 | 37/35/2 | 47/12 | 4250 |
  | 16×16 | 6881 | 0 | 0 | 30/28/2 | 40/12 | 6881 |

  控制台：`4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run08_array_v2/arr_console_v3.log`。
  前两跑 FAIL 均 TB 侧（块基址 k0 未随契约移交 / G6 循环变量与上限
  $random 漂移随机流），DUT proto_err 全程=0——详见 run08 README。

### 4. P1.2 run09 bank+feeder 一体门——PASS ×3（v3）✅

| 档位 | checks | errors | jobs | words | ld_done |
|---|---|---|---|---|---|
| 4×4 KC=8 | 150 | 0 | 25 | 150 | 27 |
| 8×16 KC=64 | 271 | 0 | 25 | 271 | 27 |
| 8×16 KC=576 | 1295 | 0 | 25 | 1295 | 27 |

控制台：`4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run09_bank_feeder/bf_console_v3.log`
（`EES_VIVADO_RESULT PASS` ×3；bank_err 全程 0；off-by-one 专项 R7 零错；
jobs fed==hdr==done==25，words==EXP 三层精确）。
v2 三层 FAIL（56/26/27）根因三项全修：① bank W 首拍写址用 NBA 未落地的
旧 wk_cnt（组合旁路 w_wa 修复，w_final 同改）——DUT 侧本 run 唯一 RTL bug；
② TB 单元层 len=9/13 越界 KC=8（L9/LLONG 钳位）；③ TB ldjit 末拍后随机隙
让过 ld_done 单拍脉冲 + EXP_WORDS 差一。设计强化：rd_busy 硬门控覆盖
整个字流窗含停拍冻结段（TDP 同址冲突结构性排除的写侧半边收口）。
详见 run09 README。

### 5. P1.3 run10a 三体合并门——PASS ×2（一跑零迭代）✅

| 档位 | checks | errors | proto_err | started/done/aborted | blocks/blk_done/ld_done |
|---|---|---|---|---|---|
| 4×4 (KC=1152) | 846 | 0 | 0 | 62/60/2 | 72/12/74 |
| 8×16 (KC=1152) | 4250 | 0 | 0 | 37/35/2 | 47/12/49 |

控制台：`4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run10a_merge/merge_console.log`
（`EES_VIVADO_RESULT PASS` ×2）。与 run06/run08 逐数严格对齐；随机流逐字
承袭 run08 ⇒ 数据逐字相同，y 对拍同时是跨供数实现（TB 直驱 vs bank+feeder
真机构）对照，双实现零差异。RTL 零改动；TB 自查三处（bank_err 前置声明、
ld_done 脉冲窗中同拍采样、G6 rs1 抽取奇偶——固定击杀拍数会少抽种子使
G7 起数据漂移）。16×16 不跑（W 字 128b 无 64b 写口通路，覆盖冻结 run08）。

## 判定标准（事先声明）

- 三档仿真 PASS 标准：errors=0 且守恒 started−aborted==done 且
  blk_done_seen==exp_blk_done —— 已达成。
- 综合评估标准修订（终态）：A 的目的 = G2 证据（已达成：294912×2 寄存器
  警告 + 15GB 内存实测 + 590k>106.4k 算术结论）；B/C 已随 P0 取消，
  G2 综合门按 100MHz WNS≥0 绝对值判。
- 板测（明日晨）：见板测计划文档；本日无板上操作。

## 未验证/留待后续

- P1.4 OOC 综合：8×16 Kc=576/1024 双配置，BRAM≈12、100MHz WNS≥0 绝对判
  （当前动作）
- G4 DMA/CSR 接入与系统级时序（PS 100 MHz 域）
- 板级功能（等 G2/G4 完成后整体上板，用户在场）

---

# 第二班次：IP 硬指标重做链 run11–run16（全链收官）

**背景**：用户硬指标——所有数据通路必须真 IP（DSP48E1 primitive 例化
裁定①合规；SiLU LUT 亦须 IP 化；例化必须逐端口对 .veo）。原有非 IP
数据路径的验证结果全面重跑，不清楚的一律重跑。

## 六门判定总表

| 门 | DUT | 判定 | 关键数（与 IP 化前逐数对齐） |
|---|---|---|---|
| run11 bank 单元 | bank V2.0.1（4×BMG 真 IP） | PASS（6 跑收敛） | checks=5585 errors=0 blocks=49；**抓到真 bug：W-only len=1 首拍闭口读旧 xk_cnt（x_wa 组合旁路修复）** |
| run12 bank+feeder | 同上 ×3 档 | PASS ×3（一跑） | KC=8/64/576：150/271/1295 全 EXP_WORDS 精确；R1-R8 零错 |
| run13 tail 单元 | tail V2.0（LUT=BMG 真 IP，D+4） | PASS（一跑） | checks=712 lat_err=0；golden 10 向量双向交叉；D+4 硬查全绿 |
| run14 array ×3 | array **V2.1** | PASS ×3（一跑） | 846/4250/6881 与 run06/run08 全字段一致；**抓到真 bug：坐标镜像三级未随尾 D+4 加深（提前一拍），V2.1 加为四级** |
| run15 core 单体 | core V1.1（封装） | PASS（一跑） | 4250/0/0、37/35/2、47/12/49 与 run10a 8×16 档一致 |
| run16 OOC 综合 | core V1.1 + 5 IP 全网表 | 资源✅/时序❌ | BRAM36=12+RAMB18=1 精确命中；DSP=68；LUT 13.5%/FF 4.8%；**WNS=−4.728 @100 MHz（Fmax≈67.9 MHz）→ 用户决策点 A/B/C** |

## DUT 版本变迁（本链）

- bank V1.1→V2.0.1：寄存阵列→4×BMG IP（TDP 64b/128b×1024 byte-WE、
  双组乒乓、无参定宽 8×16）+ x_wa 首拍旁路修复。
- tail V1.0→V2.0：LUTRAM→gemm_bm_lut IP（SDP 8×256），流水 D+3→D+4
  （stage3 组合地址直驱 BMG 读口、BMG 内部寄存器为第 3 级）。
- array V2.0→V2.1：坐标镜像 yr/yn 3→4 级（随尾 D+4）。
- core V1.0→V1.1：三体封装随 bank 无参化（P_KC 删除，Kc 纯逻辑）。
- feeder/pe_core/acc_dual/mac_cell：零改动（feeder 本无存储；PE 线
  DSP48E1 primitive 例化即用户裁定合规）。

## run16 时序决策点（挂起待用户）

关键路径：tail stage3 64 位 RNE CARRY 链（38 级，CARRY4×32）直驱
BMG 地址 setup，14.08 ns（逻辑 8.1+布线 6.0）。
预案：A 加深一级（预计仍不闭，需配算术收窄）/ B 算术收窄（触碰
§8 冻结契约）/ C 降频 ≤67 MHz（零 RTL 改动）。详见
`4_metrics/logs/2026-09-19_yolo_gemm_ip_run16_ooc_syn_bmg/README.md`。

## 上板路线（用户中午问询，已答）

B1 GEMM 顶层（**纯 Verilog .v**，可拖 BD）挂已绿 axi_csr 联合上板
（CSR 搬数小 KC 金向量回环）→ B2 PS-DMA 独立回环 → B3 DMA+GEMM
大 KC 全流 → B4 与 CSR 引擎线全联。板上动作仍限用户在场。

## 第三班次：WNS 决策 A+B 收敛链 run17–run20（时序门闭环）

用户决策（2026-09-19 下午）：WNS 走 **A+B 组合**；上板路线 B1-B4
确认、B1 先行授权。执行结果：

| 门 | DUT | 判定 | 数字 |
|---|---|---|---|
| run17 | tail V2.1→V2.2 | PASS ×2 迭代 | 711/0/0；701+3=704 守恒 |
| run18 | array V2.2 镜像五级 | PASS ×3 ×2 | 846/4250/6881 全 0 err |
| run19 | core V1.1（V2.2 尾） | PASS ×2 | 4250/0/0；47/12/49 |
| run20 | OOC 综合 100MHz | **PASS WNS=+1.392** | TNS/THS=0，12546 端点全过 |

两迭代轨迹（判据始终 100MHz WNS≥0）：
- V2.1 magic-add 恒等式（65 位加+桶形同拍）：−4.728 → **−2.669**，
  关键路径 prod_r→qn_r 12.66ns/29 级——加法链与移位树串在一级，未闭。
- V2.2 并行逐位判决（OR 树无宽进位链，+ru 由 stage4 10 位窄加吸收，
  边界 255+1→127 / −256+1→−128 正确饱和）：**+1.392**（Fmax≈116MHz），
  关键路径 sh2_r→ru_r 8.60ns。**D+5 不变**，镜像五级/TB 延迟零改动。
- 语义等价证据：V2.1 与 V2.2 两版 711/0/0 逐数相同；golden 双向交叉
  + T1 ties-even 专项 + 手算例（±5/±6/±7 s=1、±4/±5 s=3）全过。
- 资源判据不变：BRAM36=12 + RAMB18=1（IP 全网表未动）。

**G2 时序门收官：100MHz WNS≥0 达成，功能/资源/时序三门全闭。**
core V1.1（tail V2.2 + array V2.2）= B1 上板例化基线。
证据：`4_metrics/logs/2026-09-19_yolo_gemm_ip_run1{7..9}_*/`、
`2026-09-19_yolo_gemm_ip_run20_ooc_syn/`。
