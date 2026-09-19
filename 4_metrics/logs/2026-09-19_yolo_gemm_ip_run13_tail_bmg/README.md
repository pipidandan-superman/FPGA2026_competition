# run13 — 共享尾独立门 · BMG IP 重做第三门

**日期**：2026-09-19 · **性质**：IP 硬指标重做链 run11–run16 第三门（用户序③）
**判定**：**PASS（一跑通过）**

```
EES_TAIL_INFO T0_GOLDEN vecs=10 (model<->golden + DUT<->model)
EES_SUMMARY checks=712 errors=0 lat_err=0
EES_TAIL_INFO driven=704 y=702 flushed=2 last_seen=1
EES_VIVADO_RESULT PASS
```
（证据：`sim_tail_bmg_console.log`；守恒 702+2=704 精确）

## DUT / TB / 流程

- DUT：`yolo_gemm_tail` **V2.0**（SiLU LUT = BMG IP 实例 `gemm_bm_lut` SDP 8×256、
  读延迟 1；stage3 组合地址直驱 BMG 读口、BMG 内部寄存器即第 3 级、edge4 寄存 y
  → 流水 D+3→**D+4**，用户 lutram-IP 化决策的直接产物）
- TB：`tb/tb_yolo_gemm_tail_bmg.sv`（run05 TB 适配，diff 核验仅 3 类变更：
  ①头部出处/模块名 ②延迟硬查 `!=3`→`!=4`（含报文 want 3→want 4）
  ③两处注释 3→4 拍；T0–T5 刺激与判据逐拍等价，无其他改动）
- 金标准：`-testplusarg GOLDEN=` 指向 run01 软件 oracle 产物
  `2026-09-18_yolo_pe_gemm_dev_run01/golden_tail.hex`（跨 run 合法独立源）
- 流程：`sim_tail_bmg.tcl`（gemm_bm_lut wrapper + glbl +
  `-L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim`）
- 旧件保留：run05 的 `tb_yolo_gemm_tail.sv` 未动（历史证据，D+3 时代）。

## 覆盖（与 run05 同强度 + D+4 重钉）

T0 golden 10 向量双向交叉（model≡golden 先行自证，DUT≡model 再验）/
T1 RNE 平局双奇偶（s=1 手钉 ±1±3±5±7、s=2 偶平局、负平局进位到 0）/
T2 饱和双轨 33 位上界 ×2^30 + M 负 s=0 直通 + shift 全域 s=0..62/
T3 LUT 寻址 sat+128（含 ±128 双轨 addr=0/255、饱和折返）/
T4 400 背靠背随机流（20% 气泡、last 拍打标）/
T5 间隔流 + rst 在飞击杀（flushed 记账 + 残影窗 + 击杀后恢复）。
**lat_err=0**：全部 702 个输出在 D+4 整拍呈现——BMG IP 化后流水深度变化被
延迟硬查当场钉死，无逐拍漂移。

## 结论

- 尾链 IP 化（LUT RAM→BMG IP）后数值全链（RNE/sat/LUT 寻址/旁路）与
  run01 软件 golden 仍逐数一致；D+4 流水深度经硬查验证。
- 下一门：run14（array V2 门 ×3：直驱 8×16、按新 KC 档）。
