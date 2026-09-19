# run12 — bank+feeder 一体门 ×3 · BMG IP 重做第二门

**日期**：2026-09-19 · **性质**：IP 硬指标重做链 run11–run16 第二门（用户序②）
**判定**：**三档全 PASS（一跑通过）**

| 档 | 结果 | 守恒 |
|---|---|---|
| 8×16 KC=8（小逻辑 KC，替代原 4×4 档） | `EES_VIVADO_RESULT PASS` checks=150 words=150 | 精确（=86+8+4·8+8+2·8） |
| 8×16 KC=64（基线形状） | `EES_VIVADO_RESULT PASS` checks=271 words=271 | 精确（=86+8+36+13+128） |
| 8×16 KC=576（深度实档） | `EES_VIVADO_RESULT PASS` checks=1295 words=1295 | 精确（=86+8+36+13+1152） |

（证据：`sim_bankfeeder_bmg_console.log`；jobs=25/25/25、ld_done=27/27/27 三档一致）

## DUT / TB / 流程

- DUT：`yolo_gemm_bank` **V2.0.1**（BMG IP，例化无参——宽度固定 G2 基线）
  + `yolo_gemm_feeder`（不动，仍参数化）
- TB：`tb/tb_yolo_gemm_bankfeeder_bmg.sv`（run09 TB 适配：仅 3 处——模块名/
  头部、bank 例化去参、宽度档注释；R1-R8 判据强度原样保留）+
  `tb/tb_gemm_bank_tiers_bmg.sv`（三档 wrapper，8×16 逻辑 KC 8/64/576）
- 流程：`sim_bankfeeder_bmg.tcl`（IP wrapper + glbl + `-L blk_mem_gen_v8_4_12`）
- 旧件保留：run09 的 `tb_yolo_gemm_bankfeeder.sv`/`tb_gemm_bank_tiers.sv`
  未动（历史证据）；宽度退休的 4×4 档按批准方案由小逻辑 KC 档顶替覆盖。

## 覆盖（与 run09 同强度）

R1 长度角点 / R2 真交叠乒乓（fork 装载-消费重叠 + g0→g1→g0 换血）/
R3 早到-恰好-晚到（loaded 门控压 header）/ R4 确定性停拍（首/中/末字，
地址冻结）+ 随机抖动 / R5 W 驻留跨 X 换组 / R6 部分 lane WE 合并
（0F/3C/C3）/ R7 off-by-one（len=1 同拍首末、Kc-1/Kc 顶址、drain=4 背靠背）/
R8 拒写纪律（读选组写必须 wr_ready=0 且零访问、bank_err 不置位、异组畅通）。

## 结论

- bank V2.0.1 × feeder × BMG IP 行为模型在一体化场景（含真交叠与纪律负测）
  下全绿；run11 修复（x_wa 旁路）与 TB 握手纪律在 feeder 环境下复验通过。
- 下一门：run13（tail BMG 门：D+4 流水 vs run01 软件 golden 交叉）。
