# run09 — P1.2/V2 bank+feeder 一体门（yolo_gemm_bank + yolo_gemm_feeder）

- 日期：2026-09-19
- 判据（批准计划）：全遍历 errors=0 + off-by-one 专项 PASS，三层 tier 全绿
- 结果：**PASS**（v3，bf_console_v3.log）

## 最终结果（v3）

| tier | 配置 | checks | errors | jobs | words | ld_done | 判定 |
|---|---|---|---|---|---|---|---|
| tb_bk1 | 4×4 KC=8（单元层） | 150 | 0 | 25 | 150 | 27 | PASS |
| tb_bk2 | 8×16 KC=64（基线形） | 271 | 0 | 25 | 271 | 27 | PASS |
| tb_bk3 | 8×16 KC=576（深度实形） | 1295 | 0 | 25 | 1295 | 27 | PASS |

- 守恒：jobs fed==hdr==done==25；words==EXP_WORDS 三层精确相等；bank_err 全程 0
- off-by-one 专项（R7：len=1 首末同字 / len=2 / KC-1 / KC 顶地址 / 背靠背 drain=4）零错
- 阶段：R1 单块长度族 / R2 真交叠乒乓+回绕陈旧覆盖 / R3 早到-恰好-晚到(重装压顶) /
  R4 确定性停拍(字0/4/8)+随机抖动 / R5 W驻留X独立换组(含 X-only 装载) /
  R6 lane-WE 合并重写 / R7 off-by-one / R8 活流中写读选组拒绝（结构性无冲突纪律）

## 一体验证形态（为什么 bank+feeder 必须一体过门）

读地址引两拍（BRAM 同步读 1 + 保持寄存 1）——读通路无法脱离真实 RAM 时序单独验证；
TB 同时扮演装载生产者与阵列消费者（V2.0 纯消费者契约：header 在 IDLE/WAIT 接受、
ISSUE 态 ready 高、抖动/停拍模式、DRAIN≥4）。golden = TB 镜像阵列，与 DUT 同一套
BE 合并语义；逐拍核对数据 + first/last 旁带 + k 序。

## V2 读侧契约要点（本 run 定稿并验证）

1. **无 k0**：每个装载块都从组地址 0 开始——绝对 k/块基址职责随 run08 移交供数方后，
   在此正式退役：**块基址活在装载顺序里，不在读侧**。
2. **唯一 k 计数器**：feeder 单计数器驱动 W/X 两读口；kcnt 只随流水推进，
   停拍即冻结（地址冻结⇒dout 稳定，无限期停拍合法）。
3. **换组拍**：阵列不露 accept 脉冲——ISSUE 进入可观测为 word_ready 升起；
   组翻转落在观测拍（首地址发出前一拍），地址路由与出口级 dout MUX（在 feeder，
   board plan §2）恒一致；旧组末地址离口 ≥2 拍（阵列 DRAIN≥4）满足结构无冲突。
4. **rd_busy 硬门控**（本 run 设计强化，超出计划保守条文）：
   `rd_busy = S_STREAM ∥ v1 ∥ v2` 覆盖整个字流窗含停拍冻结段——
   "非读选组"的 ld_ok 判定若只看 ren 历史，停拍时 ren 已冷而字仍在飞，
   放行装载会在恢复读时与写形成同址 TDP 冲突；busy 门在整个窗口禁止。
   bank 侧：`ld_ok[g] = (g != rgrp) || ~rd_busy`。
5. **header 装载门控**：两组 loaded 才亮 blk_valid——晚到作业自然压头；
   重装首拍清 loaded 把已呈现的头压回（R3 重装压顶验证）。

## Bug 史（v1 编译失败 → v2 三层 FAIL 56/26/27 → v3 全绿）

1. **xvlog VRFC 10-3186**（v1）：untyped task 端口默认 1-bit logic 不能位选
   → 端口显式 `input integer`。
2. **bank W 首拍写址错**（v2 主错，25 错/tier2）：wr_first 对 wk_cnt 的清零是 NBA，
   本拍写访问仍用旧终值 → 每块 word0 写到上一块终址；块1 因复位后旧值恰为 0 而
   侥幸通过、后续块全错——tier2 的 `got=afa73b2adeecdf00`（块1 word0）恒定残留
   与 R5 末 X-only 装载清零 wk_cnt 后 R6 全写恰好落址的"反常自愈"共同锁定根因。
   修复：组合写址 `w_wa = wr_first ? 0 : wk_cnt`；`w_final` 同改
   （len=1 W-only 块 first=last 同拍否则锁出 stale+1 错长度）。
   X 天然免疫：hi 半字写总在本块首拍之后 ≥1 拍，清零已落地（结构性宽限，注释明示）。
3. **TB 越界族**（tier1 独有 29 错）：R4 len=9×3/LSET+5=13 与 R8 len=9 超过单元层
   KC=8，镜像越界读 X 而 DUT 地址截断回绕 → 钳位 localparam L9/LLONG。
4. **TB ld_done 假丢**（每层 1 错）：ldjit 节间随机隙在**末拍之后**也能插入，
   把单拍 ld_done 脉冲让过采样点 → 间隙只许 `kk < len-1`。
5. **TB EXP_WORDS 差一**：R7 小块和误记 13（实为 1+2+5+5=12）→ 每层守恒恰差 1。
6. **R3 晚到阶段设计错**（v2 时代旧版，已在 v2 启动后重设计）：两组 sticky loaded
   下"装载前 job 必不亮头"不成立 → 重设计为重装压顶（hold_check_en 中途检查点）。

## 教训（沉淀）

- **NBA 清零与本拍访问同拍竞态**：块内"首拍清计数"模式必须配套组合写址旁路；
  与 run08 "块基址是供数方职责"同类——时序责任边界要显式落到契约。
- TB 长度族必须被 KC 参数化钳位；越界镜像读 X 与 DUT 地址回绕的组合会制造
  假数据错（xxx 与回绕真值各半），先查用例参数再查 DUT。
- 单拍脉冲类断言（ld_done）的采样点必须与被测事件紧贴，任何插在中间的
  随机等待都是断言杀手。

## 文件

- DUT：`E:\competition\2_fpga\3_yolo_zynq\rtl\GEMM\yolo_gemm_bank.sv`（V1.1，w_wa 旁路）
- DUT：`E:\competition\2_fpga\3_yolo_zynq\rtl\GEMM\yolo_gemm_feeder.sv`（V1.0）
- TB：`E:\competition\2_fpga\3_yolo_zynq\rtl\GEMM\tb\tb_yolo_gemm_bankfeeder.sv`（含 DBG plusarg 探针）
- tiers：`E:\competition\2_fpga\3_yolo_zynq\rtl\GEMM\tb\tb_gemm_bank_tiers.sv`
- 脚本：`sim_gemm_bankfeeder.tcl`（纯 xvlog/xelab/xsim，无 unisim/glbl——无 DSP 原语）
- 原始日志：`bf_console.log`（v1 编译失败）/ `bf_console_v2.log`（FAIL 取证）/ `bf_console_v3.log`（PASS）

## 下一步

P1.3（run10a）：bank+feeder+array 三体合并，复跑 run06 全矩阵并要求检查数严格对齐。
