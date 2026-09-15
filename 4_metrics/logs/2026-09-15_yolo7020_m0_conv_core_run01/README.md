# 2026-09-15 yolo7020 M0 参数化通用 conv 标量核 门（run01）

## 目标（架构基线 §5 M0 / §9 执行窗口）
`rtl/yolo_conv_core.v`：把门已过的 `yolo_conv0_core.sv` 推广为任意
IC/OC/KH/KW/IH/IW/stride/pad/PAD_VAL/HAS_ACT 的参数化通用核（数值路径逐位
不变），通过合成矩阵 + 真实 golden 回归，PASS token `TB_CONVGEN_PASS`。

## 结果（run2 = RTL V1.1 + 激励 v2）

| 用例 | 形状（IC/OC/K/IH×IW/s/p/pad/act/fill） | 比较 | 结果 |
|---|---|---|---|
| genE | 5/5/45/9²/s1/p0/0/act1/random | 245/245 | **TB_CONVGEN_PASS** |
| genF | 32/3/32/13²/s2/p0/0/act1/extreme | 147/147 | **TB_CONVGEN_PASS** |
| genG | 64/2/64/8²/s1/p0/0/act1/random | 128/128 | **TB_CONVGEN_PASS** |
| genCrand | 256/7/256/10²/s1/p0/0/act0/random | 700/700 | **TB_CONVGEN_PASS** |
| genCzero | 256/7/256/10²/s1/p0/0/act0/zero | 700/700 | **TB_CONVGEN_PASS** |
| genArand | 3/16/27/96²/s2/p1/−128/act1/random | 36864/36864 | **TB_CONVGEN_PASS** |
| genAext | 3/16/27/96²/s2/p1/−128/act1/extreme | 36864/36864 | **TB_CONVGEN_PASS** |
| genD | 256/4/2304/12²/s1/p1/0/act1/random | 576/576 | **TB_CONVGEN_PASS** |
| genB | 64/8/576/40²/s1/p1/0/act1/random | 12800/12800 | **TB_CONVGEN_PASS** |
| case0 | conv0 真实 golden00 全量 | 409600/409600 | **TB_CONVGEN_PASS** |
| case0b | conv0 真实 golden02 全量（交叉样本） | 409600/409600 | **TB_CONVGEN_PASS** |

覆盖：K ∈ {27,32,45,64,256,576,2304}（15 档中 7 档）、stride 1/2、
pad 0/1、PAD_VAL −128/0（首层 z 折叠/内层）、act 有/无、随机/极值/全零
填充、1×1 与 3×3 核、OH·OW 非整数倍输出。**11/11 全绿。**

## 环境
- ModelSim SE-64 10.1c（Jul 28 2012），`vsim -c -novopt`（10.1c 优化阶段
  挂死铁律，见 conv0 run01）；license `D:/work/modelsim/win64/LICENSE.TXT`。
- RTL/TB 编译：`vlog -work work ../../rtl/yolo_conv_core.v ../tb_yolo_conv_core.v`
  （于 `2_fpga/3_yolo_zynq/sim/msim`）。
- 批量执行：本目录 `run_all.sh`（逐例完整 vsim 命令行，含 -g 参数覆盖与
  +STIM/+CASE/+WDT_MS plusargs；case0b 为同命令行补跑，见其 log 头）。
- 主机 Windows 11 / Administrator；时间 2026-09-15 11:08–11:09（run2）。

## 失效-根因-修复过程（run1 → run2，本 run 的核心价值）

### run1（RTL V1.0 + 激励 v1）：假绿 + 真红
- 9 个合成例全 "TB_CONVGEN_PASS"，但 case0 真实回归
  `TB_CONVGEN_FAIL errors=221550/409600 first_lin=0 got=109 exp=87`。

### 根因 1（RTL）：K 分解除数错误
- `k_ic = k / KP`（KP=IC·KH·KW=27）应为 `k / (KH*KW)`（=9）：k<KP 时
  k_ic 恒 0，k≥9 的 tap 全部读错 x 平面/伪造 pad。
- 证据：debug TB 逐 tap dump，case0 k=13 处 DUT x_addr=960（=0 平面
  3·320+0，因 13/27=0、k_ih=13%27/3=4）vs 真值 102400（ic=1 平面）。
- 修复：`k_ic = k/(KH*KW); k_ih = (k%(KH*KW))/KW; k_iw = k%KW;`
  （RTL V1.1，修订记录在文件头）。

### 根因 2（激励）：合成 requant 参数退化 → 假绿
- v1 参数 shift∈{1,2,7,…}+全幅 int32 bias+31 位 M：n/2^s 要么 ≫2^7
  （整通道饱和成 ±127/−128 常数）要么 ≈0（shift 62 → 全 0）；全幅 bias
  主导 (acc+bias) 符号 → 输出与 acc 无关。**任何 MAC 错都被 requant 常数
  化掩盖。**
- 证据：同一 V1.0 RTL，修复定位期间重跑 genE 门仍 PASS 而 debug tap 明显
  错位（同 work 库同 session）——合成例对错误零检出，9 个 "PASS" 全部无效。
- 修复（synstim_gen.py v2，反退化三原则 + 通道角色分配）：
  1. 通道角色表 `channel_plan(OC)`：任意 OC≥2 必含 ≥1 平局 + ≥1 现实域
     通道（首个现实域通道 target∈[80,120] 高中心 → 确定性覆盖饱和沿），
     OC≥4 补足 4 类平局，OC≥6 末通道为确定性饱和通道；
  2. 现实域通道 bias 幅值 ~acc_abs_typ、M∈[2^28,2^31)、
     s=round(log2((typ+|bias|)·M/target))——q 中心 ≤170、散布 ≈5×中心，
     天然 ≥8 个 LSB 档（生成器内逐通道断言 distinct≥8）；
  3. 平局通道 δ∈{+1,−1,+3,+5}、M=+2^30、s=31、bias=δ−acc[p*]：构造像素
     n=δ·2^30 精确落在 q=+0.5/−0.5/+1.5/+2.5 非饱和 RNE 平局点，分别
     暴露 half-up/截断/偶保持缺失；构造后反验 n mod 2^s == 2^(s-1)；
  4. 生成器内断言：tie≥1、sat≥1、各现实域通道 distinct≥8、y distinct≥8
     （zero 填充豁免）、numpy im2col ↔ 纯 Python naive 抽点一致才落盘。
- run2 实测覆盖：tie 32–4575、sat 75–13315、y_distinct 27–164（zero 例 4）。

### 教训（写入生成器文件头，适用于 M1–M9 所有合成激励）
**合成激励的 requant 参数必须让输出"活着"（q 中心有界 + 散布 ≥ 数十
LSB + 专门平局/饱和通道），否则 PASS 无检出力；假绿的合成例 + 真实数据
回归两者缺一不可。**

## 工件
- RTL：`2_fpga/3_yolo_zynq/rtl/yolo_conv_core.v`（V1.1，含修订记录）
- TB：`2_fpga/3_yolo_zynq/sim/tb_yolo_conv_core.v`（参数化，-g 覆盖）
- 生成器：`2_fpga/3_yolo_zynq/sim/synstim_gen.py`（v2；种子 101–109 可复现）
- 激励：`2_fpga/3_yolo_zynq/sim/stim/gen*/`（bin+hex+manifest）+
  `conv0_golden{00,02}`（golden_extract.py 三方自检，见 conv0 run01）
- 证据：本目录 `console_extract.txt`、`sim_*.log`（run2 原始 transcript）、
  `stim_manifests/`（11 份 manifest 副本）、`stim_sha256.txt`（165 文件）、
  `tool_probe/`（字符串 plusargs/$clog2/-do 引号工具探针）、
  `invalid_run1_degenerate_params/`（run1 全部失效 transcript，bug 证据保留）
- 仿真库：`2_fpga/3_yolo_zynq/sim/msim/work`
- 临时 debug TB（tb_dbg_firstpix.v/tb_dbg_taps.v）已在定位完成后删除，
  其关键输出摘录在本 README 根因 1 段。

## 下一步（架构基线 §9 执行顺序）
M1 PE 双打包乘法门（`yolo_pe_pack.v` + `TB_PE_PACK_PASS`，Python 逐位
模型黄金）；随后 M2/M5/M6/M7 数值链 + M3/M4 缓冲并行。
