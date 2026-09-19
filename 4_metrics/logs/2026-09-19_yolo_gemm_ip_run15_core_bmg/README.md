# run15 — 合并核心单体门（core V1.1）· BMG IP 重做第五门

**日期**：2026-09-19 · **性质**：IP 硬指标重做链 run11–run16 第五门（用户序⑤）
**判定**：**PASS（一跑通过），与 run10a 8×16 档逐数对齐 ✅**

```
EES_SUMMARY checks=4250 errors=0 proto_err=0
EES_ARR_INFO config=8x16 tiles started=37 done=35 aborted=2 y=4250
EES_ARR_INFO blocks_fed=47 blk_done=12 ld_done=49 (Kc logical)
EES_VIVADO_RESULT PASS
```
与 run10a（三体分立例化、旧寄存阵列尾）8×16 档完全一致：4250/0/0、
37/35/2、47/12/49——**同一刺激同一 golden，全 IP 数据通路零语义漂移**。
（证据：`core_bmg_console.log`）

## DUT / TB / 流程

- DUT：`yolo_gemm_core` **V1.1** 单体（相对 run10a 的"三体分立"，封装
  连线一并入测；即 run16 OOC 综合顶层与上板例化单元）：
  - bank **V2.0.1**：4×BMG 真 IP（gemm_bm_w_g0/g1 TDP 64b×1024 +
    gemm_bm_x_g0/g1 TDP 128b×1024），无参定宽 8×16；
  - feeder（未动）+ array **V2.1**（坐标镜像四级）+ tail **V2.0**
    （gemm_bm_lut 真 IP，D+4）。
- TB：`tb/tb_yolo_gemm_core_bmg.sv`（run10a TB 改造，共 5 处：
  ①三体例化→core 单体 ②删 feeder↔bank/feeder→array 内部线
  ③P_KC 删除（Kc 纯逻辑）④4×4 档退役（bank 定宽无通路，等价覆盖
  已由 run08/run14 冻结 846×2）⑤头部/模块名；G1-G9 刺激/golden/
  判据逐字保留）。
- 流程：`sim_gemm_core_bmg.tcl`（pe_pack + 5 IP wrapper + 9 件 -sv +
  glbl；xelab 带 `-L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim`）。
- 旧件保留：run10a 的 `tb_yolo_gemm_merge.sv` 未动（历史证据）。

## 覆盖（G1-G9 与 run08/run10a 逐字同矩阵）

G1 K=1/27/32/576 单块 / G2 2304=[576×4]/[1152,576,576]、1152=[576,576]
分块续累（ping-pong 组交替 b&1）/ G3 [1,1,27,1,34] 非规则 / G4 行列
掩码尾 / G5（抖动随直驱退役，tile 保对齐）/ G6 job 递交后流中 rst 击杀
×2 / G7 背靠背 / G8 首层大 bias / G9 随机 15 tile。
合并层仪器全零：proto_err=0、bank_err=0（上升沿计错）、ld_done=49
精确对账、守恒 35+2=37。

## 结论

- **全 IP 数据通路（4 bank BMG + LUT BMG + DSP48E1 阵列）在封装单体、
  完整调度矩阵下逐数复现 IP 化前结果**——重做链功能侧至此闭环，
  唯余 run16 OOC 综合门（资源/时序定档）。
- 下一门：run16（yolo_gemm_core OOC 综合：5 IP 全网表、BRAM 预算
  12×RAMB36E1+1×RAMB18E1、WNS 新测定）。
