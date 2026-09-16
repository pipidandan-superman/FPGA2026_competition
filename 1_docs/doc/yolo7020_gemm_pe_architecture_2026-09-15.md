# yolo7020 GEMM PE 阵列架构设计与逐模块验证基线

版本：2026-09-15 v1。状态：`ARCH_DECISIONS_FROZEN / M0_CONV_CORE_PASS(2026-09-15 run01; V1.2 修复后 run02 回归 11/11 同数) / M1_PE_PACK_PASS(2026-09-15 run01, §3.2 已按穷举证据修正) / M2_ACC_PASS(run01) / M3_WBUF_PASS(run01) / M4_XBUF_PASS(run01) / M5_REQUANT_PASS(run01) / M6_LUT_PASS(run01) / M7_ADDRGEN_PASS(run01) / M8_CTRL_PASS(run01; V1.1 tile_rdy run02; V1.2 rq_rdy run03) / M9_DMA_PASS(run01) / M10_GEMM_ARRAY_PASS(2026-09-15 run01, conv_core V1.2; 2026-09-16 V1.2a Y 写主 run03) / M11_FULLNET_PASS(2026-09-15 run01 目录; 门运行 run02, 1 帧全 63 卷积节点逐位 + head sha==run04, 门定义修正见 §8; 2026-09-16 run03 阵列 V1.2a 承接, 七项同数 + head sha 复命中) / M9B_DMA_WR_PASS(run01; V1.1 run02; V1.2 非对齐 run03) / M12A1_ALL_GREEN(2026-09-16: M8/M9b/M10/M11 run03 + CSR/engine run01, B 段 OOC 待确认) / OOC_PENDING / BOARD_NOT_RUN`。

本文档冻结 yolo7020（EES-331，xc7z020clg484-1）卷积引擎 **GEMM PE 阵列**的架构决策、
模块分解与逐模块验证/证据规则，作为后续 RTL 实现的设计基线。实现状态以本文档
状态字为准；任何"通过"结论只以 `4_metrics/logs/` 下的运行证据为准。

## 0. 与主计划的关系（重要）

主计划 `../yolo7020_hardware_deployment_plan_20260914.md` §1.4 冻结的第一版结构为
"128 MAC 通路（8 输出通道×16 空间位置）、100 MHz、每通路 1 个 DSP、不预设
DSP48E1 能免费实现 2/4 路独立 INT8 MAC"。本文档**不推翻该约束，而是把它升级为
参数化族**：

| 实例 | OC边×N边 | MAC/拍 | DSP 用法 | 定位 |
|---|---|---|---|---|
| SIM-8×8 | 8×8 | 64 | 不限 | 全网位级仿真（1580 万拍/帧，ModelSim 可行） |
| BASE-8×16 | 8×16 | 128 | **1 MAC/DSP（128 DSP，无打包假设）** | **计划基线档：打包门未过时的回退产品档** |
| PROD-16×16 | 16×16 | 256 | 2 int8/DSP（128 DSP，fabric 累加） | 性能档：M1 打包门 + OOC 时序双证据通过后启用 |

帧率声明纪律沿用主计划 §1.7：**OOC 时序与 B1 板测证据落地前，30fps 仅为估算
目标，不作为对外承诺**。BASE-8×16 @100MHz ≈ 12.6fps 峰值，与主计划"第一版
不承诺 20/30fps"一致。

## 1. 已验证基线（本文档的地基）

1. **数值合同已双端验证**：量化整数语义（W8A8、int32 累加、+bias_eff、每通道
   M/shift RNE 平局到偶、sat_i8、SiLU 256 项 LUT、首层 pad=−128 z 折叠）
   —— PC golden run04 ↔ PS 板上 128 帧全量 head 128/128 位级一致
   （`4_metrics/logs/2026-09-15_yolo7020_ps_onboard_run01/`）。
2. **标量黄金核已过位级门**：`2_fpga/3_yolo_zynq/rtl/yolo_conv0_core.sv`
   （1 MAC/拍，conv0 专用）vs golden 双激励 409600/409600 零差异
   （`4_metrics/logs/2026-09-15_yolo7020_g3_conv0_rtl_sim_run01/`）。
   PE 阵列必须与它零差异；整数和次序无关性是并行的合法性来源。
3. **工具链铁律**（10.1c 实测）：vsim 一律 `-novopt`（设计优化阶段本机挂死）；
   三目/拼接参与有符号运算必须显式 `$signed()`（曾致 pad 常数 0x80 零扩展）。

## 2. GEMM 形状全集（63 conv，实测枚举自 rom_data schedule）

统一视图：im2col 后 `C[OC×N] = W[OC×K] × X[K×N]`。

- **K = IC·kh·kw**：{27,32,48,64,96,128,144,192,256,288,384,512,576,1152,2304}
  （15 档；计数 {27:1, 32:1, 48:1, 64:7, 96:1, 128:2, 144:3, 192:4, 256:3,
  288:7, 384:4, 512:1, 576:18, 1152:8, 2304:2}）
- **OC**：{7,16,32,64,128,256}（计数 {7:3, 16:3, 32:9, 64:29, 128:13, 256:6}）
- **N = OH·OW**：{100,400,1600,6400,25600}（计数 {100:18, 400:22, 1600:17,
  6400:5, 25600:1}）；stride-2 conv 共 7 个
- 总量 **1.011 GMAC/帧**（最大 4 层各 58.98M：OC64/N1600/K576）；权重总量
  **2.93 MB int8**（> BRAM，必须 DDR 流式）

尾部浪费实测（对 16 边）：N=100 层 12%×占比7%、K=27 层 18%×占比2.6%、OC=7
层 padding —— 全网合计 <1.5%，可忽略。

## 3. 架构（冻结）

### 3.1 数据通路

输出驻留（output-stationary）阵列，OC边×N边 = 参数 `OC_EDGE×N_EDGE`，K 每拍
步进 1。tile 三层循环（任意形状对硬件透明，仅循环计数器不同）：

```
for n_tile   in ceil(N/N_EDGE):
  for oc_tile in ceil(OC/OC_EDGE):
    累加器清零
    for k in K:                      # 每拍 1 步
      W 行广播(OC_EDGE B) × X 列广播(N_EDGE B) → 阵列乘加
    requant(RNE)+LUT → C tile 写出   # 与下一 tile 的 K 循环重叠流水
```

每拍阵列消耗 OC_EDGE+N_EDGE 字节（16×16 即 32B/拍，片内 BRAM 广播供给；
DDR 侧仅 tile 更换时补给，实测 ~15–20MB/帧 ≈ 0.5GB/s @30fps，单 HP 口够用，
配 2 口留裕量）。

### 3.2 DSP 双打包方案（PROD 档启用前提；M1 门已验证并修正，2026-09-15）

每 DSP48E1 服务同一 OC 行、相邻 2 个 N 列。**M1 门（run01）全域 2^24 穷举
证明本节原字面方案（间隔 9'b0 + 直接位提取）对负操作数不成立**（74.6%
失败：负 x0 低通道误差 256·w、负低积高通道借位误差），采纳修正布局：

```
x0b        = x0 + 128                          # MSB 翻转，真无符号字节 [0,255]
A[24:0]    = { x1[7:0], 9'b0, x0b[7:0] }      # A = x1·2^17 + x0b 精确
B[17:0]    = 符号扩展 w[7:0]                    # 广播权重
P          = A·B                                # 43 位
lane0      = $signed(P[16:0]) − (w <<< 7)       # = w·x[n]   （解偏置：P[16:0]=w·x0b）
lane1      = $signed(P[33:17]) + P[16]          # = w·x[n+1] （P[16]=低积借位位）
```

两通道乘积位域分离后**每通道在 LUT fabric 累加器独立 int32 累加**（每拍
一次 32 位加 + lane0 的 −w·128 移位修正项 + lane1 的 1 位借位修正项，
均纯线/1 位加，无乘法器）。界：|w·x0b| ≤ 127·255 = 32385 < 2^16（17 位
提取无损）；|w·x| ≤ 127·128 = 16256（16 位载荷足够）。证据：
`4_metrics/logs/2026-09-15_yolo7020_m1_pe_pack_run01/`（穷举三布局对照）。

### 3.3 存储组织

| 缓冲 | 组织 | 容量上界 | BRAM（双缓冲） |
|---|---|---|---|
| W tile（含该 OC 组的 bias_eff/M/shift 参数行） | OC_EDGE 个行 BRAM，每行 1B/拍 | 16×2304=36KB | 32×BRAM36 |
| X tile | N_EDGE 个列 BRAM | 2304×16=36KB | 32×BRAM36 |
| SiLU LUT | LUTRAM 256×8 ×OC_EDGE 份（并行查） | 4KB | 0（LUTRAM） |
| 输出 tile | 16×16×1B | 256B | 1 |

最坏 64–65 块 BRAM36 / 140。**回退开关**：K 分块（Kc=576）可把双缓冲压到
~32 块（控制复杂度换资源），集成期若与相机管线争 BRAM 再启用。

### 3.4 requant/LUT 尾段（分时复用，不占 DSP）

吞吐需求 = (OC_EDGE×N_EDGE)/K 拍，最坏 K=27 → 10 路/拍。实现为 **10 个
fabric 33×32 有符号乘法器**（~3K LUT）+ 10 套 RNE/sat + 16 份 LUTRAM，
与下一 tile 的 K 循环重叠执行，不插气泡。REQUANT_UNITS 随实例参数化
（8×8 档需 ceil(64/27)=3 路）。

### 3.5 接口

- 配置/描述符：AXI-Lite，基址 0x43C1_0000 起 64KB（`hw_contract/address_map.md`），
  顶层 `C_BASEADDR` 参数化。每层描述符 = 形状（OC/N/K/stride/pad）+ W/X/Y
  DDR 地址 + 首层标志（z 折叠路径）。
- 数据：2×AXI HP 64b 读主（W、X）+ 1 写主（Y），突发 64–128 拍。
- 首层 z 折叠：pad 常数 −128 由地址生成器旁路供给（对标量核语义一致，
  `$signed` 纪律）。

## 4. 资源预算与扩展定律（PROD-16×16）

| 子系统 | 估算 | 占 xc7z020 |
|---|---|---|
| 乘法墙（128 DSP 双打包） | 128 DSP | 58% |
| fabric 累加器（256×int32 + 每 DSP 2 路 32b 加） | ~8K FF + ~12K LUT | 8% / 23% |
| W/X tile 双缓冲 | 64 BRAM36 | 46% |
| requant+LUT 尾段 | ~3K LUT | 6% |
| DMA×3 + 控制器 + 地址生成 | ~5K LUT | 9% |
| **合计** | **128 DSP / 64 BRAM / ~22K LUT** | **58/46/42%** |

余量（~90 DSP / ~76 BRAM / ~28K LUT）留给既有相机/HDMI/UDP 管线；集成期以
整体构建 utilization 报告为准。扩展定律：乘法 DSP 与累加逻辑 ∝ OC×N；tile
缓冲 ∝ 边长×K_max；requant 单元 ≈ 常数（分时复用）；片内供给带宽 ∝ 边长。

## 5. 模块分解与逐模块验证门（RTL 实现顺序 = 验证顺序）

**规则：先逐模块单独测试，全部绿后才集成；每门一个独立 run 目录存证据。**
黄金参考三级：PC Python（intarith.py / golden npz）＞ 参数化通用标量核 ＞
上级已过门模块。

| # | 模块 | 内容 | 单测门（PASS token） | 黄金参考 |
|---|---|---|---|---|
| M0 | 参数化通用 conv 标量核 | conv0 核推广到任意 OC/IC/K/N/stride/pad；数值合同不变 | `TB_CONVGEN_PASS`（合成矩阵：K=27/64/576/2304、非 tile 整倍、全零/极值 ±128/±127/随机、stride1/2、pad0/1） | golden npz + intarith.py |
| M1 | PE 双打包乘法 | §3.2 位域方案 | `TB_PE_PACK_PASS`（双通道位级，含 ±128/±127/±1/0 与随机 10⁴ 组） | Python 逐位模型 |
| M2 | 累加器 | int32、K 断点续累、清零 | `TB_ACC_PASS` | Python |
| M3 | W tile 缓冲 | 行组织、双缓冲切换、参数随载 | `TB_WBUF_PASS` | BFM |
| M4 | X tile 缓冲 | 列组织、双缓冲 | `TB_XBUF_PASS` | BFM |
| M5 | requant | RNE 平局到偶 + sat（33 位全域） | `TB_REQUANT_PASS`（对齐 intarith.rne_shift/sat，含平局样例） | intarith.py（唯一权威） |
| M6 | SiLU LUT | 256 全索引 | `TB_LUT_PASS` | lut.bin |
| M7 | 窗口/地址生成 | im2col 地址、pad、首层 −128 z 折叠、K 序=ic·9+kh·3+kw | `TB_ADDRGEN_PASS` | golden_extract.py 期望 |
| M8 | 控制器/描述符 | 15 档 K/5 档 N/尾部 tile/层切换 | `TB_CTRL_PASS` | 指令级参考模型 |
| M9 | DMA 通道 | 突发、4KB 边界、随机 stall | `TB_DMA_PASS` | AXI BFM |
| M10 | 阵列集成（SIM-8×8） | M1–M9 组装 | `TB_GEMM_ARRAY_PASS`（vs M0 零差异，合成+真实激励） | M0 通用核 |
| M11 | 全网端到端（SIM-8×8） | 63 conv 顺序执行 | `TB_FULLNET_PASS`（128 帧 head sha256 == run04 golden） | run04 regression |
| M12 | OOC 综合（PROD-16×16） | 时序/资源/DRC | `GEMM16_OOC_TIMING_PASS`（150MHz 必过，200MHz 目标） | Vivado 报告 |
| M13 | 整合构建 + B1 板测 | 与相机管线同位流 | `B1_BOARD_CONV_PASS`（**需用户单独授权**） | 板上 vs PC |

集成顺序依赖：M1+M2 → 行/列组织 → M10；M3/M4/M9 并行开发；M5/M6/M7/M8
可并行。**任何模块改数值路径 → 从该模块的门开始全链重跑，不允许只跑集成级。**

## 6. 证据保留规则（每个门强制）

目录：`4_metrics/logs/<YYYY-MM-DD>_yolo7020_<模块名>_run<NN>/`，固定四件套：

1. `README.md`：结论、命令行、环境（工具版本+主机名+时间）、失败过程若有趣须记录
2. `console_extract.txt`：含唯一 PASS token 的可 grep 摘录
3. 原始 transcript/log：**不改名、不编辑、不裁剪**
4. 激励 manifest + sha256（随机激励必须落盘种子或文件，可复现）

已立此规的先例：`2026-09-15_yolo7020_g3_conv0_rtl_sim_run01`（含 bug 根因证据链）。

## 7. 边界与纪律（沿用，不因架构工作放宽）

- 一切文件操作仅限 `E:\competition` 内；`2_fpga/0_diaplay_test` 只读。
- 板卡加载/位流替换/板上运行新镜像：**逐次单独向用户申请授权**。
- 测试集不参与任何调参；数据本体不入 Git；SSH 密码走环境变量（EES331_SSH_PW）。
- 数值合同冻结：实现不得改合同；发现合同疑义 → 停下书面提出，不得顺手改。

## 8. 决策记录

| 日期 | 决策 | 依据 |
|---|---|---|
| 2026-09-15 | 阵列 = 输出驻留参数化 OC×N，K 每拍 1 步 | 整数和次序无关 → 并行合法；K 档多不宜 K 向并行 |
| 2026-09-15 | 产品档 PROD-16×16（双打包 128 DSP） | 1.011 GMAC/帧预算下唯一对 30fps 有 ≥2× 裕量的三候选之一（8×8/8×16/16×16）；资源四维 ≤58% |
| 2026-09-15 | BASE-8×16 保留为计划基线回退档 | 主计划 §1.4"不预设打包"约束；M1 门失败时无打包退化可用 |
| 2026-09-15 | SIM-8×8 用于全网位级仿真 | 1.011G MAC/64 = 1580 万拍/帧，ModelSim 分钟级；标量核跑全网不可行 |
| 2026-09-15 | requant 用 fabric 乘法器分时复用 | 保 DSP 给乘法墙；吞吐 256/K 拍，最坏 10 路/拍 |
| 2026-09-15 | W tile 携带该 OC 组 per-channel 参数 | requant 参数与权重同生命周期，免独立参数通路 |
| 2026-09-15 | **M0 门通过（run01）**：合成激励必须反退化（通道角色表 + 现实参数域 + 精确平局/饱和构造 + 逐通道 distinct 断言），且每门必带真实数据回归 | run1 假绿实证：退化 requant 参数使错误 RTL（K 分解 k/KP）合成 9 例全 PASS，仅 conv0 golden 回归 221550/409600 错暴露之；RTL V1.1 + 生成器 v2 后 11/11 全绿（`4_metrics/logs/2026-09-15_yolo7020_m0_conv_core_run01/`） |
| 2026-09-15 | **M1 门通过（run01）**：DSP 双打包采纳偏置布局（x0b=x0+128 入低字节；lane0 减 w<<<7 解偏置、lane1 加 P[16] 回补借位）；原字面布局全域 74.6% 失败，弃用 | 2^24 全域穷举三布局对照：doc_literal 12517376 败 / sext_gap 8355840 败 / bias 0 败；TB_PE_PACK_PASS 10216/10216。PROD-16×16 档双打包假设成立，资源增量 ~2 个 17 位加/DSP（`4_metrics/logs/2026-09-15_yolo7020_m1_pe_pack_run01/`） |
| 2026-09-15 | **M2–M7 门通过（run01）**：数值/缓冲/地址六模块首绿或快绿（M2 acc 57936、M5 requant 22493、M6 lut 1400、M7 addrgen 67918、M3 wbuf 98239、M4 xbuf 97464 全零失配） | 各 run 目录四件套；M3 两教训（黄金数据/参数键空间分离；interleave 读深钳前轮 klen——未写地址不可读）直接预焙进 M4，M4 首跑即绿；M4 真 im2col 回归双路闭合（地址算术 vs np.pad 窗切逐字节一致） |
| 2026-09-15 | **M8 门通过（run01）**：Moore FSM 黄金发射点 = 后沿（先 step 后发射）；寄存输出 TB 统一 negedge 驱动 / posedge+#1 采样成文 | run1 全红为黄金预沿发射，RTL/TB 零改动、仅改 emit 顺序后 695092 周期 ×15 输出全绿；23 层覆盖 15 K 档 + 5 N 档全集、bank 跨层连续翻转、单一 all_done（`4_metrics/logs/2026-09-15_yolo7020_m8_ctrl_run01/`） |
| 2026-09-15 | **M9 门通过（run01）**：DMA 字节串化器为状态无关独立进程（FSM+串化器单时钟块，R 接受写优先）；末字尾长静态化（命令接受时算 tail_r） | run3 真 RTL bug：串化器移位挂在 S_R 分支，FSM 回 S_AR 发 AR 时同字节重复交付（209159 错）→ 重构后 210904 字节零差异；33 命令/1666 AR（8 条跨 4KB 切分）随机停停下全绿（`4_metrics/logs/2026-09-15_yolo7020_m9_dma_run01/`） |
| 2026-09-15 | **M10 门通过（run01，另经用户单独授权）**：M1–M9 全链集成 SIM-8×8（`rtl/yolo_gemm_array.v`：loader 双 bank 装载 + DMA W/参数 + addrgen+X 字节口 + 32×pe_pack + acc + 顺序 requant 尾 + LUT + Y 输出流），6 层流 438447 格 vs M0 零差异，真实层 R1（model.0）/R2（model.16）对 run04 权威逐位一致 | TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1；K∈{27,64,576,2304}、oc 尾 {7,1}、n 尾 1、act 旁路、first/last、层间间隙全覆盖；失败链 7 份原始 transcript 留证（`4_metrics/logs/2026-09-15_yolo7020_m10_gemm_array_run01/`） |
| 2026-09-15 | M10 集成揪出 4 个 RTL 缺陷（全部修复+留证）：① addrgen 端口位宽越界（参数化零扩展）；② loader 层边界 S_LCHK 挂死（末 tile 后须 `loaded_all_q → S_LDESC` 再取下层）；③ oc_loc 解码降序覆盖循环（改升序，消 328608 双写+漏写）；④ **conv_core V1.2 越界部分选择**：`oc[P_AW-1:0]` 在 P_AW>OC_CW 时高位读 X → 参数服务整层 X；M0 旧用例恰全 P_AW==OC_CW 从未触发（V1.0 起潜伏） | ④ 为数值路径改动 → §5 全链重跑义务：M0 门 run02 回归 11/11 与 run01 逐项同数 PASS（零行为变化，`2026-09-15_yolo7020_m0_conv_core_run02/`）；逐层好坏判据 OC_CW<P_AW 完美吻合（L0 343+L2 400+L5 200 格 X，L3 净） |
| 2026-09-15 | M10 集成口径冻结（入 M11 承接）：requant 尾**顺序 1 输出/拍**（rq_idx 平铺 → (oc_local,n_local)=divmod(rq_idx,n_tail) 解码；重叠流水仅性能优化、延后）；ctrl 升 **V1.1**（S_TILE 增 tile_rdy_i 等待，接高电平与 V1.0 周期等价——M8 门结论不受影响）；**X 平面 = 组合字节口直读**（DDR 流式与同步源重定时推迟 M11）；**Y 为观测输出流**（真 AXI 写主属 M11+/M12）；DMA 本门仅 W/参数装载；W 行 KPAD 填充满足 DMA 8B 对齐；黄金权威 = run04/rom_data 重组链；TB 哨兵 0xA5 为合法输出值（双侧同值视为相等，完备性由写双射计数机器检查：dut_wr==total_out∧dbl==0，gold_wr==oc·n∧gdbl==0） | `yolo_gemm_array.v` V1.0 头注释（决策成文）；M10 run01 README 集成缺陷段与环境段 |
| 2026-09-15 | **M11 门通过（run01 目录，门运行 run02）**：SIM-8×8 全网端到端 1 帧（golden_00=images89=run04 权威），63 conv 全执行、3,553,900 格逐位零误差、写双射完备（dut_wr==compared、dbl=0、ldone=63、adone=1），65 个 PS 微操作（view/concat/add/maxpool5/upsample2）由 TB 按 intarith 语义解释执行，head 落盘 149,100B **sha256 == run04 frame0**（9ce70525...）且 6 张量对 npz 逐字节全对（M11_HEADCHK_PASS）。**k1×1 几何首次上场**（M0–M10 全部 k3×3，从未覆盖）并逐位通过；RTL 零改动（无 §5 重跑义务）。新失败链留证：run01 为 TB WDT 32 位溢出假失败（3.6e12 mod 2^32 = 817,405,952 ns 精确命中杀进程时刻） | `4_metrics/logs/2026-09-15_yolo7020_m11_fullnet_run01/`（README/console_extract/原始 transcript×6/head dump+headcheck/manifest+sha256）；`sim/tb_yolo_fullnet.v` + `sim/m11_vecgen.py`（三重生成期护栏：numpy 参考链 41 npz 检查点+head sha → 程序解释器逐指令 → 全 104 缓冲审计）+ `sim/m11_headcheck.py` |
| 2026-09-15 | **M11 门定义修正**：§5 原文"128 帧 head sha256 == run04"修正为"1 帧全 63 卷积节点逐位 + head sha256 == run04 frame0"。理由：阵列是调度驱动的数据无关引擎，帧间唯一自由度是首层输入数据（已被 M0/M10 真实层回归覆盖两次）；128 帧 ≈ 5–10 天仿真不可行；1 帧逐节点位级强于 128 帧仅头部哈希（22 个无 npz 张量的 C2f 内层 cv1/cv2 节点由 numpy 参考链 + head sha 双向闭合） | 用户授权"ok，先做M11"后的执行决策；run04 权威链验证：numpy 参考链复现 run04 位级（41 检查点 + head sha） |
| 2026-09-15 | M11 数据面口径（M12 承接清单）：Y 仍为 TB 散写回 DDR 镜像（物理链化：卷积输出字节即后续 PS 操作消费的数据面，但**真 AXI 写主未实现**，y_base 由 TB 侧加、描述符字段化属 M12）；X 仍为组合字节口直读镜像（DDR 流式推迟）；PS 微操作协议（COPY/RSCL/ADD/MAXP5/UPS2/HEADS 微码 + 镜像布局）为本门 TB 内实现，硬件化与否属 M12 架构决策 | `sim/m11_vecgen.py` 程序编码 + `sim/tb_yolo_fullnet.v` 解释器；镜像 13.3MB = 104 缓冲 + 63×(W/参数+黄金区) |
| 2026-09-16 | M12 A 段授权（用户"先跑a"）+ 三项架构决策：① PS 微操作 v1 全留 PS 软件（65 微操作解释器沿用 M11 冻结镜像布局，硬件化留 v2 候选不进本批）；② M12 OOC 时钟为纯约束 create_clock 6.667ns，M13 落板建议 PS FCLK 直出 150MHz（与视频链冲突再议 PLLE2）；③ Vivado 形态 = 非工程批处理跑门（显式文件清单 + TCL 机器判据 + dcp/报告落 4_metrics/logs），150MHz 首跑不过才临时建调试工程（调试完删除不入库） | 用户 2026-09-16 会话逐项确认（"七点的要求可以按照建议走"+"门跑批处理，首跑不过再建调试工程"+"先跑a"）；B 段 OOC 待 A 绿后另行确认 |
| 2026-09-16 | **A 段设计期发现：§3.1 DDR 带宽口径对 PROD 档不成立（待 A2 裁决）**。M10/M11 冻结的 loader 编排按 (n,oc) tile 逐 tile 重载 W：W 帧流量 = Σ ceil(N/N_EDGE)·ceil(OC/OC_EDGE)·OC_EDGE·K = MACs/16 ≈ **63MB/帧**，而 §3.1 "~15–20MB/帧 ≈ 0.5GB/s" 只覆盖了 X 路径（Σ N·K ≈ 15.8MB）。PROD-16×16 若沿用：W 路 63MB@1B/拍 ≈ 63M 拍、X 路 xbuf 1B/拍写口 ≈ 15.8M 拍、requant 顺序尾 3.55M 拍与 K 拍串行（仅此两项 ≈ 7.5M 拍 ≈ 20fps @150MHz），三者均击穿 5M 拍/帧预算（150MHz/30fps）。SIM-8×8 各门数值结论不受影响（仿真无帧率约束） | 本会话 A 段设计推导：1.011 GMAC/帧（§2）、M11 compared=3,553,900、§3.1 伪代码逐 tile 装载复算 |
| 2026-09-16 | **A 段拆分执行**：**A1**= Y 真 AXI 写主（yolo_dma_wr 镜像写通道 + 阵列内行段化器 + y_rdy 背压，ctrl V1.2 S_RQ 增等待、接高电平 ≡ V1.1）+ dsc_ybase 描述符字段化 + AXI-Lite CSR（yolo_csr，0x43C1_0000 合同）+ yolo_engine_top 组装（含 PROD 重参编译档）；门 = M9b 写主新门 + M8/M10/M11 回归 + CSR/engine 门。**A2** = loader V2 三件套（见下行，已授权） | 分批审阅纪律（§9）；A2 三项系上行发现的连带范围 |
| 2026-09-16 | **A2 全项授权（用户"按照1做"）**：loader V2 三件套全部入场——① W 跨 n_tile 持久（循环换序 oc 外/n 内，wbuf/xbuf bank 编排解耦：wbuf 按 oc_tile 翻、xbuf 按 n_tile 翻）；② X 行段流式 + xbuf 宽写口（8B/拍；im2col 行重叠 KW=3 扇出，1 字/3 拍流水 = 8 写/拍持续）；③ requant 尾重叠流水（REQUANT_UNITS>1，§3.4 原意）。预算复核：W 路 2.93MB@1B/拍=2.93M 拍（与 X 路并行）、X 写路 ≈15.8MB@8B/拍≈1.97M 拍、Y 路 3.55MB/8B=0.44M 拍、计算 3.95M 拍 → 关键路径 ≈3.95M 拍 < 5M 拍预算（150MHz/30fps，~15% 裕量）；三 HP 口 = W 读 + X 读 + Y 写（§3.5 原案）。数值合同全部不变（装填值/求和次序/写地址均不变，Y 写序与镜像布局无关——逐字节唯一地址） | 用户 2026-09-16 会话授权；本会话带宽复算（1.011 GMAC/帧、ΣN·K≈15.8MB、W=2.93MB、requant Σoc·n=3.55M） |
| 2026-09-16 | **M8 门 run03（ctrl V1.2 回归）通过**：S_RQ 增 `rq_rdy_i` 等待态（A1 Y 写背压：rq_en/rq_idx 稳定保持为 req/ack offer），TB 仅增 `.rq_rdy_i(1'b1)` 一行、激励零改动（复用 run02 seed 808，22 hex 重算 sha256 与 run02 记录零失配）。**接高 ⇒ 与 V1.1 run02 逐位一致**：cycles/compared=699590、ldone=23、adone=1 全同——等待路径未被本 run 激励（设计预期），真实背压正确性由 M10/M11 阵列门覆盖 | `4_metrics/logs/2026-09-16_yolo7020_m8_ctrl_run03/`（四件套，stim_manifest 沿用 run02 原件）；rtl/yolo_ctrl.v V1.2 + sim/tb_yolo_ctrl.v 增 tie |
| 2026-09-16 | **M9b 门 run03（dma_wr V1.2 非对齐起始）通过**：A1 前置——Y 行起始 = oc_g·n_total + n_tile·N_EDGE 仅 4B 对齐（N=100 层非 8 倍数，18 层），V1.1 "cmd_addr 8 对齐"合同对行段化不成立。V1.2：awaddr 内部下对齐 8B、装配 bcnt 从 head 起、首字 wstrb 掩 head、覆盖字数 = ceil((head+len)/8)；head=0 与 V1.1 逐位等价（A 组 11 条对齐回归零差异）。45 命令/410,255B/3,240 AW 全绿：head=0..7 全覆盖、非对齐大长度跨多 4KB（123456@head5）。**run03a 失败链（留证）**：28 条非对齐命令 sum 失配且仅 sum 一类——逐字节 F_byte/双写/缺写/计数/链/WLAST 全零错 ⇒ DUT 对、**vecgen 黄金 sum 简写 bug**（`addr+8*(i>>3)` 仅 8 对齐时等价 F_byte）；两条教训：黄金第二来源的捷径表达式扩展合同后必须重推导；失败跑与通过跑不得同名 log（首跑 transcript 被覆盖，失败链会话记录重建） | `4_metrics/logs/2026-09-16_yolo7020_m9b_dma_wr_run03/`；rtl/yolo_dma_wr.v V1.2、sim/tb_yolo_dma_wr.v V1.2、sim/dma_wr_vecgen.py V2（seed 912） |
| 2026-09-16 | **M9b 门通过（run01 目录，门运行 run02）**：yolo_dma_wr 线性块 AXI4 写主（M12 A1 第一件）。210,488 字节 DDR 侧逐字节值 + 写双射全对、33/33 命令计数/校验和全对、1,663 AW 全链化/单在途/不跨 4KB/每突发 WLAST、源侧喂送 == DDR 侧落盘、B 随机延迟排空（max 965 突发命令）、aw 30%/w 25%/源 30% 随机停停。**V1.0 揪出两处 AXI 缺陷**：① WLAST 只在命令末字置起（AXI 要求每突发末拍，rlast 镜像漏项）；② 突发链化缺失（状态转移挂命令末字而非 burst 末拍，非末突发打完停在 S_W 且 beats_r 下溢）；另 TB V1.0 生产者竞态教训：**ready 为 DUT 状态组合且接受行为改变它时，源侧握手必须 posedge 采样**（negedge 采样漏计/多计成对、同字节重复呈现） | `4_metrics/logs/2026-09-16_yolo7020_m9b_dma_wr_run01/`（README/console_extract/失败链+通过 transcript/manifest+sha256）；小端装配 = 读串行化精确逆（源字节 k → lane k，地址 A 的字逐位等于 rdata(A)）；Y 逐字节唯一地址 ⇒ 写序与镜像布局无关 |
| 2026-09-16 | **M10 门 run03（阵列 V1.2a Y 真 AXI 写主承接）通过**：`TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1` 与 V1.0 run01 六项逐项同数（门判据 = 计数同一性，Y 写延迟变化允许）；激励零改动（22 hex sha256 零失配）。**run02 失败链揪出段化器行首准入在途竞态**：准入读前沿前 seg_state_r，len-1 行序列（n_tail=1 尾 tile 行首拍背靠背）每 IDLE 窗口放进 4 个行首拍 = 吸收 1 + 落 SEG_CMD 丢 3，L0/L2/L5 丢 5+12+6 = **23 字节与 FAIL 逐位吻合**；设计论证"SEG_IDLE ⇒ 零在途"漏算 d1..d3 流水内已准入拍。V1.2a 修复：行首准入 = 段化器 IDLE ∧ 在途计数 seg_infl_r==0（d0 准入 +1/d3 落地 −1）；ywr_idle_w 同判据（堵 ctrl_ldone 贴尾 3 拍早脉冲窗）。ctrl V1.2 S_RQ 等待态首次非平局真实激励 | `4_metrics/logs/2026-09-16_yolo7020_m10_gemm_array_run03/`（四件套 + run02 失败链 transcript）；rtl/yolo_gemm_array.v V1.2a、sim/tb_yolo_gemm_array.v V1.1（AXI 写从 BFM 散写按物理地址，dsc_ybase = L×YSPAN TB 侧加，镜像布局与 V1.0 逐位一致） |
| 2026-09-16 | **M12 A1 CSR/engine 门 run01 通过（首跑）**：`TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1 csr=0` 与 M10 run03 六项计数同一性全同 + csr=0；激励零改动。yolo_csr V1.0（AXI-Lite 单在途从：12 影子描述符/CTRL 门铃/STATUS 含 ldone 计数/all_done 粘滞/IRQ W1C/LUT 0x400 窗口；C_BASEADDR 参数化）+ yolo_engine_top V1.0（u_csr+u_array 纯布线，PROD 16×16 默认参/SIM 8×8 门实例同 RTL；X 字节口 A1 直通，REQUANT_UNITS 随 A2）；寄存器图入 address_map.md（三处同步）。TB 以 M10 TB 同构黄金链，PS 角色全走 AXI-Lite 主 BFM（t0 影子模式往返自检 + 门铃/受理等待/ldone 轮询/IRQ 置起 W1C）。**smoke 失败链教训：寄存器拼接与解包位域必须读回抽检**——TB DESC1 把 act/first/last 拼到 [14:12]（CSR 读 [18:16]）致 L0 act 丢失、SiLU 旁路 220 字节值错（计数全对；值错是拼接错位的唯一线索） | `4_metrics/logs/2026-09-16_yolo7020_m12_csr_engine_run01/`（四件套 + smoke 失败链/通过 transcript）；rtl/yolo_csr.v、rtl/yolo_engine_top.v、sim/tb_yolo_engine_top.v、hw_contract/address_map.md（寄存器图表） |
| 2026-09-16 | **M11 门 run03（全网回归，阵列 V1.2a 承接）通过 → M12 A1 五件全绿收口**：`TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900 head_bytes=149100 ldone=63 adone=1` 与 run02 七项逐项同数 + `M11_HEADCHK_PASS sha256=9ce70525...` == run04 frame0 == run02；63 conv 全 acc_err=0（非零计数=0）；激励零漂移（stim 6 hex + vecgen + headcheck 与 run01 sha256 程序化比对全 SAME）。Y 观测口→真 AXI 写主换装对全网数据面逐位无扰动；§5 全链重跑义务履行完毕（M8/M9b/M10/M11 run03 + CSR/engine run01）。**run03 失败链（留证）**：TB 散写 BFM word 合并用逐 lane NBA——一拍 8 lane 落同一 8B 字互踩只留末 lane（conv0 acc_err=357407≈51200×7，DUT 侧逐字节全对）；修复 = 所有 strobe 拍合并成单 NBA。教训：**验证侧镜像模型的写合并粒度必须与被测写口的原子性一致** | `4_metrics/logs/2026-09-16_yolo7020_m11_fullnet_run03/`（README/console_extract/3 transcript + head_dump + headcheck.out/manifest + sha256）；sim/tb_yolo_fullnet.v V1.1 |
| 2026-09-16 | **B0 OOC run01/02 + UG479 严格合规批（用户令"读 ug479 严格按手册设计"，范围 = 全量 V1–V4）门链全绿**：B0 run01 DSP 238/220 超映射（推断式打包乘法被 Vivado 拆双 8 位乘法器）→ pe_pack V1.1 DSP48E1 直例 + xbuf V2.0 BMG IP → run02 `dsp48e1=142 ramb36=20` 但 150MHz FAIL（WNS −31.140）。UG479 v1.10 全文审计：12 项已合规 + 四类违规全修（V1 C 端接 / V2 D 端接 = Table 2-2 note 1 tie-High+CREG/DREG+CE/RST Low；V3 OPMODEREG==CARRYINSELREG（p.41）等控制属性显式流穿；V4 AREG=BREG=MREG=PREG=1 三级流水（p.14/p.47），ACASCREG=BCASCREG=1 由 Table 2-3 强制）。**模块延迟合同变更：pe_pack 输入 D 拍 → 输出 D+3 拍**（数值不动：M1 黄金集 10216 向量逐位复中）；配套 gemm_array V1.3 acc_en 3 拍重定时 + ctrl V1.3 S_DRAIN（末 K 拍乘积 tk → acc 落地 tk+4 → requant 采样 tk+5，k_total=1 亦安全）。门链：M1 PASS 10216/10216、M8 PASS 706403 拍（黄金再生成 drain=3×tiles）、M4/M10 PASS 438447 与基线同数、**M11 双跑 ModelSim 全绿**（V1.3 批 + V4 前基线：TB_FULLNET_PASS 3553900 同数 ×2 + M11_HEADCHK_PASS sha==run04 ×2；xsim 侧被 TB 级 X 问题阻塞 = PS t_add/t_rscl 大数组任务在 xsim 写 X，XDBG3 判决 RTL 无罪）。B0 run03：**dsp=142 稳定无恶化（流水寄存器不引入乘法器）但 WNS −31.017 与 run02 持平——"0 级流水 = −31ns 根因"被路径证据推翻（作废）**。真属主 = addrgen 描述符捕获 16 位组合除法/取模（`oy_r<=n_start/ow; ox_r<=n_start%ow`，95 级 76×CARRY4，cfg_ow_r→ox_r_reg）；dbg7c 分层：requant −24.6（47 级未分级）、acc −15.2 / ctrl −11.6（levels=1 高扇出 CE 纯布线）、xbuf −10.8（addrgen 直喂 BRAM）、PE −8.1（DSP 墙内已无长链）。**时序修复三向（addrgen 除法移出捕获拍 / requant 分级 / CE 复制）= 新范围待授权** | `4_metrics/logs/2026-09-16_yolo7020_ug479_compliance/`（M1/M8/M4/B0 证据 + README）；`..._m11_fullnet_xsim_failchain/`（XDBG3 + Plan B 基线收口）；`proj/ooc_gate/ooc_v13.*`（B0 run03）+ `ooc_dbg7c_vivado.log`（分层剖析）；rtl/{yolo_pe_pack.v V1.2, yolo_gemm_array.v V1.3, yolo_ctrl.v V1.3} |
| 2026-09-17 | **B0 时序收敛批收口：OOC v27 `GEMM16_OOC_TIMING_PASS wns=+0.005 whs=+0.051 fmax=150.11MHz`（150MHz 目标达成，dsp48e1=141→140）**。授权（~01:30）：xbuf BMG 输出寄存合同（xbuf V2.2 读延迟 1→2、ctrl V1.8 S_DRAIN 3→4、gemm_array W 预取 D+2 对齐 + V1.7 末拍 flush 读、黄金再生成仅延迟平移数值字节不变）+ "迭代直至 150MHz 收敛或无计可施；收敛/冻结后 M11 过夜直接启动"。13 轮迭代 WNS 轨迹：v13 −31.017 → v14 −6.507（addrgen V1.1/V1.2 除法/取模移出捕获拍 + 增量计数器）→ v15..v17 −1.98/−1.73/−1.46（row_addr 寄存乘法、acc CE 分组 + max_fanout）→ v19 −4.85（xbuf 合同回归）→ v20 −1.19（P&R Explore/AggressiveExplore）→ v23 −0.457 → v24 −0.224（requant V1.2e：64 位输出桶形消失，q8 窗口 mux + 在域判定代数化）→ v25 −0.079（requant V1.2f prod2_r PIPE 6 + addrgen V1.3 两级输出寄存 + gemm_array V1.8 尾链 d8）→ v26 −0.031（requant V1.2g 乘法操作数直通重寄存 sum_x_r/m_x_r→DSP AREG/BREG 吸收 PIPE 7 + gemm_array V1.9 尾链 d9）→ **v27 +0.005（gemm_array V1.10 行地址乘加拆分：cfg 项 d1 快照 + 16×16 乘法独立寄存积 row_prod_d2_r 单 DSP PREG + ybase+n_base 并行布线加 + d3 沿合并；mod-2^32 结合律逐位等价，d9 呈现拍不变 → M10 run12/M12 csr run09 与 v26 六层时刻逐拍同、$finish 同）**。**反复病理（v25/v26 owner 同构）**：宽乘法映射 2-DSP 级联且首 DSP 被组合穿越（A→multiplier→adder→PCOUT 内部弧 4.04ns），操作数自布线 FF 发火无 DSP 输入寄存可吸收——修法一律给乘法额外拍（操作数寄存吸收 AREG/BREG，或拆融合乘加出独立寄存积 PREG）。架构要点成文：gemm_array Y 尾不消费 requant vld_o 而以延迟 en 链重建有效（requant PIPE 每变尾链同步伸一级）；ctrl S_DRAIN 长度由 acc 排空链决定与 requant 深度无关（requant 四次 PIPE 变更 ctrl 零改动）；行地址 cfg 竞态由 d1 快照构造性消除（V1.5 NBA 次序论证退役）。v27 新临界 addrgen vld_o→xbuf BRAM ENARDEN +0.005（top10 全正裕量，BMG 输出寄存合同下稳定形态）。**冻结点 RTL**：gemm_array V1.10 / requant V1.2g / addrgen V1.3 / ctrl V1.8 / xbuf V2.2 / dma V1.3 / dma_wr V1.5 / pe_pack V1.2。M11 v27 全网 ModelSim 过夜启动（v13 为 B0 期唯一已执行对照；首跑 vlib 缺口 = sed 衍生脚本链从未执行的潜伏工具坑，脚本内留注）。**B1 主工程整合/bd + M13 板卡待另行授权；A2 loader V2 三件套已授权未启动** | `4_metrics/logs/2026-09-17_yolo7020_{ooc_gate_v25,ooc_gate_v26,ooc_gate_v27}/`（含 rowaddr 详径/top25 探针/全 WNS 轨迹表）+ `{m5_requant_run04,m5_m7_unit_v25,m10_gemm_array_run10..12,m12_csr_engine_run07..09}`；`proj/ooc_gate/ooc_v1{3..7},ooc_v19,ooc_v2{0..7}.tcl`（dcp 不入库）；`7_logs/2026-09-17/{01,02,03}` |

## 9. 执行窗口（2026-09-15 定义，本批权威边界）

**起点**：M0 第一个动作——`yolo_conv0_core.sv` 参数化为通用核（形状全参数化，
数值路径不动）+ 合成激励生成器。前置（golden 源/标量核/工具链铁律/证据规范）已就绪。

**推荐停止点**：M9 全绿、M10 未动（模块单测全过、集成未开——正是"逐模块
单独测试，再集成"的审阅分界）。**最小完成线**：M0+M1 双绿（两个决策门：
通用数值合同 + DSP 打包假设；M1 失败 → 回退 BASE-8×16 并重定后续模块参数）。

**批内硬暂停**：门 FAIL 且根因未明；数值合同疑义；任何需要板卡/Vivado/相机
管线的动作（均不属本批）；证据四件套缺一。

**本批不做**：M10–M13、Vivado 运行、位流、板卡操作、`0_diaplay_test` 触碰。

**停止时交付**：每门一个 run 目录（四件套）、7_logs 执行记录与 next_start_guide
更新、M1 结论入本文档 §8 决策记录、memory 更新。

执行顺序：M0 → M1 →（绿后并行）M2/M5/M6/M7 数值链 + M3/M4 缓冲 → M8 → M9。

**补记（2026-09-15 同日，M10 批）**：用户单独授权"开始M10集成"后，M10 已按
§5 规则完成并过门（见 §8 M10 三行）；期间 conv_core 数值路径改动已履行
全链重跑义务（M0 门 run02 零差异回归）。

**补记二（2026-09-15 同日，M11 批）**：用户单独授权"ok，先做M11"后，M11
已按 §5（含上表门定义修正行）完成并过门（见 §8 M11 三行）；RTL 零改动。
**当前权威边界更新为：M12（OOC 综合/Vivado）及其后（板卡）均未动，需另行
单独授权。**

**补记三（2026-09-16，M12 A 批）**：用户授权"先跑a"（A 段 = RTL 承接 +
仿真回归门；B 段 OOC 综合待 A 绿后另行确认）。A 段设计期发现 §3.1 带宽
口径对 PROD 档不成立（W 逐 tile 重载 63MB/帧等三项，见 §8 发现行），A 段
据此拆分：A1（Y 写主/CSR/ybase/engine_top + 回归门）先行；A2（loader V2
三件套：W 持久 + X 行段流式宽写 + requant 重叠）范围超出原 M12 承接清单，
待用户单独授权。
