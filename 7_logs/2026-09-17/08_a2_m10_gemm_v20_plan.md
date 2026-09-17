# A2 M10 gemm_array V2.0 集成设计定案（2026-09-17，授权链同前）

**状态：设计冻结，未动工。** 前置已完成：ctrl V2.0 绿（07 笔记）、
M7 xrowgen 门待判决（06 笔记）、wbuf V3.0 / xbuf V3.0 / dma V1.4 /
xrowgen V1.0 端口合同已核对（本文引用）。

## 1. 端口面（gemm_array V1.10 → V2.0）

- **+ dsc_walk_i**（描述符走序位，透传 ctrl；CSR 侧 M12 批同步）。
- **X 组合口退役**（x_addr_o/x_rdata_i 删）；新增**第二 AXI4 读主**
  `x_m_axi_*`（araddr/arlen/arsize/arburst/arvalid/arready/rdata/rlast/
  rvalid/rready）——u_dma_x(WIDE=1) 直出。
- W 路读主端口不变（u_dma 升 WIDE=1 例化，宽口喂 wbuf V3.0）。
- ctrl 例化换 V2.0 端口：dsc_walk、wbuf/xbuf/params_rdy 三路、snap、
  tail_idle/seg_idle、w/x 双 bank 对（rq_* 全删）。
- layer_done 语义简化：ctrl S_TWAIT 已等排空 → 现行 ldone_pend/
  ywr_idle 门控逻辑退役，layer_done_o = ctrl_ldone 直出（安全裕度
  论证：S_TWAIT 进入条件已含 tail occ==0 && 尾 FSM 闲 && seg 闲）。

## 2. loader 拆分（W 路 / X 路，各自走序感知）

两 loader 步进**同一张 walk 网格**（与 ctrl 同式：walk0 = oc 内步进、
n 回绕步进；walk1 对称），各自只对**自己轴的值变化**动作：

- **W loader**：动作条件 = 层首 tile 或 oc(p)≠oc(p_prev)。动作 = DMA
  命令序列（OC_EDGE 行 W 宽写 + bias/m/shift 三段，cmd 8/9/10 语义
  保留）→ wbuf V3.0 宽写（we/wr_bank/wr_sel/wrow/wblk/wdata64）。
  **目标 bank 序列与 ctrl 翻转严格合拍**：层首装入 ctrl 接受拍的
  w_rd_bank（= V1.x layer_bank0_r 推广）；此后每次装入 ~上次目标
  （交替）。跳步（oc 不变，仅 walk1 出现）不动 bank、自由前进。
- **X loader**：动作条件 = 层首 tile 或 n(p)≠n(p_prev)。动作 =
  xrowgen start 脉冲（几何快照：n_start=p_n·N_EDGE、n_len=尾宽、
  xbase、k_len、first）→ u_dma_x(WIDE=1) ← xrowgen cmd 流 →
  xrowgen 宽写流 → xbuf V3.0（we/waddr/wstrb/wdata，bank 由本层
  接线）。目标 bank 序列同构（n 轴）。
- **rdy 合同**（ctrl S_TILE 三路等待的来源）：
  - wbuf_rdy = w_bank_oc[ctrl_w_rd_bank] 有效且 == ctrl_oc_tile
  - xbuf_rdy = x_bank_n[ctrl_x_rd_bank] 有效且 == ctrl_n_tile
  - params_rdy = 预取捕获完成（见 §4）
- **防跑飞**：装填目标恒为 ~ctrl 当前读 bank → 双 bank 交替天然把
  每个 buffer 的"装填"限制在 ctrl 消费 +1 之内（第 2 步装填的目标
  = ctrl 正在读的 bank → busy 阻塞）。ctrl 在装填未完时推进（bank
  已翻转）→ S_TILE 等 rdy=0，beat_en=0 不读，安全。
- **退化轴**（oc_tiles/n_tiles==1）：层首装填后永不再动 → rdy 常高
  （与 ctrl 值变化翻转语义严格一致，M8 黄金已覆盖此形态）。

## 3. acc 快照影仓（乒乓 ×2）+ 尾引擎

- 影仓 = 2 × N_LANES·32b；占用计数 occ∈{0,1,2}；**snap_rdy =
  (occ ≠ 2)**。snap_o 拍末沿：shadow[wr] ← acc_q，wr^=1，occ++。
- **快照捆绑**（尾引擎只读捆绑，不读 ctrl 活动计数器——竞态由构造
  消除）：acc 通道 + pb/pm/ps 平面寄存（3·OC_EDGE）+ act 位 +
  oc_g_base(=oc_tile·OC_EDGE) + n_base(=n_tile·N_EDGE) + n_tail +
  rq_limit(=oc_tail·n_tail−1，snap 拍一次乘) + ybase + n_total。
- **尾引擎**：按槽序处理快照：idx 0..limit 顺序发射（与 V1.x d0
  解码同式但用捆绑值），REQUANT_UNITS 轮询（idx mod RU，SIM RU=3/
  PROD 10；requant V1.2g 与 silu_lut 模块零改动，LUT ×RU 例化），
  每拍最多 RU 发射；RU 宽 sideband 链（行参数/地址 d1..d9 链 ×RU
  通道）；槽处理完 occ−−、rd^=1。
- **tail_idle**（喂 ctrl S_TWAIT）= occ==0 && 尾发射 FSM 闲 &&
  d 链全空；**seg_idle** = 现行 ywr_idle_w（SEG_IDLE && infl==0）
  推广 RU 宽后的对应式。

## 4. 参数预取与快照捕获时序

- 预取仍按 V1.x 形态：S_TILE 拍（acc_clr 电平）从 wbuf 参数区读
  3·OC_EDGE 字段进 pb/pm/ps 平面寄存；**每 tile 重跑**（含 walk1
  的 oc 不变 tile——量小 ~26 拍，换取单一时序合同；wbuf_rdy 已含
  参数就位）。params_rdy 在 tile_change（= snap_o 或 dsc_accept）
  清零。
- **快照拍把平面寄存连同 acc 打包**（§3 捆绑）→ 之后 bank 翻转/
  重装填/下一 tile 预取都碰不到尾引擎的数值源。

## 5. RU 宽 Y 段化器（必要重设计，非可选）

RU 单元的意义 = 尾吞吐 RU B/拍（与下 tile K 环重叠：conv0 型
K=27 tile 尾 256B，1B/拍时 256>27 尾受限；RU≥9 后尾 ≤K 恢复计算
受限）。因此段化器必须吸收 ≤RU B/拍：

- **行组装级**（新）：RU 发射道 → 行缓冲（每行 ≤N_EDGE B），
  组内可跨 1 个行界（RU≤N_EDGE 时最多跨 1；SIM 3<8 ✓）。行满 →
  推 (addr,len)+缓冲 给写级。
- **写级**：u_dma_wr 命令节流不变（AW/W/B 往返 ~几十拍/行），
  双行缓冲乒乓 + 行命令队列，背压经**行首准入**上传到发射控制：
  发射道 lane 可发的条件 = 非行首 || (行组装级有空缓冲 &&
  写级行命令队列未满)。准入式是 V1.x "IDLE && infl==0" 的 RU 宽
  推广（V1.x 的在途竞态教训直接继承：行组装级的"忙"必须含已发
  射未落地计数）。
- **Y 数值合同不变**：字节值/地址/行序均与 V1.x 逐位同集（RU 只
  改时序），M10 黄金按字节镜像比对继续有效。

## 6. M10 门改造

- TB：X 路 = 第二 AXI 读 BFM（M7 款多在途，独立 DDR 镜像同一份
  X 平面）；W 路读 BFM、Y 写 BFM 沿用。六层集沿用 + walk 位
  逐层填（含 walk0/walk1 对照层）。
- vecgen：描述符增 walk；黄金仍 = 装载值/求和/Y 字节镜像逐位
  （与走序无关的集合合同，M7/M11 同哲学）。
- 时序断言：peak_ost≥2（两读主各证）、snap 乒乓深度 2 行为、
  RU 轮询发射覆盖率（每单元均发火）。

## 7. 实施顺序（防一口吃成）

1. gemm_array V2.0 骨架：ctrl 例化换新端口 + 影仓/捆绑 + 快照
   消费尾（RU=1 退化：单 requant + 现行段化器字节准入照搬）→
   M10 先绿（时序合同换血、吞吐暂不提）。
2. X 路 loader（u_dma_x + xrowgen + xbuf V3.0 宽写）+ X BFM。
3. W 路 loader 宽化（u_dma WIDE=1 + wbuf V3.0）+ 双 bank 编排。
4. RU=3 发射 + RU 宽段化器（§5）。
5. M10 全量 + M11 全网 + B0 OOC v28（wbuf +32 RAMB36、ctrl rq
   乘法器下线复核）。

每步一个可跑门：1/2/3 各自 TB_CTRL 式断言或 M10 中间跑，4 落
M10 终判。**本笔记即第 1 步的动工依据。**
