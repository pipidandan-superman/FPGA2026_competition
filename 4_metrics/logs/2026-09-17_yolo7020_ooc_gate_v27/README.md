# 2026-09-17 yolo7020 OOC gate v27 — B0 迭代 13（gemm_array V1.10）

## 结果

**GEMM16_OOC_TIMING_PASS wns_ns=+0.005 whs_ns=+0.051
fmax=150.11 MHz**（target 150 MHz，create_clock 6.667ns）。
**B0 150 MHz 收敛。** 布线零错（42390/42390 全通）。

资源：**dsp48e1=140** ramb36=20 ramb18=0 —— DSP 比 v25/v26 少 1：
行地址 16x16 乘法从 2-DSP 级联变为单 DSP（V1.10 寄存积，PREG），
与设计意图一致。

v26 唯一 owner 家族（oc_g_d1_r→row_addr_d2_r0/PCIN −0.031，top10
全同族）被 V1.10 拆分整体消除。v27 top10 新面貌（全部正裕量）：
1. addrgen vld_o → xbuf BRAM ENARDEN +0.005（新临界——xbuf 读使能
   建立，BMG 输出寄存合同下的稳定形态）
2. acc psdsp → acc_r D +0.043
3. ctrl rq_cnt_r → pfc_cnt_r +0.047
4. ctrl FSM → acc_clr 副本 +0.065
5. addrgen vld_o → xbuf ramloop[4] +0.068
6. requant m_x_r → PCIN（V1.2g 吸收后的级联路径，+0.0x 正常态）

## 修复（本跑覆盖）

gemm_array V1.10（详见 rtl/yolo_gemm_array.v 头部 V1.10 条目）：
- cfg 项（n_total/ybase）d1 快照——d1 后不再读 cfg；
- 16x16 乘法寄存积 row_prod_d2_r（d2 沿，单 DSP PREG，弧内无级联）；
- ybase+n_base 并行布线加 row_sum_d2_r（d2 沿）；
- d3 沿合并 row_addr_d3_r，d9 呈现拍不变。
mod-2^32 结合律逐位等价；M10 run12 / M12 csr run09 与 v26 逐拍相同
承证。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/proj/ooc_gate && \
  /f/vivado2025/2025.2/Vivado/bin/vivado.bat -mode batch \
  -source ooc_v27.tcl -nojournal -nolog        # → ooc_v27_drv.log
```

P&R 指令同 v21–v26（place Explore + phys_opt AggressiveExplore +
route AggressiveExplore）。

## B0 WNS 轨迹（150MHz 目标）

| 轮 | WNS (ns) | fmax | owner |
|---|---|---|---|
| v13 | −31.017 | — | 合规批基线（addrgen 除法根因已改判） |
| v14 | −6.507 | — | addrgen V1.1 除法消除后 |
| v15 | −1.982 | — | 迭代 2（row_addr 乘法 d1→d2 寄存） |
| v16 | −1.732 | — | 迭代 3 |
| v17 | −1.463 | — | 迭代 4 |
| v19 | −4.853 | — | xbuf V2.2 输出寄存合同（读延迟 2）回归 |
| v20 | −1.187 | — | 迭代 7（P&R 加强） |
| v21 | −0.713 | — | |
| v22 | −0.581 | — | |
| v23 | −0.457 | 140.37 | requant c3 桶形家族 |
| v24 | −0.224 | 145.12 | 桶形消除（V1.2e）后 requant P 输出 + addrgen 解码 |
| v25 | −0.079 | 148.24 | requant 乘法级联（V1.2f 尾链 + addrgen V1.3 后） |
| v26 | −0.031 | 149.30 | requant V1.2g 消除 → gemm_array 行地址级联 |
| **v27** | **+0.005** | **150.11** | **V1.10 拆分消除 → 收敛** |

门链：M10 run12 PASS + M12 csr run09 PASS（均与 v26 逐拍同）→
**OOC v27 PASS** → M11 v27（ModelSim 过夜，已启动）。
