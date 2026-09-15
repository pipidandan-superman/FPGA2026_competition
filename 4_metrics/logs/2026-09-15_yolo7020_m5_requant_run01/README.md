# M5 requant 门 run01 — yolo_requant（2026-09-15）

## 结果：TB_REQUANT_PASS（首跑全绿，CLOSED）

22493/22493（逐向量比对 y_pre 黄金 + vld_o==en 检查，零失配）。

## 工件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_requant.v` V1.0 |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_requant.v` V1.0 |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/requant_vecgen.py`（seed 505） |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/requant/`（acc/bias/m/shift/en/ypre_exp + manifest） |
| 本目录 | console_extract.txt / sim_requant.log / stim_manifest_requant.json / stim_sha256.txt（8 文件） |

## 合同（架构基线 §3.2 数值合同）

`sum_b = acc + bias_eff`（33b 有符号）；`n = sum_b·m`（int64 精确，
|n| < 2^63）；`y_pre = sat_i8(rne_shift(n, shift))`，shift ∈ [0,62]，
RNE ties-to-even。rne_shift/sat_i8 自 yolo_conv_core.v（V1.1，
TB_CONVGEN_PASS）原样提取，与 pynq/intarith.py（G2 位级合同）逐位一致。

**域约定**：m ≠ INT32_MIN（|sum_b| ≤ 2^32 下其余一切 m 保证 |n| < 2^63
不回绕；真实模型 M ∈ [2^30, 2^31) 恒正，负 rail 属对抗覆盖，
±(2^31−1) 已含）。en=0 保持 y_pre；vld_o = en 打一拍。

## 激励设计（五段，反退化纪律）

| 段 | 内容 | 实测覆盖 |
|---|---|---|
| T | 平局构造 n = q·2^s ± 2^(s−1)，因式分解 m=2^k 落 (acc,bias) 对；s∈{1,2,3,5,30,31,32,40,53,62}，q 绕 0/±rail | 平局 161(q 奇)/168(q 偶) |
| S | 饱和轨：m=1 定向 k·2^s 绕 ±127/±128 环带 + RNE 恰滚入轨（127·2^s+2^(s−1) 平局→128→截 127 等）+ m=±(2^31−1) 大乘积轨 | sat 事件 17901，y_pre=127 共 8978、−128 共 8968 |
| C | (acc,bias) ∈ {±MIN,±MAX,0} × m 七种 × s∈{0,31,62} | 和/积角点全覆盖 |
| R | **真实回归**：golden00/02 真实 x/w 重算 acc + 真实 bias_eff/m/shift（shift∈[39,43]），intarith 得 y_pre，断言 LUT[y_pre+128]==真实 y_exp（真实链闭合） | 2048 点，闭合 PASS |
| X | 全域随机 20000（m 七成 [2^30,2^31)，shift 加权，5% en=0 保持） | hold 1028，y_pre distinct 209 |

黄金参照 = pynq/intarith.py 的 rne_shift + sat_i8（基线 M5 验证要求）。

## 发现（黄金模型语义注记，非 bug）

`q = n>>s` 为 floor，`rem = n−q·2^s` 恒 ∈ [0, 2^s)——intarith 中
`twice < −full` 分支为死代码，"负平局"在 floor 语义下不存在；平局分类
按 q 奇偶计（round 方向）。初版 vecgen 按 rem 正负断言而触发（修正后
通过），此注记已写入 vecgen 文档串。

## 环境与复现

- ModelSim SE-64 10.1c（vsim 必须 `-c -novopt`；`-do "run -all; quit -f"` 引号）；
- 复现：`python requant_vecgen.py` → `vlog -work work ../../rtl/yolo_requant.v
  ../tb_yolo_requant.v` → `vsim -c -novopt +STIM=../stim/requant +WDT_MS=400
  -do "run -all; quit -f" work.tb_yolo_requant`（sim/msim 下）。

## 结论

M5 门通过。M10 集成注意：本模块输出 y_pre 为激活前值；LUT 索引
（y_pre+128）与查表由 M6 yolo_silu_lut 承担。
