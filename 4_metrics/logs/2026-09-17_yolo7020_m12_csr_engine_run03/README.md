# 2026-09-17 yolo7020 M12 CSR/engine 门 run03 — B0 迭代 7（csr V1.1 + dma V1.1 + dma_wr V1.3）

## 结果

**TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
gold_wr=3247 ldone=6 adone=1 csr=0**——七项计数与 run02（2026-09-16,
xsim）逐一相同；csr=0 = AXI-Lite 协议/读回/IRQ 检查零错。

## 本跑覆盖的变更（相对 run02）

| 模块 | 版本 | 变更 |
|---|---|---|
| csr | V1.0→V1.1 | LUT 写口寄存化 + max_fanout=32（v20 ooc owner bpend_r→lut_reg[*][*]/CE −0.773 纯布线；写脉冲晚一拍，仅配置期，表内容最终一致） |
| dma | V1.1 | 增量 bnd_r（M9 run02 证明） |
| dma_wr | V1.3 | 增量 bnd_r 镜像（M9b run04 证明） |
| xbuf | V2.0→V2.2 | BMG 输出寄存（读延迟 1→2 拍，数值字节不变） |
| gemm_array | V1.2b→V1.6/V1.7 | 装载侧延迟适配 + V1.7 冲排读修复（M10 run05/run06 证明） |
| ctrl | V1.8 | S_DRAIN 3→4 等延迟适配 |

即本跑是 engine_top 级在完整 BMG 输出寄存合同（2026-09-17 用户授权）
+ 迭代 7 批下的首次 xsim 重组验证：CSR 真控制路径（LUT 预载/描述符/
轮询/IRQ）× engine 数值链全绿，数值计数与合同前完全一致。

## 仿真环境

- xsim（Vivado 2025.2）+ Vivado 自带预编译 blk_mem_gen_v8_4_12 库；
  独立工作目录 sim/xsim_eng（run_m12csr_v21.sh）
- 激励 = stim/m10 冻结集（与 M10 run04+ 同一零漂移校验）
- 原始日志：eng_v21_{xvlog,xelab,xsim}.log

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim_eng && bash run_m12csr_v21.sh
```

门链位置：B0 迭代 7——M9 run02 → M9b run04 → **M12 csr run03**
→ M10 run06 → OOC v21。
