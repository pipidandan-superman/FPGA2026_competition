# A2 M7 xrowgen —— run8 失败根因（幻影重派发 + 跨 tile IQ 污染）与 run9 全绿

承接 06_a2_m7_xrowgen.md（该文件编码已花，接续记录写在这里）。
RTL：yolo_xrowgen.v V1.1 → **V1.2**（Fix #8 / #8b）。

## run8 判决（V1.1，修 #7/#7b 后）

```
TB_XROWGEN_FAIL errors=30 tiles=66 bytes=29342 cmds=2308 ars=2307 peak_ost=2
```

- tile 0–64 全部位级一致；**30 个错误全部在最后一个 tile t65**，k=0/2/3/4 散车道。
- 关键交叉比对：k=3 行的错误字节**恰好等于 k=2 的黄金字节**（c0,c4,9d,67 / 1c,33,1c）
  → 数据摆放错乱，非算术错。

## t65 几何与手工核对

```
ih=iw=ow=6  ic=2  kh=3  kw=1  sh=sw=1  ph=pw=1  klen=6  nstart=20  nlen=12
xbase=0x8A4F8（=输入平面基址，plane_u32 是平面大小 0x48=72B）
分区 = 3 段：P0(oy=3,ox=2,m=4)  P1(oy=4,ox=0,m=6)  P2(oy=5,ox=0,m=2)
t65 是全库唯一 kh=3 且 kw=1 的 tile；kh2 的 P2 输入行 6 ≥ ih → 零 DMA 段。
```

- **手工推导 16 条合法命令（地址/长度/顺序）与 m7_cmd_trace.txt 前 16 条逐条一致**
  —— 命令地址生成无罪。
- 实际 21 条 = 16 合法 + **5 条幻影**（末组 (ic1,kh2) 的 P0,P1 重复派发直至 IQ 满 8）。
- 单 tile 复现（stim/xr65，快照 m7x18）：**standalone PASS**，仍有幻影（23 条命令）
  → run8 的 t65 失败是**跨 tile 污染**，不是 t65 自身几何错。

## 根因链

1. cg 游标推进链（P_RUN 内）：`adv_now/adv_hold` 都要求 `!last_group_w`；
   末组最后一段派发后落入普通派发分支，`cg_part_r` 越过 pl_last 环绕 4 槽段环，
   把末组各段**重复派发直到 IQ 满**（每 tile 都发生——run8 全程 2308 条命令中
   421 条是幻影）。
2. 幻影命令的 rdone 弹栈落在**下一个 tile 的 P_RUN** 里：start 快照复位了
   iq_wp/iq_rp 但**没复位 iq_cnt** → 下个 tile 带着陈旧计数启动，把陈旧表项
   （带陈旧 iq_g/iq_last）弹掉 → ws_set 提前置位 grp_ready / 覆写 slot_mem
   → em 在数据未到时发射、行内容串位。
3. t64→t65 撞上时序窗口（kw=1 每组 1 拍、em 快）；其余相邻 tile 撞不上是运气，
   不是无害证明。

## 修复（V1.2，黄金路径零变化）

- **Fix #8**：推进链新增分支 `cg_disp_w && grp_last_w && last_group_w →
  cg_part_pend_r <= 0`（末组末段派发后冻结游标，cmd_valid 关断）。
- **Fix #8b**：start 快照补 `iq_cnt_r <= 4'd0`（纵深防御；#8 之后本就归零）。

## 验证

- m7x19 单 tile（xr65）：**cmds=16 ars=16**（幻影消失，恰为手工 16 条）
  TB_XROWGEN_PASS errs=0。
- **run9 全量（快照 m7x19，默认 stim）**：
  `TB_XROWGEN_PASS tiles=66 bytes=29342 cmds=1887 ars=1889 peak_ost=2`
  （66/66 位级一致；2308→1887 = 421 条幻影全消；ars=cmds+2 为收尾在途，正常）。

## 连带影响与工具备忘

- **M10 dbg9 被杀**（RTL 变更，判决失效）：其 X loader 每 n_tile 串行调
  xrowgen，同样的幻影遗留会污染后续 n_tile 的 X 行 → 带修复重启 dbg10
  （L0 done @20766000，与 dbg9 同拍 = 黄金路径时序未变）。
- 07b 工具坑（前段已修，此处留档）：**xsim 对连续赋值里字面量实参的函数调用
  做常量折叠**（t=0 求值一次不再重算）——`part_dma_f(2'd0)` 永远 X。修法
  =内联为普通 wire 表达式；单函数单赋值（每条 assign 只调一次）**不够**。
- xsim.bat 经 cmd 转发 `-testplusarg STIM=../x` 会被参数解析吃掉（"Expected
  a switch but found ."）：值加引号 `-testplusarg "STIM=../stim/xr65"` 可过；
  绝对路径带冒号同样被吃。
- M7 TB 门格式含 run3 期定界探针（[cmd] 首 24、[beat] 首 40、
  m7_cmd_trace.txt 全量命令表）——有界、属门格式一部分，保留。
