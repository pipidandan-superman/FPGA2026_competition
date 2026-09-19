# 2026-09-16 yolo7020 M12 CSR/engine 门 run02 —— 源语/IP 修复版（xsim）

## 结果

**TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1 csr=0**——七项计数与 run01（2026-09-16，
ModelSim V1.0 推断版）逐一相同；csr=0 = AXI-Lite 协议/读回/IRQ 检查
零错。CSR + engine 组装链在 pe_pack V1.1（DSP48E1 源语）与 xbuf V2.0
（BMG IP）下数值位级不变。

## 位置（M12 阶段）
B0 修复批的门链最后一件（M1→M4→M10 已过，M11 全网并行在跑）：
CSR（PS 真控制路径）+ engine 组装（PROD/SIM 同 RTL 参数化）在源语/IP
化后的重组验证。B0 OOC run02 资源判定（DSP 142/220、LUT 38.9%、
BRAM 20、布线全通、DRC 0）见
`2026-09-16_yolo7020_m12_b0_ooc_run02/`。

## 仿真环境
- xsim（Vivado 2025.2）+ 预编译库（unisim/unisims_ver/
  blk_mem_gen_v8_4_12）；独立工作目录 sim/xsim_eng
- 原始日志：eng_xvlog.log / eng_xelab.log / eng_xsim.log（本目录）
- 激励 = stim/m10 冻结集（与 M10 run04 同一零漂移校验）

## 变更清单（相对 run01，数值路径不变）
pe_pack V1.1 / xbuf V2.0 / gemm_array V1.2b（详见 M1/M4/M10 run02-04
证据目录）；csr 与 engine_top 本身零改动（哈希在 B0 manifest）。
