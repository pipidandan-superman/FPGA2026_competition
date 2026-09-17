# A2 M7 新门：yolo_xrowgen V1.0（2026-09-17，授权链"按照1做"+"先做A2"+"继续"）

**状态**：见判决行（文末）。本笔记 = M7 新门 bring-up 全记录：向量集生成器
`sim/xrowgen_vecgen.py`（自检 + 覆盖断言）→ TB `sim/tb_yolo_xrowgen.v`
（真 xbuf + 真 dma + M9 款多在途 BFM，rdata = xram 镜像字节而非哈希）→
RTL `rtl/yolo_xrowgen.v` 缺陷迭代 → 门判据 TB_XROWGEN_PASS。

- 合同：与 addrgen V1.3 逐位同集 (k,n,value)；值 = pad ? (first ? −128 : 0)
  : X_plane[ic·IH·IW + ih·IW + iw]；k = ic·KH·KW + kh·KW + kw；
  ih = oy·sh+kh−ph；iw = ox·sw+kw−pw；oy/ox = divmod(n_start+n, OW)。
- 向量集：66 tiles / 29342 黄金字节 / 1887 cmds / 镜像 566720B；
  parts={1:54, 2:5, 3:5, 4:2}、零-DMA 组 116、最大段 40B(≤SEG_W·8=48B)、
  pad 2174 / 非 pad 27168、−128 pad 1654 / 0 pad 520、真实 conv0 tile 52。
  案例：real00（真实几何+真实字节+数据闭合）、syn_k2304（IC256 回卷）、
  syn_1x1、syn_edge_first（OW=4=P_MAX 边界）、syn_tail、syn_allpad、
  syn_wrap、syn_ow2、syn_rect13/31（非方核）。

## 门判据（TB）

每 tile：we 覆盖（每 k 恰一次、waddr<k_len、we 拍数===k_len）+ done 后
终态读回逐 (k, lane<n_len) 比对 val_i8.hex；cmd 轻校验（8 对齐、len%8==0、
8≤len≤48、addr≥xbase−8、addr+len≤xbase+plane+64）；err_o 不许脉冲；
peak_ost≥2（前视确实 engage）。BFM = M9 款（burst 队列深 4、头延迟
4+(rng&7)、随机 arready/rvalid 停停、xorshift 种子 32'h71C0A517）。

## 缺陷留档（RTL 2 处 + TB 2 处，全数被门捕获）

1. **RTL #1（cg_grp_cmd_r 永不置位）**：cg 派发含 DMA 的 part 时未置
   `cg_grp_cmd_r`，`grp_cmd_next_w` 退化为"当前 part 是否有 DMA"——混合组
   （前 part 有 DMA、末 part 零-DMA）由 cg 提前置 grp_ready，em 在 DMA 仍在途
   时读空槽。修：dispatch 时 `cg_grp_cmd_r <= 1'b1`（游标推进时清零已有）。
   症状：run2 t0 k3/k4 槽位 XX。
2. **RTL #2（part_row0_w 无符号污染）**：
   `part_ih0_w * $signed({16'd0, iw_r}) + {{21{part_iwlo_w[10]}}, part_iwlo_w}`
   ——第二操作数是裸 concat（无符号），按 Verilog 规则**整个表达式**（含乘法）
   按无符号求值：ih0=−1 变 0x3FFFF，×iw=320 → 0x4FFFEC0，再无符号加 −1 →
   **0x04FFFEBF**（探针实测逐位吻合；正确值 0xFFFFFEBF）。负 row0 的 tile
   命令全部 +0x05000000 偏置（run1 104 条、OOB 读→槽位 X 连带缺陷 #3 假象）；
   ih0≥0 的 tile 数值不受影响（无符号=有符号）。修：concat 包 `$signed()`。
   全文件同类审计：其余 concat 参与算术处要么全 $signed、要么操作数全非负
   ——仅此一处。教训：**符号扩展 concat 必须包 $signed 再进混合表达式**。
3. **TB #1（读回 NBA 竞争，run1）**：while 条件在 posedge 活动区读到
   pre-NBA 值、#1 后 vld 脉冲已过 → 4415 假 "no vld"。修：全程 negedge 采样。
4. **TB #2（xbuf V2.2 ENB=ren_i 语义，run4 定位）**：读任务 ren 只拉高 1 拍
   ——BMG 端口 B 源语输出寄存器开启（V2.2 合同）且 ENB=ren_i：P1 锁地址、
   P2 输出寄存器 ENB=0 **保持旧值** → 每次读回拿到上一个 k 的行、首读 00。
   症状极具迷惑性：行 k 读回 = 拍 k−1 的数据、行 0 = 00（一度误判为 RTL
   写地址偏移）。修：ren 保持到 vld 出现再撤 + 2 拍冲刷 ren_d1→vld 链。
   教训：**V2.2 两拍读延迟 = 两级都要 ENB=1，ren 必须贯穿第 2 拍**（K 环
   流式读 ren 常高不受影响，逐次单读的 TB 才踩中）。
5. **疑点排除（超前门 mod-4 回绕）**：lead_d = cg+1−em (mod 4) ≤1 在
   cg 超前 3 时理论放行，但 k=cg−em 只能 0→1（k=1 即 lead_d=2 阻塞），
   回绕不可达，门是稳的（推理留档，无需改码）。
6. **RTL #6（iq_last 标几何末段而非末命令段 → 死锁）**：混合组（末段
   零-DMA）里 `iq_last <= grp_last_w`（p==pl_last）的那一段**不入 iq**，
   组内无任何表目带 last → ws 永不置 grp_ready → em 等待、cg 超前门
   hold、整tile 无 done。m7x12 起（#1 修好后 cg 不再提前置位）在
   syn_edge_first（t56，恰 4 段=P_MAX、每 kh 组 3 命令+1 零-DMA）确定性
   复现。TCL 状态双快照（run 416ms + get_value ×2 间隔 1ms）实锤：
   SNAP A==B：phase=P_RUN、em_cnt=2 等 grp_ready[0]=0、cg_cnt=3
   adv_pend=1、iq_cnt=0 全消费。修：逐段 DMA 判定提为函数 part_dma_f
   （单源，dma_cur_w = part_dma_f(cg_p_w)），组内命令图 part_cmd_w，
   `iq_last <= dma_cur && 后续段无命令`。m7x11 不挂是因 #1 的错误提前
   置位恰好兜住——**两缺陷互斥掩盖**，#1 修复即暴露 #6。
7. **诊断弯路留档（避免复踩）**：①"零延迟活锁"误判——xsim 日志
   LastWriteTime 停在启动后 1 秒是**缓冲_flush 假象**，xsimk 100% CPU
   不能区分时间冻结/慢速推进（本案是推进中的死等）；判据应是：双快照
   状态静止 + 时刻仍在走。②看门狗 wdt_ms=240000 = **240 秒**仿真时间
   ≈ 24G 拍，对 700ms 量级的全量 sim 永远打不响（形同虚设；后续门若
   需要，改按总拍数或 tile 数设限）。③xsim TCL：状态转储用
   `get_value`（无 examine），路径**斜杠**制（点号报 No such HDL
   object）；tcl 文件**不可带 BOM**（PowerShell Set-Content -Encoding
   utf8 会写 BOM，首行即 invalid command，用 Write 工具落盘）。

## 已知非阻塞项（本门不处理，留档）

- **每 (ic,kh) 组约 2~4 万拍的均匀拖累**（t53=217ms/768 组、t54=12ms/64
  组、real00 tile≈3ms/9 组；run2 起就有，与缺陷无关）。疑似 cg 零前视
  （超前门实为"cg 须等 em 完成当前组才推进"）与 BFM 抽签停顿串行叠加，
  但量级差 ~300× 未完全解释；门用途可容忍（全量 ~10 分钟墙钟）。M10/
  M11 接真实位宽/走序时再究。

## 运行记录（xsim，cmd //c 绝对源+相对日志）

| run | 快照 | 结果 | 要点 |
|---|---|---|---|
| 1 | m7x10 | FAIL 29203 | cmd +0x05000000×104、TB#1 假错 4415 |
| 2 | m7x11 | FAIL 24788 | t0 k0=00（TB#2 假象）、k3/k4 XX（RTL#1）；66 tile 跑完 |
| 3 | m7x12 | 无判决 | 探针实锤 pt0=04fffebf（RTL#2）；t56 起死等（RTL#6） |
| 4 | m7x13 | 无判决 | RTL#2 修复：命令全在界、槽位真数据；残差全 = TB#2 行偏移；t56 死等 |
| 5 | m7x14 | 无判决 | TB#2 修复（ren 贯穿第 2 拍）；t56 死等（→ 状态转储定性 #6） |
| 6 | m7x15 | 无判决 | 逐 tile 进入打印 + $time 定位 t56；TCL 双快照实锤 #6 |
| 7 | m7x16 | 见判决 | RTL#6 修复（iq_last → 末命令段） |

## 判决

**待 run7（占位，绿后回填：PASS 行原文 + n_cmp/cmds/ars/peak_ost 数字 +
证据目录 4_metrics/logs/2026-09-17_yolo7020_m7_xrowgen/ + 设计笔记 §2.8
M7 行勾选）。**
