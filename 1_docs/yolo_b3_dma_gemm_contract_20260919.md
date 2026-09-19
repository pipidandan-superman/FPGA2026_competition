# B3 DMA→GEMM→DDR 接口与验证合同（P1.1 修订版 v1.1）

日期：2026-09-19 ｜ 状态：修订候选版，待 run26 实现与验证

本版重新定义了物理镜像、装载块地址、Conv0 的 W/X 打包、y 输出排列、寄存器清除语义和验收门。它替代同路径旧版 P1.1。D1–D4 的方向保持不变，但旧版“四段 W/X 表”与“单次 648B 连续 DMA”之间未定义装载缓冲的问题已在本版闭合。

本文件冻结的是 B3 目标接口合同，不表示当前工程已经完成接线或板级验证。当前 display_test.bd 仍需从 DMA 回环改为 DMA→GEMM→DMA；run25 只证明已有 100MHz 回环基线。所有 RTL、BD/IP、驱动、打包脚本、仿真和板测判据必须以本版为输入，并在 run26–run29 中留下证据。

## 0. 适用范围与术语

### 0.1 范围

本合同覆盖：

- PS 侧 CMA 镜像及 Conv0 packer；
- AXI DMA direct-register 模式下的 MM2S 装载和 S2MM 回收；
- yolo_gemm_top.v 内的 AXI-Stream 装载桥、y 打包器和 FIFO；
- AXI-Lite CSR 配置、错误清除、轮询和 reset 纪律；
- G4 仿真、B3.1 Conv0 串行板测和 P1.3 K 扩展门。

本合同不覆盖摄像头、HDMI/UDP、PPU、整网调度、IRQ 优化和最终 FPS 发布。

### 0.2 名词

| 名词 | 定义 |
|---|---|
| K | 当前 GEMM 任务的 reduction 长度；Conv0 为 27 |
| P_TO | 输出行数，当前为 8 |
| P_TN | 输出列数，当前为 16 |
| g | 8 行 row-group；g=0 对应 OC 0–7，g=1 对应 OC 8–15 |
| n_tile | 空间 tile 编号，Conv0 为 0–1599 |
| b | DMA 装载块编号，b=2*n_tile+g，范围 0–3199 |
| job | 一次 core feeder 作业；B3.1 每个装载块对应一个完整 job |
| load arena | 物理 CMA 镜像中按三拍节律交错排列的 648B 块区 |
| y slot | 物理 CMA 镜像中接收一个 row-group tile 的 128B 槽 |

## 1. 权威源与版本边界

| 编号 | 事实域 | 权威源 |
|---|---|---|
| A1 | CSR、AXI-Stream 端口、y 打包、状态位 | 2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_top.v |
| A2 | 64-bit W/X 装载、组安全、长度闭口 | 2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_bank.sv |
| A3 | DMA 规格与寄存器模型 | axi_gemm_test 的 axi_dma_0 XCI、run24 驱动与 B2 证据 |
| A4 | 权重、量化、LUT 和 per-OC 参数 | 2_fpga/3_yolo_zynq/rom_data/quant.json、manifest |
| A5 | 任务几何和 first-layer z-sum | 2_fpga/3_yolo_zynq/rom_data/schedule.json |
| A6 | 算术与 golden | 2_fpga/3_yolo_zynq/sim/golden_extract.py、gemm_golden_replay.py、run04 |
| A7 | 板级 CMA、HP0、时钟和恢复纪律 | zynq-pynq-overlay-workflow skill、P0-B run02 |

本版涉及的内容若与旧版文字、旧注释或未生成的 XCI 冲突，以本版和 A1–A7 的实际文件为准；任何改动都必须更新本文版本号和 SHA-256。

## 2. 设计目标与当前状态

### 2.1 目标拓扑

~~~text
CMA DDR ──MM2S──AXI-Stream(64b)──▶ yolo_gemm_top 装载桥
                                      │ W/X 三拍解码
                                      ▼
                                  GEMM bank/core
                                      │ y[oc][n] 流
                                      ▼
                 y 打包器──32-word FIFO──AXI-Stream(64b)──▶ S2MM ──▶ CMA DDR
~~~

- MM2S 和 S2MM 继续共用 HP0；不新增 AXI memory interconnect。
- AXI-Lite WDATA/WDATA2/WCTL 拍槽保留，供 B1 回归和掩码 tile 调试；B3 流路径运行时禁止同时使用两路源。
- ycap/CSR 回读保留，但 D2 的全有效 tile 走 S2MM；B3.1 不用 ycap 代替 S2MM。
- B3.1 只支持 row_valid=0xFF、n_mask=0xFFFF 的完整 Conv0 tile。

### 2.2 实现状态声明

以下状态在文档发布时必须如实记录：

1. 源 RTL 已有目标 AXI-Stream 端口，不等于 BD/IP 已连接。
2. display_test.bd 必须删除 MM2S→S2MM 回环，并连接两条真实流。
3. 生成的 .xci/.bd/.bit/.hwh 必须能检索到 s_axis_ld_* 和 m_axis_y_*。
4. 在 run27 G4、run28 bitstream 和 run29 B3.1 证据齐全前，B3 不得标记 PASS。

## 3. P1.1 七项接口合同

| 编号 | 合同 | 正式要求 |
|---|---|---|
| C1 | DMA | axi_dma_7.1、SG 关闭、direct-register、MM2S/S2MM 64b、SG_LENGTH_WIDTH=20、DRE 关闭；所有 B3 地址 8B 对齐 |
| C2 | HP0/CMA | MM2S 读和 S2MM 写均走 HP0；CMA 物理连续；镜像基址 4KiB 对齐；分配区带 4KiB guard page |
| C3 | 一次传输 | 一个 MM2S BTT 对应一个完整装载块；B3.1 BTT=648；DMA 在末拍产生 TLAST |
| C4 | 物理镜像 | 物理布局为 [LUT][load arena][y arena]；W/X 是 load arena 内的逻辑视图，不再声称为相邻的独立物理段 |
| C5 | AXI 边界 | 源/目的地址均 8B 对齐，BTT 为 8 的倍数；允许跨 4KiB，由 DMA/interconnect 拆分 burst；driver 必须记录每次 SAR/DST/BTT |
| C6 | Cache | B3.1 先做 cache/no-cache 成对 exact compare；在结果证明免维护前，driver 强制 flush MM2S 源、invalidate S2MM 目的并执行屏障 |
| C7 | 完成方式 | B3.1 使用轮询；中断只在后续性能阶段重新立项，不改变本合同 |

## 4. Conv0 数值和空间合同

### 4.1 任务参数

schedule.json 的 model.0 必须满足：

| 参数 | 值 |
|---|---:|
| 输入 | [3,320,320]，CHW |
| 输出 | [16,160,160]，CHW |
| kernel/stride/pad | 3×3 / 2×2 / 1×1 |
| K | 3*3*3=27 |
| P_TO/P_TN | 8/16 |
| 空间 tile | 16 columns |
| 空间 tile 数 | 160*ceil(160/16)=1600 |
| row-group 数 | ceil(16/8)=2 |
| 装载块数 | 1600*2=3200 |

量化和算术规则：

- 输入字节由 x_q = int8(canvas_u8 - 128) 得到；越界 padding 的 x_q=-128，序列化为 0x80。
- 权重存储形状为 [oc][ic][kh][kw]，K 展开为 k=ic*9+kh*3+kw。
- 首层 bias 为 b_eff[oc]=b_q[oc]+z_sum_w[oc]，其中 z_sum_w 来自 schedule；硬件不得再次加 128 项。
- P_M、P_SH、RNE、饱和和 LUT 地址遵循 A6；LUT 地址是饱和后的 q7+128，不是 q7 的原始补码字节。
- Conv0 使用 act_en=1，所有 16 个 OC 都有独立 b_eff/M/shift。

### 4.2 空间 tile 编号

对 n_tile=0..1599：

~~~text
oy      = n_tile // 10
tx      = n_tile % 10
ox0     = 16 * tx
ox(c)   = ox0 + c,  c=0..15
b       = 2*n_tile + g
oc(r)   = 8*g + r,  r=0..7
~~~

ox0 的最大值为 144，故每个 Conv0 tile 都完整落在 160 列范围内。该顺序是唯一合法的 pack、DMA、golden 和 y reorder 顺序。

### 4.3 X 窗口取值

对每个 k 先还原：

~~~text
ic = k // 9
kh = (k % 9) // 3
kw = k % 3
iy = 2*oy + kh - 1
ix(c) = 2*ox(c) + kw - 1
~~~

若 iy 或 ix(c) 越界，x_byte=0x80；否则 x_byte=uint8(canvas_u8[ic][iy][ix(c)]-128)。pack 脚本必须在生成镜像时对所有 k,c 做一次边界自检，并输出首块和四个边界 tile 的十六进制摘要。

## 5. 物理 CMA 镜像布局

### 5.1 Conv0 固定布局

镜像基址记为 B，B % 4096 == 0。物理布局如下：

| 区域 | 偏移 | 大小 | 内容 |
|---|---:|---:|---|
| LUT | 0x000000 | 0x000100 = 256B | lut_i8[0..255]，仅供 PS 写 CSR LUTD |
| load arena | 0x000100 | 0x1FA400 = 2,073,600B | 3,200 个交错 W/X 装载块 |
| y arena | 0x1FA500 | 0x064000 = 409,600B | 3,200 个 128B y slot，初始化为 0xA5 |
| 有效镜像终点 | 0x25E500 | — | B+0x25E500 之后不得访问 |
| guard page | 0x25E500..0x25EFFF | 0xB00 | 只用于越界检测，不作数据区 |

表中的偏移区间按左闭右开解释；有效镜像范围为 [B, B+0x25E500)，guard 范围为 [B+0x25E500, B+0x25F000)。

实际 CMA 申请至少为 0x25F000 字节，且 B 4KiB 对齐。驱动必须记录申请长度、虚拟地址、物理地址和 guard 初始化结果。

### 5.2 block 和 y slot 地址

~~~text
LOAD_BASE(B) = B + 0x000100
Y_BASE(B)    = B + 0x1FA500
BLOCK_SAR(b) = LOAD_BASE(B) + 648*b
Y_DST(b)     = Y_BASE(B) + 128*b
~~~

其中 0<=b<3200。所有 BLOCK_SAR 和 Y_DST 都是 8B 对齐；BLOCK_SAR 可以跨 4KiB，不能因为跨页而修改 BTT 或插入软件分段。

### 5.3 block 内部布局

每个块占 648B = 81 个 64-bit beat，按 k=0..26 交错：

~~~text
block_offset(3*k+0) = 24*k + 0   : W[k]   8B
block_offset(3*k+1) = 24*k + 8   : Xlo[k] 8B
block_offset(3*k+2) = 24*k + 16  : Xhi[k] 8B
~~~

W 和 X 的逻辑视图不再占用另外的物理段：

- W 逻辑大小为 3200*27*8=691,200B；
- X 逻辑大小为 3200*27*16=1,382,400B；
- 两者正好组成 3200*648=2,073,600B 的 load arena。

pack 脚本可以先生成独立的 canonical W/X 表，但最终 CMA 镜像必须按本节的交错布局写出。driver 不得从分离的 W/X 表直接使用 SAR=BLOCK_SAR，也不得在 DMA 运行期间临时修改 load arena。

### 5.4 LUT 和参数归属

- LUT 内容从 lut_i8.bin 读出后，PS 在 core idle 时向 0x44 LUTD 写 256 次；LUT 不经过 AXI-Stream。
- P_BIAS/P_M/P_SH 不进入 CMA 镜像；每个 row-group 的 8 行通过 0x20/0x24/0x28/0x2C 写入 array parameter store。
- 参数写入必须在对应 tile 的 start 前完成；正在计算或流装载时不得写 PCTL/LUTD。

## 6. 装载块的逐字节打包合同

对 block b 的 row-group g、空间 tile n_tile，定义：

~~~text
Wm[r][k] = weight_q[8*g+r][ic][kh][kw]
Xm[c][k] = x_byte(oy, ox0+c, ic, kh, kw)
~~~

每个 beat 的低地址字节是 lane 0，完整块内容为：

| beat i=3*k+p | is_x | x_hi | lane 0..7 |
|---:|---:|---:|---|
| p=0 | 0 | 0 | Wm[0..7][k] |
| p=1 | 1 | 0 | Xm[0..7][k] |
| p=2 | 1 | 1 | Xm[8..15][k] |

因此：

- i=0 为 wr_first=1；其余 beat wr_first=0；
- i=80 为 wr_last=1，且 DMA TLAST 必须落在该 beat；
- be=0xFF，不支持 B3 流中的 partial lane；
- ld_w_len=27、ld_x_len=27；
- job_len=27；job_first=1、job_last=1；
- ld_w_grp=ld_x_grp=job_w_grp=job_x_grp=g。

pack 脚本必须提供 block[0]、block[1]、block[3198]、block[3199] 的 SHA-256，W/X 三拍计数 27/27，所有 block 长度 648B，且 BLOCK_SAR(b+1)-BLOCK_SAR(b)=648。

## 7. y 输出和 DDR 重排合同

### 7.1 core 流顺序

core tail 按 OC 主序、N 次序输出：

~~~text
(r=0,n=0..15), (r=1,n=0..15), ... , (r=7,n=0..15)
~~~

其中 r 是 row-group 内行，n 是 tile 内列。bridge 每收到 8 个连续 y beat，组成一个 64-bit word，DDR 低地址字节对应最先到达的 y beat。

### 7.2 y slot 字节公式

令 q=0..15 为 64-bit word 编号、lane=0..7 为 word 内字节：

~~~text
r    = q // 2
c    = 8*(q % 2) + lane
y_slot_byte[q*8 + lane] = y_core[r][c]
~~~

因此：

~~~text
Y_DST(b) + 16*r + 8*(c//8) + (c%8)
    = output[oc=8*g+r][oy][ox=ox0+c]
~~~

m_axis_y_tlast 只在 q=15 的最后一个 word 上为 1；S2MM BTT 固定为 128B。板测比较前，driver 按上式将 3,200 个 slot 还原成 [16][160][160] CHW，再与 G0 y_exp_i8.bin 比较。

### 7.3 y FIFO

- 8 个 y beat 打包成 1 个 64-bit word；FIFO 深度 32 word；
- FIFO 满且无同拍 pop 时丢弃该 word 并置 y_ovf；core y 无反压；
- B3.1 必须在 start 前完成 S2MM 配置并使其 ready，保证一个完整 16-word tile 无 overflow；
- G4 必须注入 S2MM 延迟和 m_axis_y_tready 反压，验证 FIFO 满、TLAST 和错误恢复；
- ycap/CSR 回读和 AXI-Stream 回收是两条独立路径，ycap 不得被当作 S2MM 成功证据。

## 8. AXI-Stream 桥和错误语义

### 8.1 端口和握手

端口固定为：

~~~text
s_axis_ld_tdata[63:0],  s_axis_ld_tvalid,  s_axis_ld_tready,  s_axis_ld_tlast
m_axis_y_tdata[63:0],   m_axis_y_tvalid,   m_axis_y_tready,   m_axis_y_tlast
~~~

两条流与 AXI-Lite 共用 FCLK0 100MHz 和 peripheral_aresetn。B3 不使用 TKEEP/TSTRB；所有 accepted beat 的 8 个 byte 都有效。

s_axis_ld_tready=0 时，MM2S 必须保持 tdata/tvalid/tlast 稳定；bridge 只在 tvalid && tready 时推进 i。STALLCNT 计数 tvalid && !tready 的周期。

### 8.2 错误和清除

| 错误 | 条件 | 状态位 | 清除 |
|---|---|---|---|
| tlast_err | TLAST 不在 Xhi，或 accepted beat 数不是合法块长度 | BRGSTAT[2] | CTRL.err_clr 或 CTRL.soft_rst |
| src_conflict | 流传输期间写 WCTL，或 WCTL pending 时收到流 beat | BRGSTAT[3]、STATUS[8] | 同上 |
| y_ovf | y FIFO 满且无 pop | BRGSTAT[4] | 同上 |
| core_proto_err | core 自己的 first/last/长度检查失败 | STATUS[7] | core reset/soft reset，按 A1 |
| bank_err | bank 组/地址/装载检查失败 | STATUS[6] | core reset/soft reset |

软件的总错误判据为 STATUS[6..9] != 0 或 BRGSTAT[2..4] != 0。BRGSTAT 的 ld_busy 为实时位，ld_done_st 为 sticky 位；BRGSTAT 本身不因读取清零。CTRL.err_clr 清除 bridge sticky 错误、ld_pend_err 和 start_err，不能清除 ID 或配置参数。STALLCNT 读取后清零，driver 必须在每个 tile 结束时读一次并留档。ld_done_st 和 tile_done_st 都是累计/粘滞诊断位，不能单独证明当前 block 已完成；当前 block 必须同时满足对应 DMA Idle、STATUS busy=0、无错误和本次 job 的 tile_done 观察。

缺失 TLAST 无法由一个已经停止发送的 AXI-Stream 自行产生新的握手事件；因此 G4 由 BFM watchdog 判为缺失 TLAST，板级由 DMA BTT/Idle timeout 判为失败。run26 必须确认 bridge 对 accepted beat 计数和 TLAST phase 都做检查，不能只检查 phase=2。

### 8.3 双源互斥

B3 driver 只使用 AXI-Stream 装载，禁止在同一个 tile 的 DMA 期间写 WCTL。B1 回归只使用 WDATA/WDATA2/WCTL，禁止同时启动 MM2S 流。冲突发生时，WCTL beat 丢弃、bridge beat 保持 AXI 流协议，错误必须可读出；driver 不能把“DMA 完成”当作“无冲突”。

## 9. CSR 地址和字段合同

下表保持 0x00–0x50 原地址，只在 0x54/0x58 追加 bridge 状态：

| 偏移 | 名称 | 字段/写入纪律 |
|---:|---|---|
| 0x00 | ID | RO，期望 0x20260919 |
| 0x04 | CTRL | bit0 start，bit1 soft_rst，bit2 err_clr |
| 0x08 | STATUS | bit0 busy，1 job_pend，2 wr_pend，3 ld_done，4 blk_done，5 tile_done，6 bank_err，7 core_proto_err，8 ld_pend_err，9 start_err |
| 0x0C | GEOM | [12:0] job_len，B3.1=27 |
| 0x10 | ROWVAL | [7:0] row_valid，B3.1=0xFF |
| 0x14 | NMASK | [15:0] n_mask，B3.1=0xFFFF |
| 0x18 | JOBCFG | bit0 act_en，1 first，2 last，3 w_grp，4 x_grp |
| 0x1C | LDGRP | bit0 w_grp，bit1 x_grp |
| 0x20 | P_BIAS | signed 32-bit held value |
| 0x24 | P_M | signed 32-bit held value |
| 0x28 | P_SH | [5:0] shift |
| 0x2C | PCTL | [2:0] p_row，bit8 write strobe；只在 idle 写 |
| 0x30/0x34 | WDATA/WDATA2 | 64-bit WCTL 拍槽数据 |
| 0x38 | WCTL | bit0 is_x，1 x_hi，[9:2] be，10 first，11 last |
| 0x3C | LDSTAT | W/X ready、loaded、ld_done、bank_err |
| 0x40 | LDLEN | [12:0] ld_w_len、[25:13] ld_x_len |
| 0x44 | LUTD | [7:0] wd、[15:8] wa；idle 写 256 次 |
| 0x48 | YSTAT | [15:0] y_count、busy、tile_done_st |
| 0x4C | YADDR | ycap 调试读地址 |
| 0x50 | YDATA | ycap 调试读数据，按 A1 等待 RAM 延迟 |
| 0x54 | BRGSTAT | bit0 ld_busy，1 ld_done_st，2 tlast_err，3 src_conflict，4 y_ovf |
| 0x58 | STALLCNT | tvalid&&!tready 周期数；读取后清零 |

实现要求：外部 reset 必须清零所有配置寄存器、sticky 状态、计数器和 FIFO；soft reset 清 core/bridge 运行状态和错误，但保留 LUT、PCTL 参数和普通配置寄存器。当前 top RTL 的配置寄存器 reset 赋值仍需在 run26 修正或以静态检查证明；在此修正前不能宣称合同闭合。

## 10. B3.1 driver 正典时序

### 10.1 初始化

1. 检查板卡身份、bitstream ID、FCLK0=100MHz、DMA halted/idle、HP0 owner。
2. 分配 0x25F000 字节 CMA，确认物理基址 4KiB 对齐；记录 virtual/physical 地址。
3. 填充 LUT、load arena 和 y arena；y arena 和 guard page 初始化为 0xA5。
4. 对源镜像做 pack 自检；必要时 flush 整个镜像并执行内存屏障。
5. 写 LUTD 256 次，确认 core idle；清 bridge/core sticky 错误。

### 10.2 每个 block b 的串行时序

对 b=0..3199 顺序执行：

1. 从 b 计算 g=b&1、n_tile=b>>1、oy/tx/ox0。
2. 写 8 行 PCTL：p_row=r，数据取 oc=8*g+r 的 b_eff/M/shift。
3. 写 GEOM=27、ROWVAL=0xFF、NMASK=0xFFFF、JOBCFG=act=1,first=1,last=1,w_grp=g,x_grp=g、LDGRP=g,g。
4. arm S2MM：DST=Y_DST(b)、BTT=128；确认通道未报错并已 ready。
5. flush BLOCK_SAR(b)..+648（若 cache policy 仍未通过免维护门），再 arm MM2S：SAR=BLOCK_SAR(b)、BTT=648。
6. 写 CTRL.start；不得在该 DMA 期间写 WCTL、PCTL 或 LUTD。
7. 轮询 MM2S/S2MM halted+idle、STATUS busy=0、STATUS[6..9]=0、BRGSTAT[2..4]=0、BRGSTAT[1]=1（累计诊断）、YSTAT.tile_done_st=1；BRGSTAT[1] 不得作为当前 block 唯一完成条件。
8. 读取 STALLCNT 并清零；记录 MM2S/S2MM BTT、SAR、DST、错误状态和完成耗时。
9. 进入下一个 b。B3.1 不允许跨 tile outstanding；P1.3 才评估重叠。

### 10.3 结束和数据校验

1. 对 y arena 做 cache invalidate（若尚未证明免维护），按 §7.2 重排成 [16][160][160]。
2. 检查 409,600 个输出字节与 G0 golden 逐字节相等。
3. 检查 y arena 之外的 guard byte 仍为 0xA5；y arena 内的 409,600B 应全部覆盖，不允许残留哨兵。
4. 核对累计 MM2S=2,073,600B、S2MM=409,600B、accepted stream beats=259,200。
5. 读取并保存最终 STATUS/BRGSTAT/YSTAT、DMA 状态、STALLCNT CSV、输出 SHA-256。

## 11. Reset、错误恢复和禁止动作

- 不得在 MM2S/S2MM active、bridge ld_busy=1、core busy 或 y FIFO 非空时发 soft_rst。
- 发生 timeout 时先停止后续 job，保存 CSR/DMA 状态和最后一块地址；不得直接复用同一 CMA 镜像而跳过 cache 维护。
- soft_rst 会清除 core/bridge 运行状态以及 bank 的 `w_loaded/x_loaded` 元数据；RAM 中的旧字节不等价于“已装载”。因此 soft_rst 后，在重新装载对应 W/X block 且 `LDSTAT` 再次确认 `w_loaded=1、x_loaded=1` 之前，禁止启动新 job。
- recovery 顺序：停止 DMA → 确认 halted → `CTRL.err_clr` → 必要时 `soft_rst` → 重新写配置/LUT/PCTL → 重新 arm S2MM → 通过 MM2S 重新装载当前 block 的 W/X → 读 `LDSTAT` 确认 loaded → 最后才允许 `CTRL.start`。
- 任何 tlast_err/src_conflict/y_ovf/bank_err/core_proto_err 都使当前 B3.1 run 失败；恢复后的重跑必须生成新的 run 记录，不能覆盖失败证据。
- guard page、DMA BTT、物理地址和 mirror SHA 必须在每次 run 中留档。

## 12. G4 仿真和负向覆盖

### 12.1 必做正向用例

- 单 block：b=0、b=1、b=3198、b=3199，检查 W/X 三拍和 y slot 地址。
- Conv0 全量：3200 blocks，输出与 G0 golden 逐字节相等，stream accepted beat=259,200。
- 随机 s_axis_ld_tready：覆盖 ready 常高、单周期气泡、长反压；数据和 TLAST 不变。
- 随机 m_axis_y_tready：覆盖 FIFO 正常、满边界和恢复；不能产生错误的 y slot。
- 4KiB crossing：至少覆盖 BLOCK_SAR 位于 4KiB 页尾附近的实际 DMA 地址。
- cache/no-cache 双跑：输入、输出、镜像和 CSR 配置相同，两个结果 SHA-256 必须相同。

### 12.2 必做负向用例

- TLAST 提前一拍、延后一拍、缺失 TLAST；期望 tlast_err 且 driver 拒绝 PASS。
- 流传输期间写 WCTL；期望 src_conflict 和 ld_pend_err。
- S2MM 延迟导致 FIFO 满；期望 y_ovf，并验证错误清除后可重跑。
- BTT 非 648、BTT 非 8 的倍数、SAR/DST 非 8B 对齐；driver 在软件侧拒绝提交。
- row_valid/n_mask 非全有效时走 ycap，B3 S2MM 入口拒绝该任务。

G4 PASS 条件：正向用例 nerr=0、CSR/DMA 无错误、流量守恒；负向用例只在预期错误位出现且无死锁时通过。

## 13. BD/IP/实现验收

run28 之前必须完成：

1. BD 中删除 axi_dma_0_M_AXIS_MM2S → axi_dma_0_S_AXIS_S2MM 回环。
2. 连接 axi_dma_0/M_AXIS_MM2S → u_yolo_gemm/s_axis_ld_*。
3. 连接 u_yolo_gemm/m_axis_y_* → axi_dma_0/S_AXIS_S2MM。
4. 两个流口和 AXI-Lite 共用同一个 100MHz FCLK0/reset 域。
5. 重新生成 XCI/BD/bit/HWH，静态检索端口和连接；不得只验证源码 top。
6. 记录 WNS/WHS@100MHz、LUT/FF/DSP/BRAM 的统计口径。BRAM 必须同时列 BRAM36 和 RAMB18，说明是 IP、tile 还是全设计。

## 14. 计划门和 PASS 定义

| run | 内容 | PASS 条件 |
|---|---|---|
| run26 | 本版合同、packer、bridge RTL、静态 CSR/地址检查 | 公式、字节布局、寄存器位和 reset 规则一致；无未决 P0 |
| run27 | G4 全量/负向仿真 | §12 全部用例通过，checks=0，错误注入可观测且无死锁 |
| run28 | BD 重连、实现、bitstream/HWH | 真正流连接、100MHz 时序通过、资源报告口径完整 |
| run29 | B3.1 Conv0 板测和 cache 对照 | nerr=0、字节账、guard、DMA idle、CSR 错误、输出 SHA 全通过 |
| P1.3 | K=576/1024/2304 分块和重叠 | 块边界累加与 oracle 一致；无 FIFO overflow/deadlock；记录 STALLCNT 分布 |

B3.1 不能因为局部 DMA 回环、AXI-Lite B1 或 ycap 回读通过而 PASS。只有 run29 的真实 DMA→GEMM→DDR 路径满足本合同，才允许把 P1.2/B3.1 标记为 PASS。

## 15. 资源、时序和性能记录

- 时序基线：FCLK0=100MHz，记录 WNS/WHS 和关键路径；WNS≥0 才能进入板测。
- 资源报告必须同时列 DSP、LUT、FF、BRAM36、RAMB18，并注明与哪一个 bitstream 比较。
- 每块记录 MM2S/S2MM 完成时间、STALLCNT、FIFO overflow、DMA 状态；不要只报告总墙钟。
- B3.1 只建立功能正确性和字节账；FPS、P95/P99 和持续吞吐属于 P3/P4，不从一次 Conv0 门推导。
- P1.3 overlap 的功能门是有限完成、无 starvation、无 overflow、nerr=0；性能结论必须依据实测 STALLCNT 和吞吐 CSV。

## 16. D1–D4 和本版变更记录

- D1：移除 DMA 回环，接真实 DMA→GEMM→DDR。
- D2：y 主路径 day-1 直连 S2MM；ycap 保留为调试和 B1 回归。
- D3：LUT 仍由镜像提供，PS 通过 CSR LUTD 写入；LUT 不走流。
- D4：AXI-Lite 拍槽和 AXI-Stream 两路装载源保留，但运行时互斥并报告冲突。

本版相对旧版的实质修订：

1. 把物理布局改为 [LUT][load arena][y arena]，明确每个 block 的连续 SAR；W/X 表仅作为逻辑视图。
2. 固定 b=2*n_tile+g、oy/tx/ox0、OC row-group、K 展开和 padding 公式。
3. 固定 y stream 的 OC-major/N-major 顺序和 128B slot 的字节重排公式。
4. 明确 BRGSTAT sticky、CTRL.err_clr、STALLCNT read-clear 和软件总错误判据。
5. 增加 reset、cache、4KiB crossing、guard page、负向 TLAST、FIFO 压力和 BD/XCI 静态门。

本版文档修改后必须重新计算 SHA-256，并在 7_logs/2026-09-19/03_validation_summary.md 和对应 run 目录中记录；旧版审查证据仍保留，不得覆盖。
