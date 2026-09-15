# 2026-09-15 yolo7020 M1 PE 双打包乘法 门（run01）

## 目标（架构基线 §3.2 / §5 M1）
验证 DSP48E1 双 int8 打包方案（单 DSP 承载同一 OC 行、相邻 2 个 N 列的
w·x[n] 与 w·x[n+1] 两路独立乘积，PROD-16×16 档 128 DSP 的启用前提）。
PASS token `TB_PE_PACK_PASS`，黄金 = Python 独立逐位模型。

## 结果

**TB_PE_PACK_PASS 10216/10216**（216 定向角点 + 10000 随机，两通道位级
零差异）+ **全域穷举证明 2^24 组 0 失败**。M1 门通过，PROD 档双打包假设
成立（资源：128 DSP + 每 DSP ~2 个 17 位 fabric 加法，仍在 §4 预算内）。

## 核心发现：基线 §3.2 字面方案对负操作数不成立（M1 门的职责所在）

对三种布局做独立 Python 位模型 + 2^24 全域穷举（结果在
`stim_manifest_pe_pack.json['exhaustive_proof_2p24']`）：

| 布局 | 定义 | 全域失败数 | 失败机理 |
|---|---|---|---|
| doc_literal（§3.2 字面） | A={x1,9'b0,x0}，P[15:0]/P[33:17] 直接提取 | **12517376/16777216 (74.6%)** | ① 负 x0 按无符号字节入 A：低通道差 256·w（x0=−128,w=−128 → −16384 vs +16384）② 负低积从高位域借 1：高通道差 1 |
| sext_gap（直觉修正①） | 间隔填 x0[7] 复制 | 8355840/16777216 (49.8%) | 低通道精确，但负 x0 的 17 位补码在低位域按**正权**计入，A 多出 +2^17 → 高通道被污染 w·[x0<0]（不可由 P 位恢复） |
| **bias（采纳）** | x0b=x0+128（MSB 翻转）入低字节、间隔 0；lane0=$signed(P[16:0])−(w<<<7)、lane1=$signed(P[33:17])+P[16] | **0/16777216** | 偏置使低字节真无符号；解偏置 = 减移位广播 w（纯线，无乘法器）；借位 = P[16] 恰为低位符号位，1 位加法回补 |

**数学要点**：有符号数无法不经偏置/污染嵌入宽操作数的低位域——低域位权
恒正，符号位只能落在操作数顶端。x0b=x0+128 使低字节值域 [0,255] 真无符号；
A = x1·2^17 + x0b 精确成立；|w·x0b| ≤ 127·255 = 32385 < 2^16 → P[16:0]
有符号 17 位提取无损；|w·x| ≤ 127·128 = 16256 → 输出 16 位载荷足够。
RTL（`rtl/yolo_pe_pack.v`）位域与该模型逐位一致。

数值合同不受影响（两路输出仍逐位等于 w·x 直乘）；后续优化可把 +128 偏置
折叠进 X tile 存储（同 8 位宽），模块接口保持"原始 int8 入、精确 w·x 出"。

## 试错记录（生成器侧）
首次穷举时三布局全失败——Python 位模型把 25 位 A 位型按**无符号正值**相乘
（最高位是符号位），修正为 `_signed_field(a,25)` 后 bias 布局归零。
与 RTL `$signed()` 铁律同源的坑，出现在模型侧。

## 环境
- ModelSim SE-64 10.1c，`vsim -c -novopt`；编译
  `vlog -work work ../../rtl/yolo_pe_pack.v ../tb_yolo_pe_pack.v`（sim/msim）。
- 运行：`vsim -c -novopt +STIM=../stim/pe_pack +WDT_MS=100 \
  -do "run -all; quit -f" work.tb_yolo_pe_pack`（DUT 组合路径，10216 向量
  单次运行 <1s 仿真时间）。
- 穷举证明：`python pe_pack_vecgen.py`（numpy 按 x0 分块向量化，~秒级）。

## 工件
- RTL：`2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v`（V1.0，文件头含布局推导）
- TB：`2_fpga/3_yolo_zynq/sim/tb_yolo_pe_pack.v`
- 生成器/黄金：`2_fpga/3_yolo_zynq/sim/pe_pack_vecgen.py`（seed 202 可复现）
- 激励：`2_fpga/3_yolo_zynq/sim/stim/pe_pack/`（5 hex + manifest）
- 证据：本目录 `console_extract.txt`、`sim_pe_pack.log`（原始 transcript）、
  `stim_manifest_pe_pack.json`（含穷举结论）、`stim_sha256.txt`

## 下一步（架构基线 §9）
M1 绿 → 并行推进 M2 累加器 / M5 requant / M6 LUT / M7 地址生成 +
M3 W tile / M4 X tile 缓冲；M10 集成时 PE 打包 × 累加器（fabric per-lane
int32 累加 + 每拍 lane0 减 w<<<7、lane1 加 P[16] 修正项）。
