# 2026-09-16 yolo7020 M10 GEMM 阵列 门（run04，xsim + 源语/IP 修复版）

## 目标
M12 B0 修复批后的 M10 门重跑：`yolo_pe_pack` V1.1（DSP48E1 源语直例）
与 `yolo_xbuf` V2.0（2× blk_mem_gen IP）进入阵列全链，验证 6 层重放
数值位级不变。run03（2026-09-16，ModelSim，V1.0 推断版）为基准。

## 结果

**TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
ldone=6 adone=1**——与 run03 同一冻结激励（22 hex + manifest 零漂移），
438447 个输出字节逐位一致，AXI 协议哨兵 0 违例。

## 仿真环境
- **xsim**（Vivado 2025.2 官方 unisim + BMG 预编译库）取代 ModelSim
  （用户指示；M1/M4/烟雾已先行验证工具链）
- 命令（sim/xsim）：xelab tb_yolo_gemm_array glbl -s snap_m10
  -L blk_mem_gen_v8_4_12 -L unisim -L unisims_ver -timescale 1ns/1ps
- 原始日志：m10_xvlog.log / m10_xelab.log / m10_xsim.log（本目录）
- 仿真时长 ~24ms（6 层），CPU ~600s

## DUT 变更（相对 run03，全部数值路径不变）
| 模块 | 版本 | 变更 | 动机 |
|---|---|---|---|
| yolo_pe_pack | V1.0→V1.1 | 乘法改 DSP48E1 源语直例（+clk_i） | ooc_run01 DSP 238/220 超限（推断被拆解） |
| yolo_xbuf | V1.0→V2.0 | 13824 LUTRAM → 2× BMG IP（20 RAMB36） | 原生 IP 化（用户指示）+ BRAM 归位 |
| yolo_gemm_array | V1.2→V1.2b | u_pe 实例 .clk_i 连线 | 承接 pe_pack 端口新增 |

tb_yolo_gemm_array.v 哈希与 run03 相符（未改）。

## 门覆盖（继承 run03）
S1/R1/S2/R3/R2/S4 六层真实几何（k=27/576/64/2304…，含 im2col 地址、
双 bank 翻转、requant/SiLU、AXI 读/写随机停停、单写哨兵）；
黄金 = 4× conv_core 静态镜像（合成层）+ G2 run04 部署导出（真实层）。

## 上游
- 基准：2026-09-16_yolo7020_m10_gemm_array_run03（PASS，ModelSim V1.0）
- 单元门：m1 run02（pe_pack 源语版 10216/10216）、m4 run02（xbuf BMG
  版 97464/97464）
- 失败链：proj/ooc_gate/ooc_run01_vivado.log（DSP 238/220，保留）
