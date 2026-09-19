# A2 M10 —— R1 死锁根因（done 残留高电平 + loader 无反压）与修复 #9/#10

承接 09_a2_m7_run9_fix8.md。RTL：yolo_xrowgen.v V1.2→**V1.3**（Fix #9）、
yolo_gemm_array.v V2.0→**V2.0a**（Fix #10）。

## 症状（dbg9/dbg10 完全一致 → 非 #8 回归，V2.0 首跑即有）

- L0 正常走完（done @t=20766000，ywr=343）。
- R1（model.0，oc=16→oc_tiles=2、n=25600→n_tiles=3200、walk0 n-outer）
  发出全部 6400 tile，**Y 字节数 0、occ=0、ctrl=1（S_TILE）卡死**，
  ct=0/0（tile 0 永未准入），x_n_r 走到 3198/3199（X loader 跑完整层），
  w_oc_r=0/1（两 bank 按 oc 特化）。
- 冻结态残留：xrowgen phase=IDLE 且 **done=1**（本应是 1 拍脉冲）、iq=1/1。

## 证据链

1. **TCL 状态转储**（m10_probe1.tcl，快照 m10dbg10）：
   `xbuf_rdy_w=0`（x_n[0]=0xC7E=3198 ≠ ctrl_n_tile=0）而 `wbuf_rdy_w=1`
   —— 死锁点 = ctrl 在 S_TILE 等 `x_n==0` 的值窗口，已被 loader 覆写掉。
   两个 loader 均 idle 且走完层（wl_n=3199, xl_n=3199）。
2. **START 事件配对异常**（TB [xrg] START 追踪）：xrowgen START 两两成对、
   间隔仅 30~270ns，而单次真实填充需 ~1.4µs —— loader 的 S_XRUN 在启动后
   3~27 拍就提前退出过一次。
3. **逐拍探针**（TB [xl] 窗 5.0–5.35µs，快照 m10dbg11）定形：
   ```
   t=5015: fill n0 真实 done（em_done_p_r=1，phase→P_IDLE）
   t=5025..5045: em_done_p_r 保持 1 —— P_RUN 外无默认清零，
                 直到下次 start 快照（V1.2 line 511）才清！
   t=5045: loader 3 拍 walk 后发 START n1；S_XRUN(n1) 进入时采到残留 done
   t=5055: S_XRUN(n1) 立即退出 → 提前发布 tag1（b1 数据还在流）
           → 游标走到 n2 → START n2 打在 P_DIV 忙时被静默丢弃
           → fill n2 从未运行，却在 fill n1 的真实 done 上发布 tag2→b0（陈旧数据）
   ```

## 根因（两个叠加缺陷）

- **#9（xrowgen V1.2）**：`em_done_d_r/em_done_p_r` 只在 P_RUN 分支赋值，
  P_IDLE 期间保持 —— done_o 从完成一直挂到下次 start 快照。背靠背用户
  （X loader）3 拍 walk 内发的下一个 start 落在残留窗口里，新 S_XRUN 入口
  采到 done=1 立即退出：提前发布 + 下一个 start 被丢 + 被丢填充的 tag 发布
  在真实填充的 done 上 —— tag/bank/数据三方错位（也是冻结态 done=1、
  iq=1/1 残留的来源）。
- **#10（gemm_array V2.0 loader）**：无真实反压。need 按值变化触发
  （walk0 下 W 每位置都触发 → R1 全层 6400 次全冗余加载，A2 ① 的跨
  n_tile 持久化从未生效；X 每两位置一次 → 3200 次全部跑完）；唯一填充门
  `ctrl_beat_en && bank match` 只防计算拍，S_TILE/S_SNAP 期间不设防 →
  loader 自由跑完整层，把 ctrl 还没消费的值窗口覆写掉。W fill#1 慢于
  X 早期充填时，ctrl tile-0 准入窗口（x_n==0 ∧ w_oc==0 同时成立）在
  wbuf_rdy 拉高前就被销毁 → 永久死锁。

## 修复

- **#9（V1.3）**：else 分支顶部加 `em_done_d_r/em_done_p_r <= 1'b0` 默认
  清零（P_RUN 内再赋值覆盖，last-write-wins）—— done_o 恢复真 1 拍脉冲。
- **#10（V2.0a）**，每个 loader 三件套：
  1. **need = 值不在其 ctrl 奇偶 bank 中**（presence 判据；walk0 下 W 全层
     只加载 2 次 = A2 ① 落地）；
  2. **目标 bank = wl/xl_bank_par_r**：随游标推进、按该轴**值变化**翻转
     （与 ctrl `w_bank_chg_w/x_bank_chg_w` 完全同构）—— 填充永远落在 ctrl
     将要读的 bank，跳过不再破坏对相（旧“按填充次数交替”在有跳过时错相）；
  3. **填充许可 = 目标 bank 的 tag ≠ ctrl 当前需求值**（任意 ctrl 相位，
     替代 beat_en 门）。
  净效果：loader 每缓冲至多领先 1 个值、永不逐出 ctrl 正需要的值 →
  值跟踪握手窗口永不失守；accept 时清 vld 保证跨层无陈旧满足。

## 验证

- **dbg12（快照 m10dbg12，V1.3+V2.0a）——死锁修复实证，数值 FAIL（新战场）**：
  - 结构面全绿：六层全走完（L0 @21.606ms / L1 @16.183ms / L2 / L3 / L4 / L5 @31.915ms），
    `dut_wr=438447(exp 438447)`、`snap=6883(exp 6883)`、`occ2=1607138`、
    `bfmerr=0/0`、`ost_w=2 ost_x=2`、`ldone=6 adone=1`、`dbl=0 unwritten=0`。
    心跳实证设计节拍：R1 期间 xn=1975/1976（恰领先 1 值）、ct=0/1976（值匹配）、
    woc=1/0（W 持久化生效，A2 ① 落地）、occ=2（A2 ③ 尾重叠活跃）。
  - **数值面 FAIL**：`err=275910`，首错 `L=0 i=73 dut=127 gold=0`。
    i<73 全对（oc0 全 49 字节 + oc1 前 24 字节）。i=73=(oc1,oh3,ow3)=tile3 第 0 字节。
  - 旁证两条（待查）：wbuf/xbuf 同址读写 collision（L2–L4 交界，addr 5–9）；
    L5 期间 "Address 900 outside range for B Read" ×8。
  - **数值回归属 V2.0 线**：run12（v27，gemm_array V1.10，同冻结 stim/m10、
    同 yexp1/2 参考数组）曾 `TB_GEMM_ARRAY_PASS compared=438447` —— 参考可信，
    回归由 A2 重写（V2.0/xrowgen/dma V1.4）引入，且 V2.0 此前从未跑到过终局比对。
- dbg13（快照 m10dbg13，TB 加分层错误统计 + 256 值直方图 + L0 窗口转储）：
  分层错误 L0 31/343、L1 274225/409600(67%)、L2 71/400、L3 799/2304、
  L4 768/25600(3%)、L5 14/200；**所有层 hist_eq=0** → 纯值错误，非错序/寻址。
  L3 误差全为 127↔128（饱和边界翻转）、L4 全 ±1~2 → 与"acc 缺/多若干乘积项"的量级一致。
- dbg14–17（快照 m10dbg14..17）逐级收窄：
  - d14：首错位 i=73（瓦3、oc_loc=1、n_loc=0）的 requant 参数全对
    （b=57041 m=2^30 s=31，与瓦0 oc1 相同）而 acc 错（dut −52060 vs ref −57041）→ 缺陷在 requant 上游。
  - d16（TB 侧精确 im2col 参考 + SNAP 时刻 56 lane acc 转储）：
    **t=0 全 56 lane 精确**（W 布局/X 数据/MAC 瓦内全对）；t=1..5 每瓦恰一条
    干净列 j=7−t；t=4 的 j4/j5 delta 逐 oc 相同；同一组 per-oc 误差值
    （oc0 +6272 / oc1 +16000 / oc2 −3072 / oc3 −7424 / oc4 −14464 / oc5 −2304 / oc6 +5888）
    跨瓦在不同 lane 复现 → 暗示固定错误数据流。
  - d17（xrowgen 写监听 + 与 TB im2col 逐字节比对）：**7 瓦全部 0/216 字节错** →
    xrowgen V1.3 摆放完全正确，xbuf 内容精确；瓦1 填充起始 5.245µs 早于瓦0 SNAP
    5.855µs（按设计 1-ahead 重叠）。缺陷收窄至**读侧/累加侧**。
- dbg18（TB 解析错误模型扫描，106 候选 × 全 287 比较点含零点）：
  **mid=9 sg=0 精确命中 287/287 —— delta(t,j,oc) = −w[oc][0]·X_t[j][0]**：
  每瓦（t≥1）恰好丢 k=0 首拍乘积！干净列之谜同时解开：j*=7−t 的像素是
  (t+1,0)，c=0 → k=0 字节为 PAD=0 → delta 自然为 0。
- dbg19（wrow_vld 边沿消费操作数抓取 + 与 d17_exp 逐拍比对）：
  **XBAD=0/189、MISS=0** —— 读通路完全干净，进入 PE 墙的每个 X 字都精确；
  读侧彻底排除。
- dbg20（瓦0/瓦1 首拍微迹 + acc_d_w 加数转储）：加数序列解密 ——
  乘积在 **wv+3** 拍出现在 acc_d_w（p0=−6223 @7.705 可见），而 en 链（4 级）
  首拍在 **wv+4**（@7.715）→ en#j 加的是 p_{j+1}；末拍后乘积寄存器保持 p26，
  最后一个 en 把 p26 重复加，恰好抵消移位丢的 p26 → 每瓦总和 = Σ − p0。
  瓦0 幸免纯属掩蔽：图像顶行全 pad → **瓦0 全部 lane 的 p0=0**；t=6 j0 精确
  因 img[5][5]=0。

## 根因 #11（数值回归）与修复

- **#11（gemm_array V2.0/V2.0a）**：acc 使能链保持 V1.6 的 4 级深度，但 V1.x 的
  wrow 经 `wrow_d1_r` 额外 staging（wrow_vld 晚 1 拍，+4 链正确）；V2.0 撤掉
  staging 后 wbuf V3.0 的 `dout_vld` 提前 1 拍（D+2），乘积 wv+3 到达而使能
  wv+4 才开——注释“chain length identical”正是误判之处。
- **修复（V2.0b）**：en 链缩短为 wv+3（删 acc_en_d3_r，组寄存器改接 d2）。
- dbg21（快照 m10dbg21，V1.3+V2.0a+**V2.0b** 全程仿真）：
  - 结构面全绿且与 dbg12 一致：`dut_wr=438447(exp) snap=6883(exp) occ2=1607138
    bfmerr=0/0 ost_w=2 ost_x=2 ldone=6 adone=1 dbl=0 unwritten=0`。
  - **err 275910 → 23**。分层：L0/L1/L2/L3/L5 全零（hist_eq=1）；
    **L4 恰 23 错，前 8 条 i=24792..24799 = oc61 × n392..399**（= L4 最后
    一个 tile：oc_tile 7 × n_tile 49，8×8 全满 tile），dut=252..254 vs
    ref=250..251（int8 −4..−2 vs −6..−5，delta +2/+3），hist_eq=0（真值错，
    非错位）。打印上限 8 隐藏了其余 15 错的分布（dbg22 将放Cap 并解 oc/n）。
  - 仿真层完成时刻：L1 @16.183ms / L2 @16.584 / L3 @16.743 / L0 @21.606 /
    L4 @31.187 / L5 @31.915。

## 层边界两族告警的定性（dbg21 后分析）

- **"Address 900 outside range for B Read" ×8（L5 期间）= 十六进制 0x900=2304**：
  xbuf 深度恰 2304（L5 k=2304）。`xren_flush_q`（V1.7 尾冲）在
  `ctrl_k_cnt==k-1` 的下一拍补读地址 k=2304 —— 越界 1。全设计仅 4 个 BMG：
  wbuf×2（288 块、addr 9b，十进制 900 塞不进）、xbuf×2（12b/2304 深，十进制
  900 在界内不会告警）——唯一自洽解释是模型按十六进制打印。
  冲刷拍数据无人消费（acc 使能链是 W 侧计时），L5 数值全对 → **良性**，
  修复属整容（冲刷地址钳到 0 或 k-1）。
- **collision ×5**（非 9）：wbuf bank1 addr5 @16.592（L3 初）、xbuf bank0
  addr6/7 @16.664（L3 中）、wbuf bank0 addr8/9 @16.775（L3 完成后、L0
  执行初）。涉及的 L3/L0 数值全零 —— 未致数值损伤，但属 Fix #10 许可窗
  之外的同拍同址（READ_FIRST 旧值语义救了读侧）→ dbg22 顺带审计窗口内
  写活动（预期 0）。
- **层边界竞争族排除（机制论证）**：`dsc_ready_o=(state==S_IDLE)`，而
  S_IDLE 只能经 S_TWAIT（tail_idle ∧ seg_idle）→ S_LDONE 到达 —— 下层
  描述符/下层 LUT 预载/下层 W/X 填充全部被尾排空串行化，不可能与上层
  尾部重叠。loader 与 ctrl 共享同一 `dsc_accept_w`，无提前嗅探。
- **requant 参数快照混合假说排除**：d14 已证同层内逐 oc 参数差异巨大
  （b ∈ [−512466, 57041]、m/s 各异）——错 entry 会造成大 delta，
  与 +2/+3 不符。且参数随 W 装载流尾部（先 576×8B 数据后 bias/m/s）
  落 bank 平面，许可窗打开前不可能先写参数。
- **+2/+3 的量级再解读**：Δy=Δacc·m/2^s 经 RNE —— 若 oc61 的 s 偏大
  （如 39），Δy=+2/+3 对应 Δacc≈±1000（整整一个乘积项）；若 s=31 则
  Δacc≈4..6。不能由 delta 量级反推根因 —— 需逐拍数据（dbg22）。

## dbg22（快照 m10dbg22）：三级判定 —— 引擎全洗清，嫌疑定位操作数字节

- TB 改动：dbg13 打印上限 64 + oc/n 解码；[d22] 探针武装于
  (oc_tile 7, n_tile 48)：逐 wrow_vld 拍抓 xcol/wrow 64b（两瓦×576 拍）、
  SNAP 上下文（acc 64 lane + pb/pm/ps + act）、尾引擎 d1 上下文 + 7/8 级
  延迟链配对的 y_pre/lut y_o、窗口写活动计数；终局三级分析
  （①acc vs 乘积和 ②y_pre vs d22_rq 位精确参考 ③全链 vs yexp2）。

- 结构复查与 dbg21 一致：L0/1/2/3/5 errors=0 hist_eq=1；窗口内写活动
  xbuf=10270 wbuf=2304（计数窗跨到 L5 填充，设计上不可判定，弃用）。
- **stage 1（acc vs Σ 抓获乘积）：两瓦各 0/64** —— 读→PE→累加→影子槽全自洽。
- **stage 2（y_pre vs 位精确 requant 参考）：0/256** —— requant 引擎与逐 oc
  参数快照精确。
- **stage 3（全链 vs yexp2）：230/256 —— 探针自污染，不作数**。缺陷：尾拍
  捕获的槽过滤 `slot ∈ {slot[0],slot[1]}` 对所有瓦都真（影子槽就 0/1 两个
  乒乓），256 拍缓冲混入 L5 拍 + 瓦 47 尾拍，却被硬编码 n48/n49 坐标解码。
  d23 已加 `cur_layer==4` 门控修正捕获侧（dbg23 run1：tailbeats 256→70，
  但瓦 48 尾拍仍被硬编码 n392 坐标解码 —— stage3 CHAIN 行里 yexp2 的
  "野值"（0/4/35/251…）全是错单元格的金值，与主比对平滑值无矛盾）。
- **错块全图（dbg13 cap=64 全打印）**：23 错 = oc61–63 × n392–399
  （oc_loc 5–7 × 全部 8 n lane，24 格中 23 格），全部 dut>ref
  （oc61 +2/+3，oc63 +3..+10）。
- **排除法定位**：W 行错会污染 oc_tile 7 全部 50 个 n_tile（A2① W 持久）→ 排除；
  纯 X lane 错会打满全部 8 个 oc 行 → 排除；唯一自洽解释 = **末瓦 k-walk 混入
  少数损坏的 X k-拍**（每个坏拍打满 8 lane；Δacc(row)=Σ_k ΔX[k]·W[row][k]
  随行权重不同，部分行的 Δy 经 RNE 舍回正确值）。
- **d23（stage 4，两轮）**：接受 L4 描述符时冻结 img[] 的 X 区域，终局把
  抓获的 X 拍与 im2col 金模型逐字节比对；W 查跨瓦一致性（n48 vs n49）。
  - run1（m10_dbg23_xsim_run1.log）三条硬结论：
    ① **字基假设死**（9216/9216 全错）、**字节基址律确认** —— xbase=0x5C718
    =378392 作字节地址，k<144（ch0–15）**2304/2304 精确匹配**（两瓦全对）；
    ② **W 跨瓦 0/4608 差异**（n48/n49 W 完全一致，持久化+读回双洗清）；
    ③ 探针自身 sizing 失误：L4 X 区域 = 64ch×40×40 = 102400 字节
    （ih=iw=40、ow=20、s2p1，由 layers.hex 解码：k=0x240、n=0x190、
    xbase=0x5C718、mode=2、walk=1），快照只存 26000 → ch≥16 出界成噪声
    （XBAD dut=04..07 exp=xx 洪水即此）。真错误区尚未比到。
  - **run2（m10_dbg24 前身，log 已存 m10_dbg23_xsim.log）：惊天反转** ——
    **X 全区 0/9216、W 跨瓦 0/4608**：进入 PE 墙的操作数 100% 金模型精确！
    叠加 stage1（acc==Σ乘积两瓦 0/64）+ stage2（requant 位精确 0/70）→
    **操作数/MAC/requant 引擎全洗清，"末瓦 X 损坏"假设死亡**。
    另一异常：`tailbeats=70` = 6（瓦47 尾残留）+ 64（瓦48 尾）+ **0（瓦49）**
    —— 末瓦 requant 尾拍全部在 layer_done（31.187ms）之后才发射！
    机制（RTL 证实）：`tail_idle_w=(sh_occ_r==0)`，occ 在末拍**发射**即减，
    9 级流水最后几拍还在飞 S_TWAIT 就放行 → 末瓦尾天然跨层尾。
    剩余嫌疑收窄为：**SNAP（已验证正确）与尾排空消耗之间，acc/影子槽
    idx 40–63（=oc_loc 5–7 全 lane，恰好是错块）被加了 +3000..+6000
    （乘积量级）的增量**；Δy·2^s/m 反推量级吻合。
  - **dbg13 全 24 格错值**（本次 cap 打满）：oc61 全 8 格 +2/+3（n396/397
    为 +2）；oc62 7 格 +1..+3（n397 幸免=唯一正确格）；oc63 全 8 格
    +3..+10；全部 dut>ref、hist_eq=0。
  - **d24（run3，log m10_dbg24_xsim.log，快照 m10dbg24）：四环闭合，根因落地**：
    - **影子槽洗清**：全部 64 拍 `accC==accS`（requant 消耗的 acc 与 SNAP 时刻
      影子槽逐位一致，dacc=0/64）——"影子槽被改写/ping-pong 失步"假设死亡；
      首拍 t=31186695 > layer_done @31186676，64 拍**全部在层结束后发射**；
      前 40 拍（oc56–60）yd==yexp2 精确，最后 24 拍（oc61–63）= 恰 23 错
      ——**时间序选择性**（错块=最后飞的拍），非位置/索引选择性。
    - **离线数值实锤（无需仿真）**：从 ddr.hex 提取 lut4（base 0x75718）与
      lut5（base 0x80088）两张激活表，逐格检验 23 个错格：
      **20/23 满足 ∃idx: lut4[idx]==ref ∧ lut5[idx]==dut（同 idx！）**
      —— dut 写回的正是**下一层激活表在同索引的值**。两张表均为量化 SiLU
      （4 值组网格、饱和区 250–255），相邻层同 idx 差小而平滑（+2/+3 均匀、
      中段斜坡区 +3..+10、oc62/n397 恰差 0 幸免）——完美解释误差形态。
      剩 oc63 三格（dut=44/18/43）**不在两表值域**（网格外值），且其 ref
      （35/14/33）∉ lut4 —— 待 run3 扩展打印（逐拍 y_pre + l4/l5 同 idx
      预测）定论；主机制已由 20/23 铁证。
    - **机制链**：`tail_idle_w=(sh_occ_r==0)`，而 sh_occ 在末拍**发射**即减
      → S_TWAIT 提前 ~10 拍放行 LDONE → TB/PS 在 `layer_done+8拍+gap` 后
      开始**为下一层顺序预载 LUT（addr 0→255，每拍一项）** → tile-49 尾拍
      的 LUT 读（发射后 ~8 拍才到达）落进预载窗口：先飞完的 40 拍读到旧表
      （正确），最后 24 拍的索引已被覆写 → 读到 L5 表值。层内 2-slot 重叠
      （A2③ 本体）无关 —— 竞态只在**层边界**：尾引擎读的唯一存储器 = LUT，
      而唯一写者 = 下一层预载。`yolo_silu_lut` 读写同拍共存（NBA 旧值语义，
      同址读写无害），被覆写后一拍起读到新值 —— 与"时间序选择性"吻合。
- **修复 #12（gemm_array V2.0b→V2.0c）**：`tail_idle_w` 恢复 V1.2 完整排空
  契约 = `(sh_occ_r==0) && (seg_state_r==SEG_IDLE) && (seg_infl_r==0)`
  （复用既有 `ywr_idle_w` 线）—— 每拍 LUT 输出落地（seg_infl 清零）+
  segmenter 回空闲后才算层尾排空。层内瓦间重叠不动；层边界损失 ≈ 64 拍
  排空（~2.4µs/层 @100MHz，<0.03% 层时长），换来 PS 侧 LUT 重载的安全序。
- **run 4（m10dbg25，log m10_dbg25_xsim.log）：err=23 原样 —— 修复不全，
  挖出同一放行路径的第 2 个洞**：
  - err 块与 run3 **逐位同型**：oc61 全 8 格 +3/+3/+3/+3/+2/+3/+3/+3、
    oc62 7 格 + n397 恰 +0 幸免、oc63 +9/+8/+10/+10/+4/+10/+8/+3；
    3 个"异常格"（44/18/43）原样复现 → 竞态确定性、非 stim 矛盾。
  - **3 个异常格离线闭合（同 run4 的 d24 行交叉）**：oc63 行的 dut−ref
    差值序列与 oc61 行的 `lut5[idx]−lut4[idx]` 差值序列 7/8 逐格全同
    （n393: 26/34↔26→34、n394: 36/46↔36→46、n396: 14/18↔14→18、
    n397: 33/43↔33→43、n399: 9/12↔9→12）—— oc61/oc63 不同行的 requant
    结果撞出相同 y_pre（同 idx），异常格就是**同一 lut4→lut5 同 idx 交换**；
    此前离线表 3 格配对抽取有误，"值域外/网格外"判断作废，
    **23/23 全归同一根因，stim 不一致假说出局**。
  - **洞 2 修复未生效的机制实锤（洞 1）**：ctrl 的 `snap_o` 在 S_TWAIT
    **首个周期**为高，而影子占用自增 `sh_occ_r <= sh_occ_r + 1` 是 NBA、
    **当拍末才落地** —— S_TWAIT 首拍采到的是 snap 前的旧值 `sh_occ==0`
    → **进入即放行**，LDONE 比末瓦尾发射还早 ~2 拍（dbg25 首拍在
    layer_done 后 19ns=2 拍，整条 64 拍末瓦尾全在层结束后跑）。
    S_TWAIT 的 `tail_idle∧seg_idle` 门此前**从未真正起过作用**。
  - d24 的 yp/l4 采集链错位（正确拍 yd==yexp2 却 ≠l4[yp]、末 16 拍
    yp=x）—— 探针延迟链抽头与 chase 序号未对齐，归因列数据不可靠；
    accC==accS 0/64 依旧成立，主链结论不受影响。
- **修复 #12 补全（V2.0c 第二刀）**：
  `tail_idle_w = (sh_occ_r==0) && !ctrl_snap && ywr_idle_w`
  —— `!ctrl_snap` 堵洞 1（脉冲拍不放行，次拍起 sh_occ==1 由槽机制接管），
  `ywr_idle_w` 堵洞 2（发射后管线落地）。`tail_idle_w` 唯一消费者 =
  ctrl 端口（已 grep 证实）。
- **run 5（m10dbg26，log m10_dbg26_xsim.log）——`TB_GEMM_ARRAY_PASS`，M10 门复绿**：
  ```
  TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
                    ldone=6 adone=1 snap=6883 occ2=1607157 ost_w=2 ost_x=2
  ```
  - 六层全 errors=0、hist_eq=1（dbg13 分层统计）——**L4 的 23 错全清，3 个
    异常格一并愈合** → 竞态污染定性终审，stim 集无罪。
  - **全排空契约的机制签名**：L4 done 31186676000→31195516000（后移
    884 拍 = 整条 64 拍末瓦尾排空）；L5 后移 1333 拍；L2 +140 拍、
    L3 +192 拍（各自尾排空）；**L0 恰不变**（其末瓦 snap 时 Y 段化器
    仍忙，run4/run5 都被 ywr_idle 门住等排空——两版同拍退出，非修复失效）。
  - compared==dut_wr==438447 逐字节双射；occ2=1607157（A2③ 双槽重叠
    活跃）、ost_w/ost_x=2（A2② 行段流式正常）、bfmerr=0。
  - V2.0c 至此通过全冻结 stim/m10 六层数值门：**A2 loader V2 三件套
    （① W 跨 n_tile 持久 wbuf V3.0 ② X 行段流式 dma V1.4+xrowgen
    V1.3+xbuf V3.0 ③ requant 尾 2-slot 重叠）+ Fix #9–#12 全链成立**。
- **M7 回归（m7x20，log m7_run10.log）**：`TB_XROWGEN_PASS tiles=66
  bytes=29342 cmds=1887 ars=1889 peak_ost=2` —— 与 run9 判定行逐字段
  一致，xrowgen V1.3 无回归。
- **run13 干净取证 + A2 批收口**：TB 探针全退役（488 行：
  [xrg]/[xr2]/[xl]/[d14]/[d16]/[d17]/[d18]/[d19]/[d20] + #22µs 分析
  initial → 备份 `sim/tb_yolo_gemm_array_dbg24_probes.v`；原始首差
  比对 + 朴素心跳复原，D22_CAP/D22_ANA 不定义，d23 冻结循环加宏门）。
  快照 m10run13，log m10_run13_xsim.log：
  `TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
  ldone=6 adone=1 snap=6883 occ2=1607157 ost_w=2 ost_x=2`
  ——六层完成时刻与 run5 逐 ps 一致（确定性）。证据目录
  4_metrics/logs/2026-09-17_yolo7020_m10_gemm_array_run13/（README 含
  失败链 #7–#12 全表、机制签名表、RTL/stim 哈希清单）+ M7 回归
  ..._m7_xrowgen_run02/。**M10 门以 V2.0c 干净版复绿，A2 loader V2
  三件套收口**。遗留良性项（collision ×5 / 0x900 冲刷越界 ×8 /
  wdt 32 位溢出警告）已记录 README，不阻门。
- **编译卡死三连的真相 = xsim.dir 工作库损坏，非源码**：上一段把
  xvlog CPU-空转 + 0 字节日志归因于“d22 声明晚于使用”——声明块
  移位后依旧空转，证伪。二分法定位：把 d22_rq 函数、三维数组写
  分别做成最小 scratch 文件在新目录编译（秒过）→ 再把整个 TB 放
  新目录编译（秒过）→ 同一文件在 sim\xsim 目录空转：**损坏的
  xsim.dir（被强杀的 xvlog 留下）让任何 xvlog 无限空转**。处置：
  `Rename-Item xsim.dir xsim.dir.corrupt` 后全量重建库（13 个设计
  文件 + glbl.v + 金模型 rtl yolo_conv_core/yolo_pe_pack/yolo_addrgen/
  yolo_csr + 两个 BMG sim 模型），`-d D22_CAP -d D22_ANA` 全开一次过。
  教训：**空转 + 0 字节 log 先怀疑工作库，换目录编译对照，别先改源**。
  （顺带：重建即清掉 m10dbg13..21 旧快照，dbg22 成为库中唯一快照。）

## 工具备忘

- xsim TCL `get_value` 对 reg 数组元素用 `path/x_n_r[0]` 语法可直接读，
  `<ERR>` 容错式逐信号转储是死锁定界的最快手段（免重建）。
- TB `$time` 在 1ns/1ps timescale 下以 **ns** 计数（`%0t` 打印才带 ps）——
  探针窗口阈值若按 ps 写会静默失配（首跑 [xl] 0 行）。
