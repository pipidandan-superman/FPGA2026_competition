# run17 — 共享尾门重演 · WNS A+B 收窄加深（tail V2.1 → V2.2 两迭代）

**日期**：2026-09-19 · **性质**：run16 WNS=−4.728 决策 **A+B**（用户 2026-09-19 授权）第一门
**判定**：**PASS ×2（V2.1 与 V2.2 各一跑通过，逐数相同）✅**

```
迭代二（V2.2 并行判决式，sim_tail_v22_console.log）：
EES_SUMMARY checks=711 errors=0 lat_err=0
EES_TAIL_INFO driven=704 y=701 flushed=3 last_seen=1
EES_VIVADO_RESULT PASS
（迭代一 V2.1 magic-add：同数 711/0/0、701/3，sim_tail_v21_console.log）
```

## DUT 变更（V2.0 → V2.1 → V2.2，手册 §8 语义零变化）

- **V2.1 B 收窄（magic-add 恒等式）**：RNE 的「64 位掩码/余数/比较/
  条件加」串行链（run16 关键路径 38 级、CARRY4×32）替换为精确恒等式
  `q_RNE = (prod + (2^(s−1) − 1 + q_floor[0])) >>> s`（65 位符号扩展
  加法防 INT64 极值回绕）。手算例含正/负/ties 全对。
- **V2.1 A 加深（D+4 → D+5）**：stage3 RNE 寄存；stage4 SE 判验 + 9 位
  饱和 + 地址加直驱 BMG（`enb=v3_r`）；edge5 出 y。
- **V2.2 并行判决式（run20 迭代一 WNS=−2.669 后）**：`ru = prod[s−1] &
  (rem低位非零 | prod[s])` 纯逐位逻辑（OR 树，无宽进位链），`+ru` 由
  stage4 的 10 位窄加吸收（255+1→127、−256+1→−128 边界正确饱和）。
  D+5 不变。两版 TB 逐数相同（711/0/0）即两位级等价。
- **守恒差一解释**：run13=712/702/2 vs run17=711/701/3——同一随机流
  下 T5 rst 击杀拍在飞元素随 D+5 多一个（flushed+1/y−1/checks−1），
  非语义漂移。

## 流程

- TB：`tb/tb_yolo_gemm_tail_bmg.sv`（延迟硬查 4→5，其余逐字未动；
  独立 oracle=截断除法+floor 修正+RNE，与 magic-add 法不同构）。
- tcl：`sim_tail_v21.tcl`（gemm_bm_lut wrapper + tail + TB + glbl，
  `-L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim`，GOLDEN plusarg
  指 run01 golden_tail.hex）。

## 结论

收窄恒等式 + 加深一级在功能侧零漂移；下一门 run18（阵列 V2.2
镜像五级 ×3 档）→ run19（core 单体）→ run20（OOC 综合 WNS≥0 判）。
