# run26 静态 CSR / 地址检查报告（合同 §9/§5 ↔ yolo_gemm_top.v V1.2）

日期：2026-09-20　｜　对照物：`1_docs/yolo_b3_dma_gemm_contract_20260919.md`（v1.1，
SHA-256 b27a4a64…）§9 CSR 表 301-326 行 + §5 物理镜像 154-167 行 ↔
`rtl/GEMM/yolo_gemm_top.v`（V1.2）写译码 411-459 行、读译码 480-503 行、
复位 384-400 行、粘滞/软复位 511-553 行、core 镜像拍 615-637 行。

## A. CSR 逐项对照（§9 表 ↔ 实现）

| 地址 | 寄存器 | 合同字段 | top.v 实现位置 | 判定 |
|---|---|---|---|---|
| 0x00 | ID | RO 期望 0x20260919 | 481 `rdata_r <= 32'h2026_0919` | PASS |
| 0x04 | CTRL | bit0 start / bit1 soft_rst / bit2 err_clr | 412-416 逐位采样 | PASS |
| 0x08 | STATUS | b0 busy,1 job_pend,2 wr_pend,3 ld_done,4 blk_done,5 tile_done,6 bank_err,7 core_proto_err,8 ld_pend_err,9 start_err | 482-485 拼接序 {…err_start,err_ld_pend,proto,bank,tile,blk,ld,wr,job,busy} 逐位一致 | PASS |
| 0x0C | GEOM | [12:0] job_len | 417 写 / 486 读 | PASS |
| 0x10 | ROWVAL | [7:0] row_valid | 418 / 487 | PASS |
| 0x14 | NMASK | [15:0] n_mask | 419 / 488 | PASS |
| 0x18 | JOBCFG | b0 act,1 first,2 last,3 w_grp,4 x_grp | 420-426 / 489-491 | PASS |
| 0x1C | LDGRP | b0 w_grp,1 x_grp | 427-430 / 492 | PASS |
| 0x20 | P_BIAS | signed 32b held | 431；声明 249 `reg signed [31:0]` | PASS |
| 0x24 | P_M | signed 32b held | 432；同上 signed | PASS |
| 0x28 | P_SH | [5:0] shift | 433 / （held，无读口，合同同） | PASS |
| 0x2C | PCTL | [2:0] p_row + bit8 write strobe | 434-437 见 B-① | PASS+注 |
| 0x30/0x34 | WDATA/WDATA2 | 64b 拍槽数据 | 438-439 | PASS |
| 0x38 | WCTL | b0 is_x,1 x_hi,[9:2] be,10 first,11 last | 440-447 | PASS |
| 0x3C | LDSTAT | [1:0] w_ld_ok,[3:2] x_ld_ok,[5:4] w_loaded,[7:6] x_loaded,[8] ld_done,[9] bank_err | 493-495 拼接序一致 | PASS |
| 0x40 | LDLEN | [12:0] ld_w_len,[25:13] ld_x_len | 496 读=core 连线镜像拍（634-635）；桥模式 RO，见 B-② | PASS+注 |
| 0x44 | LUTD | [7:0] wd,[15:8] wa | 448-452 | PASS |
| 0x48 | YSTAT | [15:0] y_count,busy,tile_done_st | 497（y_last_r[15:0],busy=16,tile=17） | PASS |
| 0x4C | YADDR | {6:0} addr 选通 | 453-456 | PASS |
| 0x50 | YDATA | 调试读，按 RAM 延迟 | 498 `{24'd0,cap_dout}`；V1.2 读窗 795-806 | PASS |
| 0x54 | BRGSTAT | b0 ld_busy,1 ld_done_st,2 tlast_err,3 src_conflict,4 y_ovf | 499-500 拼接序一致 | PASS |
| 0x58 | STALLCNT | 读清 | 329 `stall_rd_clr = ar_hs && araddr==8'h58`（AR 拍清） | PASS |

## B. 语义注记（无需改 RTL，run29 驱动纪律收录）

1. **PCTL bit8（0x2C）**：合同写"bit8 write strobe"；V1.2 实现对任意 0x2C 写
   即产生 1 拍 pctl_we（bit8 未检查，实现比合同更宽松）。驱动按合同置 bit8 写
   → 行为逐位等价。已核对 731 行注释"pctl_we 本身即提交次拍起 1 拍有效"。
2. **LDLEN（0x40）桥模式为只读镜像**：ld_w_len_r/ld_x_len_r 是 core 装载器
   长度连线的 1 拍同步副本（634-635），由流节律自动计数（§7 桥语义），PS 写
   0x40 落 default → SLVERR。TB 全程只读对账（TB 418/530/836，S2"S2 ld_done/
   LDLEN 对账"、S5a"block corrupted LDLEN"检查）。合同 §9 表该行仅列字段未
   声明可写——一致。**run29 驱动不得写 0x40**。
3. **未映射/只读地址写响应**：代码 default → SLVERR（458，fail-closed）；
   457 行注释"写忽略、OKAY"与代码不符（注释失准，行为保留 SLVERR 更安全；
   TB axi_write 检查 bresp==00，S1-S7 全绿证明所有 TB 写均落在映射地址）。

## C. 复位规则（§9）

- **外部 rst 清全部配置寄存器**：top.v 387-400（GEOM/ROWVAL/NMASK/JOBCFG/
  LDGRP/P_BIAS/P_M/P_SH/WDATA/WDATA2/WCTL 拍槽/PCTL/LUTD/YADDR 全清）
  ——R4 修复落盘，S5a/§11 仿真已验证。PASS
- **soft_rst 只清运行态、配置保留**：543-549（状态/粘滞/y 计数/soft_cnt）+
  643-647（桥相位/窗/beat 计数）；配置寄存器不在列表。PASS
- **err_clr 只清五错误位**（550-553），不影响运行态。PASS
- **STALLCNT 读清**（329）。PASS

## D. §5 地址常量 ↔ packer/meta 实测

| 常量 | 合同 | packer meta（b3_conv0_meta.json） | 判定 |
|---|---|---|---|
| LUT 区 | 0x0..0x100（256B） | lut 写入 @0x0 256B（selfcheck y_arena/guard 之外由构造保证） | PASS |
| LOAD_BASE | 0x100 | load_base=256 | PASS |
| load arena | 0x100..0x1FA400（2,073,600B=3200×648） | mm2s_bytes_total=2,073,600；块全 648B、SAR 步进 648、全 8B 对齐 | PASS |
| Y_BASE | 0x1FA500 | y_base=2,073,856 | PASS |
| y arena | 0x1FA500..0x25E500（409,600B=3200×128） | s2mm_bytes_total=409,600；DST 全 8B 对齐；初值 0xA5 | PASS |
| guard | ..0x25F000 0xA5 | guard_0xa5=true；镜像总长 2,486,272B | PASS |
| 镜像 SHA-256 | — | be4d56f067b91d0227312d164edb6ee802ebc212ad7b27d83d58aa540e63832f | 固化 |

## E. 结论

**run26 静态 CSR/地址检查 PASS**：§9 全 23 行逐项一致（2 行注记 B-①②为
宽松侧/桥语义注记，非违例）；复位三分规则（rst 全清/soft 只清运行态/err_clr
只清错误）静态证明成立；§5 全部地址常量与 packer 实测互证。B-②/B-③ 作为
run29 驱动纪律转录（不写 0x40；RO 地址写将得 SLVERR）。
