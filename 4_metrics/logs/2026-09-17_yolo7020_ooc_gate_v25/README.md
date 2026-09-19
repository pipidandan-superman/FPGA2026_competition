# 2026-09-17 yolo7020 OOC gate v25 — B0 迭代 11（requant V1.2f + addrgen V1.3 + gemm_array V1.8）

## 结果

```
GEMM16_OOC_TIMING_FAIL wns_ns=-0.079 whs_ns=0.098 fmax_mhz=148.24 target_mhz=150.0
OOC_V25_RES dsp48e1=141 ramb36=20 ramb18=0
```

WNS 轨迹：v22 −0.581 → v23 −0.457 → v24 −0.224 → **v25 −0.079**
（fmax 137.97 → 140.37 → 145.12 → 148.24）。v24 两族 owner（requant
解码 6 条 + addrgen 4 条）整体退出 top10——迭代 11 两项修复均生效。

## v25 top10（唯一族，10 条同值）

`u_array/u_requant/sum_r_reg[16]/C → u_array/u_requant/prod_c_w__2/PCIN[*]`
全部 −0.079。路径细节（ooc_v25_pathdetail.rpt，probe_v25_path.tcl 对
routed dcp 复查）：

```
FDCE sum_r_reg[16]/C→Q      0.456
net (fo=1)                  0.768
DSP48 prod_c_w__1 A[16]→PCOUT 4.036   ← 组合穿透（无输入寄存器）
net (cascade)               0.002
DSP48 prod_c_w__2 PCIN setup −1.400
数据路径 5.262ns（logic 85% = DSP1 内部穿透）
```

根因：33×32 乘法映射为 2-DSP 级联；sum_r 是 c1 加法器的输出，
无可供吸收的输入寄存器 → DSP1（A→乘法器→加法器→PCOUT 4.036ns）
整拍组合穿透。布线仅 0.77ns，布局无解 → 迭代 12 = requant V1.2g
（乘法操作数直通重寄存 sum_x_r/m_x_r，PIPE 6→7，为 AREG/BREG 吸收
提供候选）。

## 门链

M5 v25（PASS 21465）+ M7 v25（PASS 67918）+ M10 v25 run10（PASS，
计数同 run09）+ M12 csr v25 run07（PASS csr=0，层时刻与 v24 逐拍同）
+ 本跑。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/proj/ooc_gate && vivado -mode batch -source ooc_v25.tcl -nojournal -nolog
```

判决 token 与 top10 在 ooc_v25_drv.log；路径细节 ooc_v25_pathdetail.rpt
（checkpoint ooc_v25_routed.dcp 留 proj/ooc_gate，不入 Git）。
