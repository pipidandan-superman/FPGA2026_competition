# YOLO INT8 图算子引擎（PPU）设计手册

版本：1.0，2026-09-18。对象：EES-331 / XC7Z020 上与 GEMM 引擎同级的 PL 图算子
处理单元（graph-Processing Unit，下文统称 PPU），覆盖 Add、重定标 Concat、
MaxPool 5×5、Upsample 2×、view 与 heads 装配。

本文是可实施的设计规格与 ABI 冻结文件，不是 RTL 验收报告。数值语义的唯一
权威是软件 golden（run04 合同），本文一切算子公式逐字转录
[intref_yolov8.py](../../../4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04/intref_yolov8.py)
并已被 G0 回放证明等价（[G0 run01](../../../4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run01/)）。

配套阅读：[GEMM 设计手册](../../../1_docs/yolo_gemm_design_manual_20260918.md) §1/§12/§13、
[PE 设计手册](../../../1_docs/yolo_pe_design_manual_20260918.md) §9、
[CSR 设计文档](../../../1_docs/yolo_axi_lite_csr_design_20260918.md)、
已板级验证的 CSR RTL（`2_fpga/3_yolo_zynq/rtl/ps_axi_pl/`，只读）。

**沙箱边界**：本线全部产物位于 `2_fpga/parallel_task/`（用户 2026-09-18 指令），
不修改 rtl_pe/、两手册、ps_axi_pl 冻结 RTL 与主树日志证据根。

## 1. 系统定位与算子清单

GEMM 手册 §1 已划定边界：GEMM 引擎执行 63 个 Conv（含 bias/requant/SiLU），
Add、Concat、MaxPool、Upsample、view 是**同级 PL 图算子**，由全局调度器
（CSR 描述符队列）管理。PPU 就是这些图算子的执行引擎；heads 装配（6 张量
搬移成 raw head）与 view（零拷贝地址别名）也归 PPU 描述符域。

| 模块 | 职责 | 明确不承担 |
|---|---|---|
| PPU requant 核 | x_q×M → RNE → sat_i8（int64 中间） | 浮点、frexp、运行时算 M/shift |
| PPU xfer 引擎 | 段式搬移 + 逐段可选 requant（Concat/heads/COPY） | 跨段重排、即时序依赖裁决 |
| PPU add 引擎 | 双流 requant 后 int32 求和一次饱和 | 两个以上输入 |
| PPU maxpool5 | 5×5 s1 行窗 max | 其它核/步长（版本变更） |
| PPU upsample2 | 最近邻 ×2 行复制 | 其它倍率/插值 |
| view | buffer 表别名，PL 零搬移 | 数据复制 |
| 调度/依赖 | 由 CSR walker 队列顺序保证 | PPU 内部二级图分析 |

当前 schedule.json（rom_data 四件套 == run04，manifest sha 已核）共 104 任务：
conv 63 + 图算子 41。图算子实例清单（形状/字节数为本包事实，已脚本核验）：

| 算子 | 实例数 | 形状域（CHW） | 单实例字节 | 说明 |
|---|---:|---|---:|---|
| view | 16 | ch 对半切（C∈{16,32,64,128,256} 的 [0,C/2)/[C/2,C)） | 0 | C2f split，零拷贝 |
| add | 6 | (16,80,80)…(128,10,10)，a/b/out 同形（已断言） | 12800…102400 | 逐元素双路 requant |
| concat | 13 | 2–4 输入同 H/W，通道和==输出通道（已断言） | 出 38400…307200 | C2f 内 9 + neck 4 |
| maxpool5 | 3 | (128,10,10) SPPF pool0/1/2 链式 | 12800 | 5×5 s1 pad −128 |
| upsample2 | 2 | (256,10,10)→(256,20,20)、(128,20,20)→(128,40,40) | 25600→102400、51200→204800 | 最近邻 ×2 |
| heads | 1 | 6 输入装配 149100 B | 149100 | 见 §8 布局表 |

## 2. 软件计算合同（逐字转录，禁止改写）

量化包合同（manifest `source.quant_contract`，run04 冻结）：W8A8、逐 OC 对称
权重、逐张量对称激活、INT32 累加、逐 OC M+shift RNE requant、SiLU 256 表、
Add 单次饱和。PPU 算子在该合同的 int8 张量域上工作。

### 2.1 公共原语

    req_pair(r): r=f·2^e (f∈[0.5,1)) → M=RNE(f·2^31) (归一 [2^30,2^31))，
                  shift=31−e；shift>62 → (0,0)（死通道，软件离线完成）
    rne_shift(n,s): q=floor(n/2^s)；rem=n−q·2^s；
                    |2·rem|>2^s 向近整；|2·rem|==2^s 且 q 奇 → 偶侧（含负数：
                    −1.5→−2、−2.5→−2）；s==0 恒等；int64 中间
    sat_i8(x): clip(−128,127)

**已核验事实**（2026-09-18，证据 §11 P0 run01）：r=1.0 → (M=2^30, s=30)，
x×2^30>>30 RNE 逐位还原 x —— **同尺度 requant 是精确恒等**，因此同尺度
concat 段是无损复制。本包 50 个 add/concat 尺度比样本域 [0.3956, 1.8597]、
无死通道、31 个唯一 (M,shift) 对；M/shift 全部由软件离线算好入表，PL 不做
任何浮点。

### 2.2 逐算子语义

- **add**：`Ma,sa=req_pair(a_scale/out_scale)`、`Mb,sb=req_pair(b_scale/out_scale)`；
  `A=rne_shift(a_q·Ma, sa)`、`B=rne_shift(b_q·Mb, sb)`（int64）；
  `out=sat_i8(clip(A+B, −2^31, 2^31−1))`。int32 截断在 i8 饱和前仅是合同序
  （本包比率域下 |A+B|≤127×(0.4+1.86)×2<512，永不触界），RTL 仍按字面实现。
- **concat**：逐输入 `M,s=req_pair(in_scale/out_scale)`、
  `part=sat_i8(rne_shift(x·M, s))`，沿通道维顺序拼接。同尺度段=精确复制。
- **maxpool5**：k=5 s1 p=2，**pad 值 −128**，`o` 初值 −128，25 窗位取 max。
  等价性证明（手册新增，供 RTL 结构选择）：−128 是 int8 最小值，窗内有效位
  ≥3×3（10×10 输入 p=2 时角窗最小 9 有效位），故
  `max(有效位 ∪ {−128×pad位}) ≡ max(有效位)`；边界恒为 −128 的数据与 pad
  亦逐位同结果。**RTL 可选"只对有效位取 max + 位置掩码"结构，不必物化 pad
  字节，结果逐位等价**（P2 门必须两种实现模型交叉对拍一次以证等价）。
- **upsample2**：`out[...,2y,2x]=out[...,2y,2x+1]=out[...,2y+1,2x]=out[...,2y+1,2x+1]
  =in[...,y,x]`（H、W 各 repeat 2；尺度不变）。
- **view**：`out = in[c0:c1,:,:]`，纯地址视图（base+c0·H·W，尺寸 (c1−c0)·H·W）。
- **heads**：6 输入按 §8 布局恒等拷贝（无 requant；scale 字段仅供 PS float 解码）。

## 3. 数据布局与 buffer ABI

- 张量布局 CHW、字节（int8）粒度；行距=IW（无跨距填充，第一版冻结）。
  逻辑地址 `addr = base + c·H·W + y·W + x`。
- buffer 表（CSR 合同 §5.2：128 项×8 word）承载 base(64b)/size/line_stride/
  C,H,W/scale_id/owner/valid/producer/consumer。**view 不新增 DDR 存储**，
  仅在 buffer 表登记别名项（base=in_base+c0·H·W，shape=(c1−c0,H,W)）。
- 逻辑缓冲 104 项、单帧工作集 Σ=6,715,500 B、最大单缓冲 409,600 B
  （model.0 输出，已核验）。**第一版不做 buffer 复用**：全帧常驻 CMA
  （板 CMA 128 MB @0x10000000，工作集 6.72 MB 占 5.3%，余量充分），
  word7 consumer-count 字段保留给后续复用版本。
- DDR 地址窗：EES-331 PL 只见低 512 MB，CMA 窗 0x10000000..0x20000000
  （板级事实，记忆 #30）；全部特征缓冲与 head 缓冲必须落在该窗（PS 分配侧
  义务，PL 侧按 32 位物理地址直用，高字验证为零——同 GEMM 手册 §9.1）。

## 4. 描述符 ABI（图算子域）

基座：CSR 已冻结合同（`yolo_csr_pkg.sv` + 设计文档 §5.1，板级 L1–L4 已验证）：
128 项×32 word、16 KB 表经 8 KB 窗口（A_DESC_BASE 字基分页）访问、
walker 消费 head 指针、word14 累计输出字节、last 位触发结果环发布。
**104 任务 ≤ 128 项 ✓；GEMM 手册 §13 的"16 KB vs 8 KB"疑问在实装 RTL 中
已按窗口分页解决（核验：yolo_csr_pkg.sv:133 注释）。**

word0/1/2/14 字段沿用 pkg 已冻结定义。本手册冻结图算子域的其余字段：

| word | 字段（图算子解释） |
|---:|---|
| 0 | `[7:0]` opcode（§4.1）；`[8]` valid；`[9]` last；`[10]` first（本域=0）；`[11]` act_en（本域=0）；`[12]` walk（本域=0）；`[15:13]` ownership（0=PPU） |
| 1 | `[7:0]` desc_id；`[15:8]` dependency_id；`[31:16]` next_id |
| 2 | `[9:0]` in0（主输入/段表首项）；`[19:10]` in1（add 第二输入）；`[29:20]` out |
| 3 | `[15:0]` C；`[31:16]` H（W 复用 word6，见下） |
| 4 | `[15:0]` W；`[15+k..]` 预留 |
| 5 | `[15:0]` in0 quant profile id；`[31:16]` in1 quant profile id（add 用） |
| 6 | `[15:0]` 段数 N_seg（concat/heads 输入个数；单输入算子=1） |
| 7 | `[15:0]` in0 段内字节长度（view/单输入；0=按 C·H·W 推导） |
| 8 | 预留（图算子域零） |
| 9 | `[7:0]` 模式字（maxpool5 恒 5×5s1=0；upsample2 恒 ×2=0；版本演进用） |
| 13 | `[7:0]` graph flags（bit0=in_place 禁止恒 1；bit1=同尺度捷径许可）；`[15:8]` N_seg 镜像；`[23:16]` pool/upsample 模式镜像 |
| 14 | 期望输出字节（walker 累计用；与 §1 表一致） |
| 16–31 | **内联段表**：word[16+2i]=段 i 的 buffer id（`[9:0]`）+quant profile id（`[25:16]`）；word[17+2i]=段 i 字节长度。最多 8 段内联（heads 6 段、concat ≤4 段覆盖 ✓） |

**决定：不设外挂段描述符表。**当前模型 concat ≤4 输入、heads=6 输入，内联
8 段容量足够；若未来图超过 8 段再启用 word16 指外挂表（版本变更，需改手册）。
段序=输出通道序，软件按 schedule.json 输入顺序填表。

### 4.1 opcode 分配（本手册提案冻结，冲突项挂 §10）

| opcode | 算子 | 引擎路径 |
|---:|---|---|
| 0x00 | 非法（walker 报 E_CODE_DESC_INVALID） | — |
| 0x01 | CONV（**GEMM 线所有**，本手册不定义其字段） | GEMM |
| 0x02–0x0F | 预留 GEMM 线扩展 | GEMM |
| 0x10 | VIEW | 零搬移（buffer 表别名已在装载期完成，运行时仅依赖记账） |
| 0x11 | ADD | add 引擎 |
| 0x12 | CONCAT | xfer 引擎（逐段可选 requant） |
| 0x13 | MAXPOOL5 | maxpool5 引擎 |
| 0x14 | UPSAMPLE2 | upsample2 引擎 |
| 0x15 | HEADS | xfer 引擎（6 段恒等拷贝至 head 基址） |
| 0x16–0x1F | 预留 PPU 扩展 | — |

quant 表 profile（CSR §5.3，16 B/项，256 项）：word0=M、word1=shift。PPU 段
profile 与 conv 逐 OC 参数**分域**：conv 的逐 OC M/shift 随 W tile 走 GEMM 线
DMA 通道（GEMM 手册 §13），不占 quant 表；PPU 全部 41 任务共 50 个 (M,shift)
引用（31 个唯一对）入 quant 表绰绰有余。

### 4.2 调度与完成合同

- 第一版**顺序执行**：walker 按 head 指针序派发，PPU 与 GEMM 不重叠
  （SCHED_CFG.overlap 预留位，版本演进）。schedule.json 任务序即拓扑序，
  PS 按 tasks[] 顺序写描述符即天然满足依赖。
- PPU 完成定义同 GEMM 手册 §5 STORE 语义：**全部写事务 BRESP 收妥**才置
  done，不以最后 WLAST 发出冒充；desc_done 计数 +1，walker 继续下一项。
- view 描述符运行时零搬移：PPU 收到即回 done（仅错误检查：ch 边界）。
- 帧末：heads 为 last 位持有者，其完成触发 walker 发布结果环（ring 记
  head_base/head_bytes=149100/frame_id/seq），PS ACK 后进下一帧——全部沿用
  已板验证的 walker/ring 合同，PPU 不私改。

## 5. PPU 微架构

### 5.1 requant 核（add/xfer 共享参数化）

`y_q = sat_i8(rne_shift(int64(x_q)·M, s))`，s=0 旁路直通、M=0 恒 0（死通道，
本包未出现但合同保留）。RNE 实现同 GEMM 尾部（GEMM 手册 §8 公式）：
`q=n>>s; rem=n−(q<<s); q += (2·rem>2^s) − (2·rem<−2^s) + tie_adj`，
tie_adj 仅当 |2·rem|==2^s 且 q 奇。乘法 33×32→int64：1–2 DSP 或 fabric，
P2 门综合定论（**不承诺"不占 DSP"**——旧文档教训）。

### 5.2 xfer 引擎（CONCAT/HEADS/单段复制）

段序流式搬移：对段 i，DMA 读该段 buffer（行段化、64b 口），逐字节过可选
requant（段 profile M=2^30,s=30 时硬件走同尺度捷径=直通，位精确等价已证
§2.1），写 out 基址 + 通道偏移。段间无空隙。heads 特例：目标基址=HEAD_BASE，
段偏移查 §8 表，全部恒等拷贝。

### 5.3 add 引擎

双输入同形（描述符装载期断言 a/b/out shape 相等，违者 E_BIT_BUFFER）。
两路读流按同一线性序（c·H·W+y·W+x）推进；各自 requant 后 int32 加、
sat_i8 一次。两流读带宽不同步由输入 FIFO 弹性吸收（深度按行段大小 P2 定）。

### 5.4 maxpool5 引擎

CHW 通道序处理（平面 10×10=100 B 连续）。4 行 line buffer（4×10 B）+ 当前行，
列窗 5 取 max，按 §2.2 等价性用**有效位掩码**实现（不物化 pad）。边界行/列
仅对窗内有效位比较。输出同形直写。通用化参数 C/H/W 综合期定界（本包实例
128×10×10；P2 门须含非本包形状的合成用例防过拟合）。

### 5.5 upsample2 引擎

行流式：每读入行 y（W 字节）产出 2 行输出，每输入字节 xx 相邻复制。
输出行地址 = out_base + c·(4W²)+(2y)·(2W) 与 (2y+1)·(2W)。无算术。

### 5.6 DMA 与总线

64b AXI（同 GEMM 手册 §9.2 纪律：独立 AW/W、背压、RLAST/RRESP/BRESP、
4 KiB 边界、尾字节 WSTRB、在途计数、错误停发+受控排空）。PPU 读口与写口
第一版经 interconnect 与 GEMM 共享 HP 映射（**独立 vs 专用 HP 口**挂 §10
开放决策，板级带宽实测后定）。行段化器沿用 M9b/M10 已验证模式（Y 行 4B
对齐合同）。

### 5.7 带宽预算（本包事实）

PPU 每帧流量（已脚本核验）：读 2,427,500 B + 写 2,389,100 B ≈ **4.82 MB/帧**
（view 零流量）。64b AXI @100 MHz 有效 ~400 MB/s 量级下 ≈12 ms/帧上限；
@60 MHz first-light 档 ≈20 ms。此为 PPU 独占口径，与 GEMM conv 流量
（手册 §10）共享互连时需系统级再预算——**不承诺任何 FPS**，同 GEMM 手册
纪律。

## 6. 与 CSR/调度器集成 ABI 核对表（§13 义务履行）

| GEMM 手册 §13 检查项 | 本线核验结论（2026-09-18） |
|---|---|
| 16 KB 描述符 vs 8 KB 窗口 | 实装 RTL 已用 A_DESC_BASE 字基分页解决（yolo_csr_pkg.sv:133–138）✓ |
| 描述符项数容量 | 104 任务 ≤ 128 项 ✓ |
| buffer 表容量 | 104 逻辑项 ≤ 128 项 ✓（view 别名项含在内） |
| 8-bit 能力字段 vs 256 lanes | CAP0/CAP1 为只读能力报告，不承载 lanes 绝对值；PPU 不新增位宽假设 ✓ |
| LUT 窗口 | LUT 归 GEMM 尾部所有，PPU **不触碰** LUT 表与 0x5000 窗 ✓ |
| 逐 OC bias/M/shift 容量 | conv 域走 GEMM 线 W-tile DMA（其手册 §13）；PPU 域 50 引用/31 对入 quant 表（256×16B）✓ |
| 修改 CSR 合同 | 本线**零修改**：walker/ring/寄存器图不动，PPU 作为计算引擎替换走查本体（walker 文件头预留位） |

## 7. 验证计划与门（镜像 PE 线 G0→G7 纪律）

| 门 | 内容 | 通过标准 / 必存证据 |
|---|---|---|
| **P0** | 手册+ABI 冻结+事实核验脚本 | 本文档 + `4_metrics/logs/2026-09-18_yolo_ppu_abi_factcheck_run01/`（req_pair 恒等性、比率域、形状断言、流量账、CSR RTL 几何核对原始输出） |
| **P1** | PPU oracle + 全图回放对软件 golden | 5 帧全可比节点（conv+图算子，≥53/帧）位级 0 失配 + 12 个含 golden 的图算子节点单列 0 失配 → `PPU_ORACLE_PASS`；C2f 内 cat/pool 无直接 golden 张量，由下游 golden 传递覆盖（附传递链说明）。证据 `…_yolo_ppu_oracle_run01/` |
| **P2a–d** | 单算子 RTL 门：UPS2 / MAXP5 / ADD / XFER | 每门：向量生成器（反退化纪律：现实域 + 平局 + 饱和 + 死通道 + 同尺度捷径专门向量；生成期 distinct/tie/sat 断言）→ TB 独立 oracle（期望永不取自被测公式）+ 延迟记分板 + 复位/背压/空拍用例 → `EES_MODELSIM_RESULT PASS`（vsim `-c -novopt`，独立 run 目录）。MAXP5 门含 pad 物化 vs 有效位掩码双模型交叉对拍（§2.2 等价性实证） |
| ~~P3~~ | ~~描述符驱动集成 TB（walker 派发 + DMA BFM + 41 图算子全任务）~~ | **已撤销独立门（2026-09-19 用户决策）**，依据与去处见下"P3 撤销注记" |
| **P4** | 与 GEMM 线汇合（对应其 G5/G6） | 双引擎全网：convs=63 + 图算子 41 + heads，逐字节对软件 golden；时机由两线进度协调，**不单方启动** |

**P2 执行状态（2026-09-19 夜，并行线 rtl_ppu）**：五门全绿 `EES_MODELSIM_RESULT PASS` ——
requant（`2026-09-18_yolo_ppu_requant_run01`）、upsample2（`2026-09-19_yolo_ppu_upsample2_run01`）、
maxpool5（`2026-09-19_yolo_ppu_maxpool5_run01`，含 pad 物化 vs 有效位掩码双模型交叉）、
add（`2026-09-19_yolo_ppu_add_run01`）、xfer（`2026-09-19_yolo_ppu_xfer_run01`，恒等捷径
≡全量 requant 等价钉死——金文件对恒等段也算全 requant）。执行编号 P2a–e 与上表 P2a–d
字母错位一行（requant 单列 P2a，上表四算子顺延 P2b–e），每门 README 含首跑教训。

**P3 撤销注记（2026-09-19，用户决策，docs-first 落档）**：对 schedule.json
41 图算子任务做缓冲索引→生产者反查：16 个 view 为零拷贝描述符（无 RTL）；
余 25 个引擎任务中 16 个（64%）输入全部直连 conv 输出/外部缓冲，仅 9 个
存在引擎→引擎输入（add→concat ×4、add→add ×2、maxpool5×3→concat ×1、
upsample2→concat ×2），且全部是"先后任务共享 DDR 缓冲"级耦合——五引擎
皆 DMA 喂的流核，引擎间无流式直连。故 PPU-only 集成 TB 的实质 = 自写
walker + 自写 DMA BFM 复放 P2 已逐字节钉死的数值，conv↔图算子缓冲布局/
生命周期/requant 分工等真合同在单验中不存在。处置：①P3 不作为独立门；
②walker/描述符译码并入 G4 与 GEMM 线共定合同后实现（§10 D2 同步）；
③41 任务回放保留为 P4/G5 bring-up 的二分调试工具（oracle 层，无 RTL
集成 TB）；④引擎邻接场景由 P4 全网首跑在同一调度序列内天然覆盖。

每门证据四件套（README/console/raw 输出/结果 JSON）+ 输入输出哈希；TB 新增
不得拷贝 DUT 算法生成期望；数值、地址、总写字节、完成次序同时检查。

## 8. heads 装配布局（149100 B = 0x2466C，已核验）

| 序 | 段 | 形状 | 字节 | head 内偏移 |
|---:|---|---|---:|---:|
| 0 | reg8 | [64,40,40] | 102400 | 0 |
| 1 | reg16 | [64,20,20] | 25600 | 102400 (0x19000) |
| 2 | reg32 | [64,10,10] | 6400 | 128000 (0x1F400) |
| 3 | cls8 | [7,40,40] | 11200 | 134400 (0x20C00) |
| 4 | cls16 | [7,20,20] | 2800 | 145600 (0x23900) |
| 5 | cls32 | [7,10,10] | 700 | 148400 (0x243D0) |

段内 CHW；顺序 reg8/16/32→cls8/16/32 与 GEMM 手册 §12 一致；PS 读
HEAD_BASE 起连续 149100 B 做 DFL/sigmoid/NMS（PS 域，非本线范围）。

## 9. 边界与禁止事项

- 不做浮点、frexp、运行时算 M/shift；不改变任何软件量化点（GEMM 手册 §1
  红线）。数值域外输入在描述符装载期报错，不静默回绕/提前饱和。
- 不修改：两手册、`rtl_pe/`、`ps_axi_pl/` 冻结 RTL、rom_data、golden、
  主树日志证据根。共享契约（描述符位域/opcode/缓冲布局）变更必须先改本
  手册并同步 §10 对表。
- PPU 不做分支拼接/Softmax/NMS/DFL（PS 域）；不做 conv/im2col（GEMM 域）；
  不触碰 SiLU LUT（GEMM 尾部域）。
- 时序/资源结论只认锁版本综合报告；本手册不预支任何"不占 DSP/免费带宽"。

## 10. 开放决策表（需对表方与时机）

| # | 事项 | 默认（本版按此实施） | 对表方/时机 |
|---|---|---|---|
| D1 | opcode 数值分配（0x01 conv 归 GEMM 线，0x10–0x15 图算子） | 本手册 §4.1 | GEMM 线 G3 起步前互认；冲突即改表重发版 |
| D2 | 描述符 word3–13 图算子域位域终版 | 本手册 §4 | 两线 G4/P4 前联合冻结（conv 域字段以 GEMM 线为准；P3 已撤销，见 §7 注记） |
| D3 | PPU 独立 HP 口 vs 经 interconnect 共享 | 共享（BD 现状） | 板级带宽实测后（对应 GEMM 线板后候选决策） |
| D4 | buffer 复用/所有权回收启用时机 | 第一版全帧常驻 CMA | 系统级 DDR 预算定型时 |
| D5 | overlap（PPU 与 GEMM 并行执行） | 关闭（顺序派发） | G5 汇合后按关键路径实测决定 |
| D6 | 沙箱迁移归位时机 | agent 全部结束后用户主导 | 用户 |

## 11. 来源与证据

- 语义权威：intref_yolov8.py（run04 副本，sha 见该 run README）；
  G0 等价性：`4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run01/`。
- 事实核验（本手册 §1/§2.1/§3/§5.7/§8 全部数字）：
  `2_fpga/parallel_task/4_metrics/logs/2026-09-18_yolo_ppu_abi_factcheck_run01/`。
- CSR 实装合同：`2_fpga/3_yolo_zynq/rtl/ps_axi_pl/yolo_csr_pkg.sv`（只读）。
- 旧线参考实现（只读）：rtl/ 下 xrowgen/dma/dma_wr/requant（行段化/背压/
  RNE 结构参考，不直接复用其 A2 散装寄存器接口）。

本轮交付范围：本手册 + P0 事实核验 + P1 oracle 回放 + P2 起步 RTL 门。
不启动综合、不启动板测、不修改主树任何文件。
