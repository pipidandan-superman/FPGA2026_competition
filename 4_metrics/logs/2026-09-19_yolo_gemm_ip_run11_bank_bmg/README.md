# run11 — GEMM bank 单元门（用户序②：pp ram 先行）· BMG IP 重做第一门

**日期**：2026-09-19 · **性质**：IP 硬指标重做（用户批准的 run11–run16 链第一门）
**判定**：**PASS** — `TB_BANK_BMG PASS checks=5585 errors=0 blocks=49`
（末行见 `sim_bank_bmg_console.log`；判据=TB 内独立 oracle，零依赖旧 run 结果）

## DUT / TB

| 项 | 内容 |
|---|---|
| DUT | `rtl/GEMM/yolo_gemm_bank.sv` **V2.0.1**（存储=4×BMG IP：`gemm_bm_w_g0/g1` TDP 64b×1024 字节WE(8)、`gemm_bm_x_g0/g1` TDP 128b×1024 字节WE(16)；例化逐端口对 .veo 核对） |
| TB | `rtl/GEMM/tb/tb_yolo_gemm_bank_bmg.sv`（独立字节镜像 oracle：mwm/mxm + 期望 FIFO 对账） |
| IP 生成 | `gen_gemm_ip.tcl` → `rtl/GEMM/ip/`（blk_mem_gen 8.4 rev12，输出寄存器关=读延迟1/dout保持） |
| 流程 | `sim_bank_bmg.tcl`：xvlog 5 IP wrapper + glbl.v → xelab `-L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim` → xsim -runall |

## 覆盖（判据强度）

- **相 A 定向**：A1 W-only len1（first=last 同拍）/ A2 X-only len1 / A3 混合随机 be /
  A4 be=00 不写保持 / A5 全深 1024+1023 双组 / A6 同组换血 / A7 真交叠乒乓
  （fork：读 g0 60 字流中并发装 g1，写畅通+读零扰动，重叠后 g1 读回逐字对账）
- **相 B 随机 40 块**：wlen/xlen∈[0,25) 随机（不双零）、组随机、W/X 交织、
  逐拍随机 be、随机断流；每块全范围读回（背靠背流 + 流中随机停拍 dout 冻结 +
  流末保持）+ 读窗口内写读选组必须被拒（wr_ready=0，无访问，负测）
- **守恒**：ld_done 脉冲数==块数；每脉冲 len 与期望 FIFO 对账；bank_err 恒 0

## 过程（5 跑收敛，全部留档）

| 跑 | 结果 | 根因 |
|---|---|---|
| run1 | FAIL errors=70 | **TB bug**：X lo 拍误带 wr_last → 提前收口 len 恒差 1 + hi 拍幻影二收口（守恒 77≠49） |
| run3 | FAIL errors=84→错位 | **TB bug**：wr_beat 握手 delta 竞态——negedge 驱动后零延时读组合 wr_ready 得旧值 1，被拒拍误判已接受而静默丢拍（A7 的 10 个 X 拍全丢：x_wr 零脉冲、无收口、g1 数据未落地）；另 A6 后 x_rgrp 悬 1 使 A7 的 X 目标组静态挂读选组（负测形态） |
| run4 | FAIL 全线双计 | **TB bug**：握手重构后 else 分支残留旧 `@(posedge)` → 每拍双接受（len 2047=1024+1023） |
| run5 | FAIL errors=2 | **DUT 真 bug（V1.1 遗留）**：W-only len=1 块收口拍 `x_final=xk_cnt` 读上一块残留计数（首拍清零是 NBA 未落地）→ V2.0.1 加 `x_wa` 首拍组合旁路（与 w_wa 对称） |
| run6 | **PASS** | checks=5585 errors=0 blocks=49 |

## V2.0.1 变更（唯一 RTL 改动）

```systemverilog
wire [12:0] x_wa    = wr_first_i ? 13'd0 : xk_cnt;
wire [13:0] x_final = x_wa + ((wr_acc && wr_is_x_i && wr_x_hi_i) ? 14'd1 : 14'd0);
```

## 结论

- bank V2.0.1（BMG IP 存储）控制+数据路径全绿：字节 WE 合并、128b 合并写、
  组路由、rd_busy 门控（含拒绝纪律）、乒乓重叠、深度边界、守恒。
- TB 纪律修正沉淀（负例）：X lo 拍永不收口；wr_ready 采样必须在 posedge 之后
  （组合函数跨 delta 的旧值不可读）；read_verify 后 rgrp 悬置必须归位。
- 下一门：run12（bank+feeder 一体 ×3 档：8×16 逻辑 KC 8/64/576）。
