# M10 gemm_array 门 run05 — V1.7 flush 读修复（迭代 5 收口）

日期: 2026-09-17 01:20–01:33 · 工具: xsim (Vivado 2025.2) · 判决: **PASS**

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
```

## 背景（run04 = M10 v18 FAIL, err=13220）

xbuf V2.2 BMG 输出寄存合同（Register_PortB_Output_of_Memory_Primitives=true,
读延迟 1→2, 2026-09-17 用户授权）下, BMG 的 ENB 同时门级 stage1（memory
源语输出）与 stage2（源语输出寄存）。每个读拍的字在**下一个读使能沿**落到
DOUTB: beat 0..K−2 的提交沿恰是下一 beat 的读, 但**末拍 word[K−1] 滞留
stage1 永不提交**（K 环是唯一读者, 再无读使能沿）→ PE 墙收到 word[K−2]。

## 根因证据链（probe v1–v4, xsim）

- DUT lane(0,0) acc = 16599 vs python 黄金再生成 16401（超额 +198）
- 前 26 拍操作数/乘积逐拍核对全部正确（wrow/xcol 配对 beat 对齐）
- [prbT] 尾窗: 末拍乘积 = +159 = W[26]×word[25], 应为 −39 = W[26]×word[26]
- q0 步进 16440 → 16599 = 16440 + 159（恰差该错误乘积）

## 修复（rtl/yolo_gemm_array.v V1.7）

`xren_flush_q`: 检测 `ctrl_beat_en && ctrl_k_cnt == cfg_k_r−1`, 次拍补一个
读使能沿（`xren_w = ctrl_beat_en || xren_flush_q`）——末拍字恰在 D+2 操作
数相会拍提交到 stage2; raddr 重采 k_cnt（保持 K, 垃圾进 stage1 不提交）。
消费者侧生成, ctrl/addrgen/requant/xbuf wrapper 均不动 → M4/M5/M7/M8 v18
门对该修复免重跑。K=1 tile 同样修复（其唯一拍原本全陈旧）。

## 构建

sim/xsim/run_m10_v19.sh — work_m10v19, 12 rtl + BMG sim + tb_yolo_gemm_array
+ glbl; 帧证据: m10_v19_{xvlog,xelab,xsim}.log。激励 = sim/stim/m10（seed
1010 不变, 数值合同不变——本修复纯时序）。

## 门链状态（本批后）

M4 v18 PASS · M5 v18 PASS · M7 v18 PASS · M8 v18 PASS · **M10 v19 PASS**
→ B0 OOC v19（proj/ooc_gate/ooc_v19.tcl）接力。
