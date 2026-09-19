# run06 — GEMM 阵列门（③b/④，TO×TN 参数化三档）

- 日期：2026-09-18 仿真（2026-09-19 修复 TAILW 死锁后复跑 PASS，补记 README）
- DUT：`E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_array.sv`
  （V1.1：TAILW 离开判据改 y 拍计数）
- TB：`E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_array.sv`
  （参数化 + 三薄包装 tb_gemm_array_4x4/8x16/16x16，同一 TB）
- 脚本：`sim_gemm_array.tcl`（DSP 真例化 → glbl + unisim 库）
- 原始控制台：`arr_console.log`（PASS 终态）；修复前 FAIL 证据：
  `arr_console_prefail_v1.log` + `dbg/dbg_console.log`（FSM 追踪）

## 结论（终态）

| 档位 | checks | errors | tiles started/done/aborted | y 拍 | blocks_fed / blk_done | 判定 |
|---|---|---|---|---|---|---|
| 4×4（单测档） | 846 | 0 | 62 / 60 / 2 | 846 | 72 / 12 | **PASS** |
| 8×16（基线档） | 4250 | 0 | 37 / 35 / 2 | 4250 | 47 / 12 | **PASS** |
| 16×16（参数档） | 6881 | 0 | 30 / 28 / 2 | 6881 | 40 / 12 | **PASS** |

合计 11977 checks / 0 errors；守恒 `started − aborted == done` 与
`blk_done_seen == exp_blk_done(12)` 三档全吻合。`EES_VIVADO_RESULT PASS` ×3。

## 被测架构（GEMM 手册 §4/§5/§7/§8/§11）

- **广播外积**（非脉动）：行广播 w（一行一 OC），列对广播 x（两 N lane）；
- TO×TN 的 `yolo_mac_cell` 网格（cell = ② PE + 双累加器，DSP 真例化）；
- 共享 K/OC/N 计数器（§11，无 per-PE 计数器）；
- FSM：IDLE→[WAIT]→ISSUE→DRAIN→TAIL→TAILW；
  K>Kc 连续块：首块 first_k 重置累加，末块 last_k 出 done+尾，
  中间块 4 拍排空无 done（acc 保留续累）；
- DRAIN 离开：末块等有效行 done 全体与
  `&((row_done_w & row_valid_lat) | ~row_valid_lat)`；
- TAIL：oc 主序/n 次序串行过**共享尾**（R=1），仅有效元素；bias/M/shift
  按 OC 从 tile 锁存参数仓取（§8：bias 在所有块后只加一次）；
- W/X 为 ③ 档功能缓冲（绝对 k 索引，P_KMAX=2304 深度，多块续累免重载），
  真 bank 机构是 G2。

## 阶段覆盖（三档同构）

| 阶段 | 内容 |
|---|---|
| G1 K_SWEEP | 单块 K=1/27/32/576 |
| G2 BLOCKING | 2304=[576×4]/[1152,576,576]、1152=[576,576] |
| G3 IRREG | [1,1,27,1,34] 不规则块 |
| G4 MASK_TAILS | TO−1 行 / TN−1 lane / 奇行奇列 |
| G5 STALL | issue 随机停顿（1/4 概率插空拍） |
| G6 RST_MID | 在飞 rst 击杀 ×2（手动脉冲块）+ 残影窗 + 复位后新 tile |
| G7 BACKTOBACK | tile_done 后零间隙连发 |
| G8 FIRSTLAYER | ±1e8 bias_eff + M=1 + s=20 量级类 |
| G9 RANDOM | 随机 tile（40/15/8 按档缩放） |

期望值：INT64 逐元素独立乘加 oracle + 不同构 requant 模型 + LUT 图样 A 镜像，
输出值+坐标+顺序三重对拍。

## 调试记录：TAILW 死锁（本 run 的核心 bug）

**现象**（首跑 `arr_console_prefail_v1.log`）：三档值检查全对
（264/2504/5297 checks 已过），但首个掩码 tile 后级联超时——FSM 卡 S_TAILW，
tile_done 永不出现，watchdog 前只有 rst（G6）能解锁。

**定位**（`dbg/`，最小复现 tb_dbg_arr：4×4 K=27 行掩码 0111，逐拍 FSM 追踪）：

```
c=406  st=4(TAIL)  ti=0    开始尾扫
c=417  ti=11 fc=11          末有效元素喂尾（fc==nvc−1 → in_last）
c=420  yv=1                 第 12 拍 y 呈现（含 y_last 脉冲）← FSM 仍在 S_TAIL
c=422  ti=15 扫完 → TAILW
c=423  st=5(TAILW) tdone=0  等一个已经发生过的脉冲 → 永久死等
```

**根因**：尾流水仅 3 级，而 TAIL 态要扫满 TO×TN 个元素槽；掩码 tile 的
末**有效**元素不在末**槽位**，其 y_last 单拍脉冲在 FSM 仍在 S_TAIL 跳过无效
槽时就已经打完；TAILW 晚 ~2 拍进入，电平等待必然错过。全有效 tile 末有效
元素恰在末槽，y_last 落在 TAILW 窗内——所以只有掩码 tile 死锁。

**修复**（V1.1）：FSM 自计数已呈现 y 拍 `ycnt`（任意态递增，首块接受时清零），
TAILW 离开判据改 `ycnt >= n_valid_cnt`。计数值判定对拍序不敏感：
掩码 tile 进 TAILW 时 ycnt 已达上限 → 首拍即离开；全有效 tile 在 TAILW 内
等满。tile_done 仍在 TAILW→IDLE 边沿脉冲（晚于全部 y 呈现，TB 契约不变）。

**教训**：跨模块的单拍脉冲（last/flush 类）不得作 FSM 电平等待条件，除非能
证明脉冲必然落在等待窗内；计数/粘滞判定才是结构安全写法。

## 附带教训（xsim）

- `ycnt` 递增引用的 `tail_y_valid` 原声明在时序块之后 → VRFC 10-3380
  use-before-declaration；声明提前与 `cells_done` 等并列，尾部重复声明删除。
  （xvlog 严格先声明后使用，即使 always 块内引用也不豁免。）

## 下一步

- G2：W/X 真 bank（ping-pong）机构替换功能缓冲；
- 上板准备（run07）：16×16 阵列 OOC 综合时序/资源评估 + 板测计划文档。
