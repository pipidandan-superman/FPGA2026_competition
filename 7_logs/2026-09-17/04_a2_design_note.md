# A2 loader V2 设计笔记（2026-09-17，授权"按照1做" + "先做A2"）

**状态**（2026-09-17 午后更新）：动工中。已落：wbuf V3.0（**M3 绿**，
TB_WBUF_PASS 21761 ops，实测 16 RAMB36/例、双 bank 32）、
yolo_dma V1.4（**M9 三门绿**：LEGACY+BYTE 210,904B 黄金零漂移 /
PIPE+BYTE / PIPE+WIDE，均 peak_ost=2，证据
4_metrics/logs/2026-09-17_yolo7020_m9_dma_v14/）。待做：xrowgen
V1.0+M7 → ctrl V2.0+M8 → gemm_array V2.0+M10 → csr/M12 → M11 →
B0 v28+。本笔记 = A2 动工前的设计定案 + **预算书面修正**
（§8 决策行 207 的 3.95M 拍结论被真实形状算术推翻，依"发现疑义停下书面提出"纪律成文）。
算术权威：`2_fpga/3_yolo_zynq/sim/a2_budget_calc.py`（对 schedule.json 63 层逐层复算，
含 8B 对齐过量读模型；`--json` 可导出逐层明细）。

---

## 1. 预算修正（核心结论）

### 1.1 原行 207 的三处口径错误

| # | 行 207 假设 | 真实形状算术 |
|---|---|---|
| 1 | X 写路 ≈15.8MB@8B/拍 ≈1.97M 拍（X 每帧只读一遍） | oc 外/n 内换序下 **X tile 每个 oc tile 重装一遍**：X 帧流量 = oct·N·K = MACs/16 ≈ **63MB**（不是 15.8MB；15.8MB 是 n 外序的 X 流量，而 n 外序 W 流量 63MB 一样爆） |
| 2 | 读口字节 = 写口字节（im2col 无放大） | **读放大**：k1×1 无 KW 扇出，16 输出要读 16B 源（8B/拍读口喂 16B/拍写口 → 2× 读受限）；s=2 k3×3 每 16 输出读 ~33B 源（~1.7×）；k3×3 s=1 扇出 ≈2.7 才近似持平 |
| 3 | 突发按线速计 | AXI 跨度按 8B 对齐：字节粒度 im2col 跨度每段多读头尾 0..14B（均值 +7B/段）——短段（16~33B）放大 ~1.2-1.4× |

### 1.2 修正后的诚实数字（PROD-16×16，REQUANT_UNITS=10，150MHz）

| 配置 | 帧拍数 | fps | 说明 |
|---|---:|---:|---|
| 计算下限（Σ oct·nt·K） | 4,044,480 | 37.1 | 63 层 1.011 GMAC / 256 MAC/拍 |
| **A2 授权范围 + 逐层最优走序** | **5,900,456** | **25.4** | 21 层选 n 外序（全部 k1×1），其余 oc 外序 |
| A2 固定 oc 外序 | 6,954,120 | 21.6 | 走序固定的代价 = 1.05M 拍 |
| A2 + X 读 16B/拍（A2b-X2） | 4,584,164 | 32.7 | 第二 X 读通道（4th HP 口或 W 口 ID 复用） |
| A2 + oc-pair（A2b） | 4,623,064 | 32.5 | X tile 服务 2 个 oc tile（wbuf 3 bank，+~16 BRAM36） |
| A2 + 两者 | 4,057,332 | 37.0 | 基本贴计算下限 |
| ~~行 207 原口径~~ | ~~3.95M~~ | ~~"30fps 带 15% 裕量"~~ | **作废** |

**结论：A2 授权范围（单 X 读通道 8B/拍）在诚实算术下达不到 30fps 规格**；
超额 1.86M 拍中 k1×1 层占 64%（读放大 2×+，结构性：16B 源/16 输出，8B/拍读口
无解，与走序无关），其余为 s=2 读放大 + 对齐过量读。
**任一 A2b 追加项（X2 或 oc-pair）单独即过 30fps（~32.5-32.7fps）**。
A2 全部机制（宽写口/第二读 DMA/xrowgen/尾重叠/wbuf V3.0）是 A2b 的严格子集
——先做 A2 不浪费，A2b 决策建议在 A2 门链绿后单批授权。

### 1.3 走序规则（设计变更）

真实最优走序逐层而异（比较 oct·max(Xw,Xr) vs nt·W），且依赖源字节数（非描述符
直接字段）。决策：**描述符增 1 位 `dsc_walk`**（0=n 外序 = 现行 V1.x 序，1=oc 外序），
由 PS 侧 gen_schedule 离线按逐层 min 规则填充（budget 脚本同式）。理由：
- 走序对数值**中立**（(k,n,value) 集合不变，仅装填/计算交错变）→ 启发式只影响性能不影响正确性，放 PS 侧零 RTL 算术风险；
- RTL 侧 `oct ≤ nt` 规则实测 6.75M（22.2fps），比真最优差 0.85M——不值得；
- 描述符/CSR 影子本批本来就要动（loader 重写），加 1 位的边际成本 ≈ 0。

SIM-8×8：全部计算受限（15.92M 拍），走序任选，数值不变。

---

## 2. 模块设计定案

### 2.1 ctrl V2.0（走序双模 + 快照事件 + 尾排空等待）

- 走序：`dsc_walk` 位选择 tile 推进——oc 外序：`last_n ? (n+1, oc=0) : n`（W 跨
  n 扫描持久，xbuf 每 tile 翻 bank，wbuf 仅 oc tile 变化时翻）；n 外序：现行
  `last_oc ? (oc+1, n+1) : oc+1`（wbuf 每 tile 翻）。**bank 翻转以各自 buffer 的
  装填计数器奇偶为准**（对两种走序统一，不用解码"外层是否变化"）。
- `rq_limit_r` 等输出按 tile 内 oc·n 乘积不变（走序不影响 tile 内容）。
- **S_RQ 从主序列退役** → 快照事件（见 2.5）：ctrl 在末 K 拍后发 `snap_o` 单拍，
  随即直接进下一 tile 的 S_TILE/S_K；requant 尾在 gemm_array 侧尾引擎消费快照。
- `S_LDONE → S_TWAIT`（新）：层末等尾引擎排空（`tail_idle_i`）+ Y 段化器空闲
  （`seg_idle_i`）才回 S_IDLE 置 ldone。S_DRAIN=4 拍不变（acc 排空链决定）。
- `tile_rdy` 拆分：`wbuf_rdy && xbuf_rdy && params_rdy`（loader 逐 buffer 置位，
  oc 外序下 W 未变时 wbuf_rdy 常高）。

### 2.2 xbuf V3.0（宽写口，读合同不动）

- 写口 `wdata_i` 从 1B 广播改为 **N_EDGE B/拍（16B PROD / 8B SIM）**：BMG DINA
  按 lane 各自馈数 + WEA 多热（尾 tile n_len<N_EDGE 时按 lane 掩蔽）。**无 IP
  改动**（V2.2 BMG 本就字节使能写）；读侧 2 拍延迟合同原样保留 → K 环时序零扰动。
- 写地址语义升级：`k_o` 行地址 + 全 lane 一拍一行（xrowgen 供数）。

### 2.3 wbuf V3.0（BMG 字布局 + 8B/拍宽写）

- 数据存储改 **每 bank 一个 BMG**：(K/8) 深 × **1024b** 字，字 = [16 行 × 8B]
  （word[b] 位 r*64+c*8 = 第 r 行第 8b+c 字节；128 字节 lane）。
  **实测 16 RAMB36/例**（util 复核：1024b 宽 = 16 并联 64b 源语、各深
  288/512=56% 填充；"8 RAMB36 恰打包"的比特数算术对宽度映射不成立——
  第三次宽度算术教训：1→2→8→实测 16）。双 bank 共 32 ≈ 全片 22.9%。
  与 V1.0 同比特量（V1.x 扁平数组若进 BRAM 同样 32；其为 LUTRAM），
  收益=宽写口+专用 BRAM，不是省 BRAM。
  首版误按 128b 字算成 1 RAMB36/bank：16 行×8B=128 字节≠16 字节，M3 首跑
  mismatch@113 即该宽度截断，已修正。
- 写：8B/拍写某行 r 的 k 块 b → WEA = 行 r 的 8 lane 掩码，DINA 对位放置（DMA
  宽口直馈）；K%8 尾块按 lane 掩蔽（行内 k≥K 的字节永不读，掩蔽仅为整洁）。
- 读：字 ⌊k/8⌋ 一拍出全 16 行的 k 块 + **寄存 lane-mux k%8**（共享 k → 全行同
  lane，16 个并行 8:1）→ 读广播延迟 1→2 拍。K 环装填侧 +1 拍平移（wrow_d1_r
  链顺应，gemm_array V2.0 一并重定时；与 xbuf V2.2 的 2 拍读对齐反而对称）。
- 参数（bias/m/shift）存储不动（现有数组）。

### 2.4 yolo_xrowgen V1.0（新模块：im2col 行段扩展器）

**职责**：消费第二读 DMA 的 8B 流（源行段，8B 对齐读 + 字节斜切），产出
(k, N_EDGE B) 宽写拍流直喂 xbuf V3.0。替换 addrgen 在阵列中的位置
（addrgen/M7 门本身保留存档）。

- **数值合同**（与 addrgen V1.3 逐位同集）：值(k,n) = pad ? pad_val : X_plane
  [ic·(IH·IW) + ih·IW + iw]，其中 k = ic·(KH·KW)+kh·KW+kw，ih = oy·sh+kh−ph，
  iw = ox·sw+kw−pw，pad = !(0≤ih<IH ∧ 0≤iw<IW)，pad_val = first ? −128 : 0。
  装填 (k,n,value) 集合与走序/次序无关 → 门判据 = 集合逐位等价（TB 按 xbuf
  终态比对，比对器复用 M4/M10 款）。
- **源读取粒度**：每 (ic, kh, oy 段) 一条 DMA 命令——段 = tile 内同行 n 的
  ox 范围 → 跨度 (ox_hi−ox_lo)·sw + kw 字节（16~33B 常态；tile 跨 oy 行时
  拆 2 段）。DMA 从 floor(lo/8) 读到 ceil(hi/8)，xrowgen **斜切寄存器**吸收
  ≤7B 头偏移，尾丢 ≤7B（budget 模型的 +7B/段）。
- **KW=3 扇出**：每源字节最多喂 3 个 k 行（sw=1 时 lane 对齐平移 pw；sw=2 时
  源隔 1 取用）。k1×1 退化为直通（无扇出，纯搬运 + 行内连续）。
- **pad 拍**：段首/段尾不足窗口的 n lane 填 pad_val（first 层 −128）；整行
  出界（ih 越界）的 (ic,kh) 段全 pad，不发行程 DMA 命令。
- **写拍率**：常态 1 k 行/拍（16B），读受限层自动以读率节流（写口 ready 由
  xbuf 空 bank 背压）。段切换（oy 跨界/kh 步进）插入 ≤2 拍气泡——budget 已
  按读率计，未另计气泡（<2%，xrowgen 两段乒乓取数可隐藏，实现期定）。
- 几何接受 = 描述符快照同 addrgen（start 脉冲采样，含 n_start/n_len 预钳）。

### 2.5 yolo_dma V1.4（宽出 + 命令 FIFO + AR 前视）——**动工期新发现（必做）**

现行 V1.3 单在途命令：每条命令串行付 AR→首 R 延迟（HP+互联保守 ~14 拍）。
X 路命令粒度 = 段（16~33B = 2~5 R 拍）：无前视时每段 ≈14+4 ≈ 19 拍 → k3×3
IC=128 层每 tile 384 段 ≈ 7.3K 拍 vs K=1152 计算拍 → **6.3× 读受限（预算模型
线速假设不成立）**。W 路同理（64B 行命令 = 8 数据拍 + ~14 延迟 = 2.75×）。
**结论：V1.4 必须带小命令 FIFO（深 4）+ ≥2 在途 AR**（同 ARID，AXI 同 ID 读
按序返回，消费侧天然按命令序）。前视 2 即达 R 率受限（段 4-5 R 拍 ≥ 1 AR 拍），
budget 线速模型恢复成立。
- 模式参数 `WIDE`：0 = 现行字节串行器（M9 黄金 210,904B 数据零差异复用，
  时序自由）；1 = 8B 字直出（r_fire 受 out_ready 背压）。
- M9 门增宽模向量集（数据 + FIFO/前视覆盖：跨 4KB、尾字部分、随机停停）。

### 2.6 gemm_array V2.0（loader 拆分 + 第二 DMA + 尾引擎）

- **loader 拆分**：W 路（u_dma 宽模 + wbuf 宽写 + 参数预取，按 oc tile 访问
  触发）与 X 路（u_dma_x 新例 + u_xrowgen + xbuf 宽写，按 n tile 访问触发）
  各自 rdy/busy；`tile_rdy` 聚合（2.1）。oc 外序下 W 路在 n 扫描期间纯闲
  （A2b-ID 复用的时间窗）。
- **REQUANT_UNITS 生成**（PROD 10 / SIM 3）：yolo_requant V1.2g **模块零改动**
  （M5 门继续有效），轮询 lane 发射（rq_idx mod RU），SiLU LUT 复制 ×RU
  （BRAM 代价 ~+5 RAMB36 等效，OOC 复核）。
- **acc 快照影仓**：N_LANES×32b ×2 乒乓（512FF×2 PROD）——末 K 拍 ctrl
  `snap` 脉冲把 acc 组打入影子 bank；下一 tile 的 K 环清 acc/累加与尾引擎
  读影仓无冲突。快照等目标影仓空（Y 背压最坏时尾滞后 >1 tile；2 仓 =
  深度 2 的弹性，超深由 ctrl S_TWAIT/层界自然节流）。
- **尾侧参数捕获**：快照拍锁 3·OC_EDGE 参数寄存 + act 位（下一 tile 参数
  预取与尾消费重叠的竞态由此消除）；行地址链（V1.10 d1 快照/d2 乘积/d3 合并）
  移植到尾引擎侧，呈现拍合同不变。
- X 平面组合口（x_addr_o/x_rdata_i）退役 → 第二 AXI 读主端口。

### 2.7 yolo_engine_top V1.1 / CSR / 合同

- engine_top：X 组合口换第二 AXI4 读主（x_m_axi_*）；CSR 增 `dsc_walk` 影子位
  （描述符字内空闲位，寄存器图三处同步 hw_contract/address_map.md）。
- descriptor/地址映射其余不动；数值合同冻结不变（装填值/求和次序/Y 地址均同）。

### 2.8 门链影响（A2 = 数值路径改动，§5 全链重跑义务）

| 门 | 变更 |
|---|---|
| M4(xbuf) | 宽写向量集新增（全宽/掩码/one-hot）；读合同回归 |
| M3(wbuf) | ✅ 绿：V3.0 字布局全向量集（TB_WBUF_PASS 21761 ops，2026-09-17；实测 16 RAMB36/例） |
| M7(xrowgen 新) | 新门：addrgen 同几何向量集，终态 xbuf 镜像逐位（k,n,value) 集合比对 + pad/k1×1/s2/跨 oy 段覆盖 |
| M9(dma) | ✅ 绿：V1.4 三门（LEGACY+BYTE 黄金复用 210,904B 零漂移 / PIPE+BYTE / PIPE+WIDE，peak_ost=2，2026-09-17） |
| M8(ctrl) | ✅ 绿：V2.0 黄金重生成（2026-09-17 run04，TB_CTRL_PASS 136014 拍/25 层/2286 tiles/双走序/snap 寄存脉冲/S_TWAIT；bank 改值变化沿翻转——单 tile 轴免重装，实现期定案） |
| M10 | TB：X 平面改 AXI 读 BFM（M11 DDR 镜像同款）；六层集 |
| M11 | 同上 + vecgen 增 dsc_walk 位（逐层最优，脚本同式）；ModelSim 为准 |
| M12(csr) | 影子位 + 重参编译回归 |
| B0 OOC | **解冻**，v28+ 迭代（wbuf BMG/xrowgen/尾引擎新路径） |

---

## 3. A2b 备选（本批不做，量化供决策）

| 项 | 帧拍数 | fps | 代价 |
|---|---:|---:|---|
| X2：X 读 16B/拍 | 4,584,164 | 32.7 | 第二 X DMA + xrowgen 双流消费；**4th HP 口**（B1 与显示管线 HP 预算冲突待查）或 W 口 ARID 复用（3 物理口不动，TB BFM 需 ID 支持） |
| oc-pair | 4,623,064 | 32.5 | wbuf 3 bank（+~16 BRAM36）+ ctrl 配对推进 |
| 两者 | 4,057,332 | 37.0 | 上两者叠加 |

建议：A2 门链绿后单批授权其一（X2 灵活但涉 HP 口预算；oc-pair 纯 BRAM 换）。

## 4. 风险与假设

1. +7B/段对齐过量模型假设 xbase ≡ 0 (mod 8) 与段起点均匀分布（误差 ±3.5B/段，
   对 k1×1 段最敏感）；实现后以 M10/M11 实测拍数复核。
2. Y 平面行距若 8B 填充（k1×1 段可零过量）= 布局合同变更（ dma_wr/addrgen/
   PS 镜像/TB 全动），本批不做，记为备选。
3. xrowgen 跨 oy 段 tile（OW=10/20 常见）是复杂度主体，M7 门向量集必须覆盖。
4. BRAM 帐以 OOC v28 为准。wbuf BMG **实测 16 RAMB36/例（双 bank 32，
   util 复核）** + SiLU LUT ×RU ≈ +5 RAMB36 等效。
5. B1 整合 HP 口预算：本设计 3 口（W 读/X 读/Y 写）；X2 变体需 4 口或 ID 复用。
