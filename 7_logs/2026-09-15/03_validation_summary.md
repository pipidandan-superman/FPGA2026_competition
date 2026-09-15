# 2026-09-15 验证摘要

## 当前：G3 M11 全网端到端门通过（2026-09-15，SIM-8×8 全 63 卷积）

**TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
head_bytes=149100 ldone=63 adone=1** + **M11_HEADCHK_PASS sha256=
9ce70525...（== run04 frame0，且 6 张量拆分对 npz 逐字节全对）**。
`sim/tb_yolo_fullnet.v`（TB 扮 PS 角色）+ `sim/m11_vecgen.py`（104 任务
微码程序 + 13.3MB DDR 镜像，三重生成期护栏）在 1 帧（golden_00=images89，
run04 权威）上跑通全网：63 conv 逐层 3,553,900 格零误差、写双射完备；
view/concat/add/maxpool5/upsample2 65 个 PS 微操作按 intarith 语义解释
执行（独立单元检查 M11_PSOP_UNIT_PASS 1152/1152）；**k1×1 几何首次上场**
（M0–M10 全 k3×3 从未覆盖）逐位通过。RTL 零改动（§5 重跑义务不触发）。
[M11 REPORT](../../4_metrics/logs/2026-09-15_yolo7020_m11_fullnet_run01/README.md)。

本批教训：① run01 假失败 = TB WDT 表达式 `#(wdt_ms*1_000_000)` 32 位
溢出（3.6e12 mod 2^32 = 817,405,952 ns 精确命中杀进程时刻；M10 的 9e8
从未触发）——**仿真器 delay 表达式同样受 32 位 integer 运算约束，大数
先升 64 位**；② view/切片类发射的 dst 不带源内偏移（输出缓冲只装切片，
通道偏移只加在 src——自检抓 PRNG 填充暴露）；③ 手写单元激励两次笔误
（漏 ln 操作数、nt 与 pair 数不符）都被 TB 的 opcode/长度校验当场抓住，
TB 解释器本身无误。门定义修正（128 帧 → 1 帧全节点 + head sha）与理由
已入基线 §8。

## 前一：G3 M10 阵列集成门通过（2026-09-15，M0–M9 全链集成）

**TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
ldone=6 adone=1**（run01 干净门首跑绿）：`rtl/yolo_gemm_array.v` 把
M1–M9 全链集成（ctrl V1.1 调度 + DMA + 双 bank + addrgen + PE 8×8 +
requant + LUT），6 层流 S1/R1/S2/S3/R2/S4 覆盖 oc 尾 {7,1}、n 尾 1、
K∈{27,64,576,2304}、act 旁路、first=1 pad−128、last/all_done、层间间隙
{4,0,3,0,6,2}；真实层 R1（model.0，409600 格）/R2（model.16，25600 格）
对 run04 权威链逐位一致。
[M10 REPORT](../../4_metrics/logs/2026-09-15_yolo7020_m10_gemm_array_run01/README.md)。

集成揪出 4 个 RTL bug + 2 个 TB 规则（全部失败链留证）：
① addrgen 端口位宽越界（装配致命，参数化零扩展）；
② loader 层边界 S_LCHK 挂死（下一层 ctrl 永等 tile_rdy，260ms 冻结态证明）；
③ oc_loc 解码降序覆盖循环（328608 双写+漏写，升序修复）；
④ **conv_core V1.2 越界部分选择**：`oc[P_AW-1:0]` 在 P_AW>OC_CW 时读 X
→ 黄金核整层 X；M0 旧用例恰好全 P_AW==OC_CW 从未触发——**M0 门重跑
run02 回归 11/11 同数 PASS（§5 义务履行，零行为变化）**
[REPORT](../../4_metrics/logs/2026-09-15_yolo7020_m0_conv_core_run02/README.md)。
TB 规则：黄金服务连续 assign（M0 TB 款）；哨兵 0xA5 歧义（L3 恰 4 格
DUT=黄金=0xA5）→ 双侧 0xA5 视为相等，完备性由写双射计数机器检查。
工具链新坑：ModelSim 10.1c `%0t` 打印的是**仿真分辨率单位（ps）**而非
模块 timescale 单位——本批一度误判时钟 10µs，tprobe.v 对照实验证伪。

## 前一：G3 M0–M9 单元门全部通过（2026-09-15 收批，M10 未动）

批次（M0→M9）10/10 门全绿，全部 Verilog-2001 .v，每门独立 run 目录
四件套（README/console_extract/原始 transcript/激励 manifest+sha256）：

| 门 | 模块 | 结果 | 过门跑数 |
|---|---|---|---|
| M0 | yolo_conv_core（参数化通用 conv） | TB_CONVGEN_PASS 11/11（含 conv0 golden 409600/409600 ×2） | 2（假绿教训） |
| M1 | yolo_pe_pack（DSP48E1 双 int8 打包） | TB_PE_PACK_PASS 10216/10216 + 2^24 穷举 0 失败 | 1 |
| M2 | yolo_acc（int32 累加、K 断点续累/清零） | TB_ACC_PASS 57936/57936 | 1（首跑绿） |
| M3 | yolo_wbuf（W 双 bank 字节矩阵 + 参数面） | TB_WBUF_PASS 98239/98239 | 3（黄金侧 2 bug） |
| M4 | yolo_xbuf（X 双 bank 列镜像 + im2col） | TB_XBUF_PASS 97464/97464 | 1（首跑绿） |
| M5 | yolo_requant（每通道 M/shift RNE） | TB_REQUANT_PASS 22493/22493 | 1（首跑绿） |
| M6 | yolo_silu_lut（双尺度 SiLU 5 表） | TB_LUT_PASS 1400/1400 | 1（首跑绿） |
| M7 | yolo_addrgen（im2col 地址 + pad 注入） | TB_ADDRGEN_PASS 67918/67918 | 2 |
| M8 | yolo_ctrl（tile/层调度 Moore FSM） | TB_CTRL_PASS 695092 周期 ×15 输出 | 2（黄金发射点） |
| M9 | yolo_dma（AXI4 读主 + 字节串化） | TB_DMA_PASS 210904 字节/33 命令/1666 AR | 5（真 RTL bug 1） |

M3–M9 七件本批新证据要点：**M3** 黄金模型数据/参数键空间分离 +
生成期宽度护栏（>128bit 拒绝）+ 未写地址不可读（interleave 读深钳到
前轮 klen）；**M4** 真 im2col 回归双路闭合（地址算术 vs np.pad 窗切
逐字节一致）；**M8** 23 层覆盖 15 K 档 + 5 N 档全集、尾部钳位、
bank 跨层连续翻转、单一 all_done；**M9** 8 条命令跨 4KB 逼出突发
切分（1666 AR 全部对齐/INCR/不跨界/地址链精确/无超取），随机停顿
下 21 万字节零差异。
[M9](../../4_metrics/logs/2026-09-15_yolo7020_m9_dma_run01/README.md) ·
[M8](../../4_metrics/logs/2026-09-15_yolo7020_m8_ctrl_run01/README.md) ·
[M7](../../4_metrics/logs/2026-09-15_yolo7020_m7_addrgen_run01/README.md) ·
[M6](../../4_metrics/logs/2026-09-15_yolo7020_m6_lut_run01/README.md) ·
[M5](../../4_metrics/logs/2026-09-15_yolo7020_m5_requant_run01/README.md) ·
[M4](../../4_metrics/logs/2026-09-15_yolo7020_m4_xbuf_run01/README.md) ·
[M3](../../4_metrics/logs/2026-09-15_yolo7020_m3_wbuf_run01/README.md)。

批次方法论沉淀（TB 惯例成文）：寄存输出统一 negedge 驱动 / posedge+#1
采样；**状态机黄金必须先 step 后发射**（后沿采样 ⇒ 后沿发射，M8 run1
全红即此）；流握手全部 posedge NBA 捕获；Verilog 保留字/优先级陷阱
（`edge` 形参、`!==` 结合紧于 `&`——M8/M9 各踩一次，掩码必须括号或
中间变量）；**独立数据进程不能挂 FSM case 分支**（M9 串化器重复交付
bug 根因）。

## 前一：M1 PE 双打包门通过（2026-09-15，PROD 档启用前提成立）

**TB_PE_PACK_PASS 10216/10216**（216 定向角点 + 10⁴ 随机）+ **2^24 全域
穷举 0 失败**：单 DSP48E1 承载 w·x[n]/w·x[n+1] 两路独立 int8 乘积的位域
方案成立。**关键发现**：架构基线 §3.2 字面布局（间隔 9'b0 + 直接位提取）
全域 74.6% 失败（负 x0 低通道差 256·w + 负低积高通道借位差 1）；符号
扩展间隔修正仍 49.8% 失败（负 x0 的 +2^17 正权污染高通道）；**采纳偏置
布局**（x0b=x0+128 MSB 翻转入低字节，lane0=$signed(P[16:0])−(w<<<7)、
lane1=$signed(P[33:17])+P[16]），数值合同不变、资源增量 ~2 个 17 位
加/DSP。§3.2 已按穷举证据修正。
[M1 REPORT](../../4_metrics/logs/2026-09-15_yolo7020_m1_pe_pack_run01/README.md)。

## 前一：M0 参数化通用 conv 核门通过（2026-09-15，G3 阵列基线第一门）

**TB_CONVGEN_PASS ×11/11**：`rtl/yolo_conv_core.v`（conv0 核推广为任意
IC/OC/K/stride/pad/PAD_VAL/HAS_ACT，数值路径逐位不变）——9 合成矩阵
（K∈{27,32,45,64,256,576,2304}、s1/s2、p0/p1、pad −128/0、act 有/无、
随机/极值/全零）+ conv0 真实 golden00/golden02 全量回归各 **409600/409600**
零差异。**本 run 的核心教训（假绿根因）**：run1 中 RTL K 分解 bug
（`k/KP` 应为 `k/(KH*KW)`，case0 221550/409600 错）被退化合成参数完全掩盖
（shift 1/2 → requant 输出常数化，9 合成例假 PASS）——同一错误 RTL 门绿而
真实回归红。修复双管齐下：RTL V1.1 分解公式 + 生成器 v2 反退化三原则
（通道角色表保证 ≥1 平局+≥1 现实域通道；现实域 bias~acc 幅值、shift 从
M/标度导出；δ∈{+1,−1,+3,+5} 精确 RNE 平局构造 + 确定性饱和通道 + 逐通道
distinct≥8 断言）。**合成激励输出必须"活着" + 真实数据回归，缺一不可。**
[M0 REPORT](../../4_metrics/logs/2026-09-15_yolo7020_m0_conv_core_run01/README.md)。

## 前一：PS 上板全量自检 + G3 conv0 数值门双通过（2026-09-15）

**PS_SELFCHECK_ONBOARD_HEAD_ONLY**：128 帧全量在真实 ARM PS（PYNQ 2.7/
numpy 1.21.5）上整网 head **128/128 位级一致**——量化整数合同在硬件上逐位
复现，G-PS 离线推理门通过。box 72/128，56 帧差异全部归因为 ARM/x86 libm
float64 ulp（3–5e-7）引起的近并列幸存者交换/并列行重排（受影响行均 conf≤0.01，
无框数/类别变化），计划 :219 容差内良性。45.34s/帧（纯 numpy 未优化，PC 参考
0.574s）。板端仅新增 /home/xilinx/yolo_selfcheck/，PL/服务/SD 未触碰。
[PS 上板 REPORT](../../4_metrics/logs/2026-09-15_yolo7020_ps_onboard_run01/REPORT.md)。

**G3_CONV0_RTL_SIM_PASS**：首层 conv RTL（rtl/yolo_conv0_core.sv，1 MAC/拍）
vs golden 双激励全量 **409600/409600 零差异**（golden00/golden02）。工具链教训：
本机 ModelSim 10.1c 设计优化阶段挂死 → **vsim 一律 `-novopt`**；10.1c 符号性
毒化 → **三目/拼接参与有符号运算必须 `$signed()`**（两 bug 各致 421/163 错后
归零）。[G3 REPORT](../../4_metrics/logs/2026-09-15_yolo7020_g3_conv0_rtl_sim_run01/README.md)。

## 前一：G2 量化整数参考门限通过（2026-09-15）

**G2_QUANT_INTREF_PASS**：valid FP32 mAP50 0.8939 → INT8 0.8763，drop +0.0176 ≤ 0.02（计划 r3 G2 门限）。逐层余弦 165 检查最差 0.9305；数值合同（W8A8、每通道 M+shift RNE、双尺度 SiLU LUT、首层 u−128 z 折叠）全程未变——方法演进只动校准。test split drop +0.0571（FP 基线仅 0.7255、npos 极少，未参与调参，如实报告；残余损失主因 valid Left −0.100 ≈1.4 框当量）。部署包 weights/bias/lut/quant+manifest 已复制 `2_fpga/3_yolo_zynq/rom_data/` 并逐字节哈希核对；golden（5 图全节点张量）与 128 帧回归为 G3 对齐源。[G2 REPORT](../../4_metrics/logs/2026-09-14_yolo7020_g2_quant_intref_run01/REPORT.md)。限制：LSQ 再拟合 ×6 轮会过收缩（+0.0344），×2 为选定平衡点；若需更高 test 裕量，后续单变量候选为偏置校正/QAT（计划第 17 行）。

## 补记：G1 FP32 基线（完成于 2026-09-14）

G1_FP32_BASELINE_PASS：640/416/320 三尺寸，320 较 640 valid mAP50 −0.0278（更高），G2 采用 320；420 图校准清单产出。[G1 REPORT](../../4_metrics/logs/2026-09-14_yolo7020_g1_fp32_baseline_run01/REPORT.md)。

## 待办交接

本批（M0–M9）收满，M10 集成未动（基线 §9 执行窗）。下一批 M10 起步
集成关注（各门 README 结论段已汇总）：ctrl S_RQ 相位按 rq_idx 平铺，
requant 尾段 (oc_local,n_local)=divmod(rq_idx,n_tail) 解码；W/X bank
由 rd_bank_o 直连（DMA 填非激活 bank = ~rd_bank）；acc 每拍需加 PE
lane0 −(w<<<7) / lane1 +P[16] 修正项；DMA out_* 直连 wbuf/xbuf 写侧
（或加写地址生成层），MAX_BURST=16 接 Zynq HP 口可重参到 64 拍，
单在途 AR 如成带宽瓶颈可加深 AR 流水。PR #8 仍在等队友审核。
