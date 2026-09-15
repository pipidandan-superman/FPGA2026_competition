# M7 addrgen 门 run01 — yolo_addrgen（2026-09-15）

## 结果：TB_ADDRGEN_PASS（CLOSED，2 跑过门）

67918/67918 beat（逐拍比对 x_addr/pad/pad_val/k/n_local + 每 tile
done 脉冲与 vld 回落检查），145 tile。

## 工件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_addrgen.v` V1.0 |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_addrgen.v` V1.0 |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/addrgen_vecgen.py`（seed 707） |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/addrgen/`（cfg/cnt/addr/pad/padval/k/nloc + manifest） |
| 本目录 | console_extract.txt / sim_addrgen.log / stim_manifest.json / stim_sha256.txt（9 文件） |

## 合同（golden_extract.py 文档合同 + 基线 §3.1/§3.5）

X-tile 填充地址流（n 外层 × k 内层，每拍 1 beat）：
- `k = ic·(KH·KW) + kh·KW + kw`（K 序与 M0 conv_core V1.1 同式——除数
  是 KH·KW 不是 KP）；
- `ih = oy·SH + kh − PH`，`iw = ox·SW + kw − PW`；越界 → pad beat；
- `x_addr = ic·(IH·IW) + ih·IW + iw`（X 平面 CHW，与 golden_extract
  x_i8.bin 布局一致）；
- pad beat 地址 0，`pad_val = −128`（首层 z 折叠）或 `0`（后续层）；
- 几何在 start 脉冲采样（M8 描述符语义）；n_len 由 ctrl 预钳位
  （本模块信任输入）；N < 2^16、IC·IH·IW < 2^31。

## 激励设计（真实 ×2 + 合成 ×6）

| 案例 | 几何 | 目的 |
|---|---|---|
| real00/real02 | conv0 真实（3x3/S2/P1/IC3/320²/K27/N25600/first），72 tile（64 随机 n_start + 首/尾/左列边界） | **真实回归 + 数据闭合** |
| syn_1x1_nopad | 1x1/S1/P0/IC256/K256 | 零 pad 路径（反退化） |
| syn_k2304 | 3x3/S1/P1/IC256/K2304 | ic 255 次回卷、最大 K 档 |
| syn_tail | N=100（10²），96+4 尾 tile | 尾 tile（ctrl 预钳位语义） |
| syn_allpad | 3x3/S1/P0/1×1 平面 | 27 beat 中 26 pad（z 折叠主导） |
| syn_edge_first | 3x3/S1/P1/4×4/IC32/K288/first | pad 富集首层（pad−128 富集） |
| syn_wrap | 3x3/S2/P1/5²→3²/N9 整 tile | ox 回绕 + oy 递增全覆盖 |

**真实数据闭合**：每条真实 beat 的地址取真实 x_i8.bin 字节，必须等于
numpy 独立窗口提取值（含 −128 pad 的 xp）；任何地址错误都表现为数据错。
实测覆盖：pad 2846（−128 类 1822 / 0 类 1024）、非 pad 65072、真实 beat
30240。

## 过程记录（run1 → run2）

- run1 全红：`k=1(exp 0)` 一拍整体错位——TB 用"先 @(posedge) 再比对"
  的注册输出惯例，而 addrgen 输出是计数器组合直出，beat 0 位于捕获
  posedge 后的那一拍，被循环跳过。RTL 无错、无改动；TB 采样点移到
  每拍稳定窗（negedge+#1）后全绿。**经验：组合直出与注册输出的 TB
  采样惯例不同，须按模块输出风格选采样窗。**
- RTL 定稿前自查修掉两处：漏 `ow_i` 端口（占位名未替换）；`ic_i` 初版
  8 位装不下 K2304 的 IC=256 → 改 16 位。

## 环境与复现

- ModelSim SE-64 10.1c（vsim 必须 `-c -novopt`）；
- 复现：`python addrgen_vecgen.py` → `vlog -work work ../../rtl/yolo_addrgen.v
  ../tb_yolo_addrgen.v` → `vsim -c -novopt +STIM=../stim/addrgen +WDT_MS=400
  -do "run -all; quit -f" work.tb_yolo_addrgen`（sim/msim 下）。

## 结论

M7 门通过。M10 集成注意：M9 X-DMA 以本模块 beat 流为地址/旁路源；
pad beat 不发起存储器读（DMA 侧按 pad_o 屏蔽）；Y 侧写出地址由
M8/M10 以 n_global = n_start + n_local 组合（y 平面 CHW 线性）。
