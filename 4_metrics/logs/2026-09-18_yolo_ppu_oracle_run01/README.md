# P1 — PPU oracle 全图回放门 run01

- 日期：2026-09-18 深夜。脚本：ppu_oracle.py（内核库）+ ppu_replay.py（回放器），
  副本在本目录，源件 2_fpga/parallel_task/3_oracle/。
- 命令：python ppu_replay.py <本目录>
- 结果：**PPU_ORACLE_PASS** — 5 帧 × 53 节点 = 265 次位级比对 0 失配；
  每帧图算子可比节点 12（6 add + 2 upsample + 4 顶层 concat）全对；
  maxpool5 pad 模型 vs 有效位掩码模型在全部 3 实例 × 5 帧实数据逐位等价
  （手册 §2.2 等价性实证）。
- conv 路径逐字转录 gemm_golden_replay.py（G0 已证 ≡ 软件 golden）；
  图算子路径只经 ppu_oracle 内核（逐字转录 intref run04）。
- C2f 内 cat/pool/split 无直接 golden 张量，由下游 conv/add golden
  传递覆盖（如 model.9.pool*→model.9.cat→model.9.cv1 链）。
- **P2 设计输入（requant_stats.json，250 次应用/10.82M 元素）**：
  真实数据 RNE 平局事件 0 次（饱和 3817、同尺度恒等路 100/250、
  最大 distinct 138）→ P2 向量生成器必须构造性覆盖平局（奇/偶 q 两向）、
  饱和上下界、M=0 死通道、s=0 旁路、恒等对，生成期断言 ≥1 each。
- 产物：replay_console.log、replay_result.json、replay_result_f0..f4.json、
  requant_stats.json、脚本副本 ×2。
