# OOC v28（A2 RTL 闭包时序门，2026-09-17）

## 判定

```
GEMM16_OOC_TIMING_FAIL wns_ns=-8.750 whs_ns=0.040
                       fmax_mhz=64.86 target_mhz=150.0
OOC_V28_RES dsp48e1=… ramb36=… （见 ooc_v28_utilization.rpt）
```

- 24305 失败端点 / 总违例 −52830ns；**损害全部集中于 X 通路**：
  300 条最差路径归属 = u_xrowgen ×582 + u_dma_x ×18，GEMM 核 /
  重量化 / W 路干净（v27 已闭 150MHz 的部分未回归）。

## 两个主锥（ooc_v28_top10.rpt + v28_p300.rpt）

1. `u_xrowgen/dma_hi3_w2/CLK → cg_khiw_r_reg[*]/CE`，−8.750ns，
   数据路径 15.128ns、12 级（DSP48E1×1 + CARRY4×3 + LUT×8）：
   `(pt_m−1)*sw + kw − 1` 行跨度算术 → 4 部件窗口比较链
   （dma{0..3}_w）→ later_cmd/grp_last_cmd → 发射队列推进 CE。
2. `u_xrowgen/oy0_r_reg[0]/C → pt_row0_r_reg[k][bit]/D`，−8.71ns：
   `part_ih0 = (oy0+pp)*sh − ph` 与 `part_row0 = part_ih0*iw +
   part_iwlo` **双乘级联单周期**（两 DSP 串联）。

性质：结构性欠流水（非布局/扇出问题，逻辑占 60%）。xrowgen 是 A2
新模块，v27 OOC 文件列表不含它 —— 本次是其首次时序暴露（同 B0
addrgen 除法坑的家族：地址生成单周期数学过深）。

## 处置（用户指令优先级：尽快上板验证，板后决策优化）

- **本批不改已承证 RTL**（xrowgen V1.3a 已过 M7 run03 / 在跑 M11
  FULL；动它 = 作废 M7/M10/M11 证据链 + 重跑 2h+ 仿真）。
- 板级 first-light 降 FCLK0 150→60MHz（数据路径 15.128ns 全锥
  ≤15.2ns < 16.667 − setup/skew ≈ 15.9ns，预期 WNS ≈ +0.8ns）。
- M12 时序门按**出货时钟**重跑承证：ooc_v28b60.tcl
  （create_clock 16.667，同净表全流程），判据行
  `GEMM16_OOC_TIMING_60M_PASS`。
- xrowgen 流水化（cone1 判据寄存一拍 + cone2 双乘劈两拍，或预计算
  行跨度表）= **板后优化批**候选，与 A2b（X2/oc-pair）同交用户决策。

## 复现（cwd proj/ooc_gate）

```
vivado -mode batch -source ooc_v28.tcl        # 150MHz 目标（本 FAIL）
vivado -mode batch -source ooc_v28b60.tcl     # 60MHz 出货时钟门
```

## 哈希（sha256 前 16）

```
0f14247fece6fb4d  rtl/yolo_xrowgen.v   (V1.3a，综合双驱动修复版)
24dc59f4cfd0cef9  rtl/yolo_gemm_array.v (V2.0c，同 M10 run13/M11 run05)
cc490c0ce840c2b5  proj/ooc_gate/ooc_v28.tcl
```

关联：v28b60（60MHz 门）、M11 run05（全网回归，进行中）、
M7 run03（xrowgen 综合合法性回归）。
