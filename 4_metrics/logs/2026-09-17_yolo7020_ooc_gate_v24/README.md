# 2026-09-17 yolo7020 OOC gate v24 — B0 迭代 10（requant V1.2e 窗口化解码）

## 结果

```
GEMM16_OOC_TIMING_FAIL wns_ns=-0.224 whs_ns=0.090 fmax_mhz=145.12 target_mhz=150.0
OOC_V24_RES dsp48e1=141 ramb36=20 ramb18=0
```

WNS 轨迹：v21 −0.713 → v22 −0.581 → v23 −0.457 → **v24 −0.224**（fmax
135.5 → 137.97 → 140.37 → 145.12）。requant 64 位桶形家族（v23 top10 全体
−0.457…−0.340）整体退出。

## v24 批变更（迭代 10，位精确，黄金全复用）

requant V1.2d→V1.2e：q_r 的全部消费者只需 q[7:0]/q[63]/在域判定——
64 输出桶形 `prod >>> s` 整体消失（64 FF→10 FF）：
- q8 窗口 mux ×8（q[j]=prod[j+s]，越界补符号）；
- qneg_r = prod[63]（算术右移保号，0L）；
- 在域判定代数化：q∈[−128,127] ⟺ magn<2^(s+7)，magn=prod[63]?~prod:prod，
  himask_r（=全1<<(s+7)，s≥57→0）c2 沿预寄存后 AND+OR 归约。

M5 v24 首跑 FAIL 2739 错（himask 首版写成低位掩码 `~(全1<<(s+7))`，
等价拿 magn 低 t 位做在域判定；M5 v24 门拦下，transcript 留档
m5_v24a_xsim_fail.log），修复后 run03 PASS compared=21465。

## top10 owner（v24 → 驱动迭代 11）

两族：
1. **requant c3 解码**（6 条，−0.224…−0.076）`u_requant/prod_c_w__2/CLK →
   q8_r/ir_r/half_r`——桶形虽消失，解码仍从 DSP 内部发火：prod_r 被吸收为
   DSP48E1 P 寄存器，CLK→P 出 DSP 长连线 + 3 级 64:1 窗口 mux 为关键维，
   同拍位选无解 → 迭代 11 ① = requant V1.2f（prod2_r fabric 重寄存，
   PIPE 5→6 纯输出侧重定时）。
2. **addrgen**（4 条，−0.158…−0.121）`kh_r→pad_o/x_addr_o`、
   `k_len_c→row_off_r` → 迭代 11 ② = addrgen V1.3（两级输出寄存拆分
   窗口解码 + last_k 超前一拍预测）。

## 门链

M5 v24（run03）+ M10 v24（run09，计数与层完成时刻和 v21–v23 逐拍相同）
+ M12 csr v24（run06，csr=0）+ 本跑。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/proj/ooc_gate && vivado -mode batch -source ooc_v24.tcl -nojournal
```

判决 token 打印至 ooc_v24.log；top10 见 ooc_v24_top10.rpt。
