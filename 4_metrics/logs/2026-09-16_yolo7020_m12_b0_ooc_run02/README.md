# 2026-09-16 yolo7020 M12 B0 OOC 门 run02 —— 源语/IP 修复后（放得下 ✓ / 时序待优化批）

## 结论（一段话）
B0 首问"这一版仿真的版本能不能放得下"——**放得下**：DSP 142/220（64.5%）、
LUT 20686/53200（38.9%）、FF 13474（12.7%）、BRAM 20/140（14.3%），布线
37915/37915 全通、DRC 0 违反。修复目标精确达成：**PE 阵列 128 DSP =
每 PE 恰 1 个**（run01 推断式拆解为 228）。150MHz 时序未达（WNS −31.14ns，
等效 26.45MHz），按用户既定顺序（"先综合看看能不能放得下，优化放在后面"）
时序收敛属下一批。

## 资源对比（run01 失败链 → run02）
| 指标 | run01 | run02 | 预算 | 占比 |
|---|---|---|---|---|
| DSP48E1 | **238 超限** | 142 | 220 | 64.5% |
| Slice LUT | 37214 (70%) | 20686 | 53200 | 38.9% |
| LUTRAM(xbuf) | 13824 | 0 | — | — |
| BRAM | 0 | 20 RAMB36 | 140 | 14.3% |
| Slice FF | — | 13474 | 106400 | 12.7% |

DSP 142 = 128 PE + 7 addrgen + 4 requant + 1 row_addr_d0_w + 1 ctrl_rq_last_w1
（routed DCP 逐单元分类，ooc_dbg4）。

## 修复内容（数值路径全部不变，门证据齐）
1. `yolo_pe_pack` V1.1：DSP48E1 源语直例（OPMODE=0000101 全旁路），
   M1 run02 PASS 10216/10216（xsim + unisim）
2. `yolo_xbuf` V2.0：2× blk_mem_gen IP（SDP 128b×2304、16 字节写使能、
   READ_FIRST、读延迟 1 拍；10 RAMB36/bank），M4 run02 PASS 97464/97464
3. `yolo_gemm_array` V1.2b：u_pe `.clk_i` 连线，M10 run04 PASS
   layers=6 compared=438447
4. M11 全网 / CSR-engine 重跑同批执行（PASS 后证据另附目录）
5. 本目录 = OOC run02（synth+opt+place+phys_opt+route 全流程）

## 时序剖面（下一批"优化"的输入数据，150MHz 约束下）
- WNS −31.140ns / TNS −197901ns / 17610-26562 端点违反 → fmax 26.45MHz
- 子系统 WNS：addrgen −31.1（98 级织物锥，描述符除法）、requant −24.2
  （44 级组合锥）、PE_acc −22.9（高扇出 valid→acc CE 纯布线 ~23ns +
  无流水果法链）、xbuf −12.1、ctrl −12.9、dma −3.9、dma_wr −3.1、wbuf −2.3
- 架构既定的优化路径（pe_pack V1.0 头注已预告）：集成侧给 DSP 开
  MREG/PREG（单元合同保持组合，数值路径需全链门重跑）、addrgen 每层
  预计算替代运行时除法、requant 锥切级、高扇出控制网复制。

## 环境
- Vivado 2025.2 批处理（F:\vivado2025），器件 xc7z020clg484-1（EES-331）
- OOC 模式（顶层 IO 自动 false path），create_clock 6.667ns（150MHz，
  2026-09-16 架构决定），脚本 ooc_run02.tcl（本目录 manifest 含哈希）
- IP：read_ip yolo_xbuf_bmg.xci（DCP 由 ip/gen_xbuf_bmg.tcl synth_ip 产出）
- 产物：ooc_run02_routed.dcp（proj/ooc_gate/，未入证据目录，体积）

## 失败链（保留）
run01：DSP 238/220 综合阶段失败（ooc_run01_vivado.log，本目录有副本，
原位文件不改写）；归因证据 ooc_dbg1（层次化资源）/ooc_dbg2（DCP DSP
分类 PE=228）/ooc_dbg3（requant DSP 参数），proj/ooc_gate/ 原位。
