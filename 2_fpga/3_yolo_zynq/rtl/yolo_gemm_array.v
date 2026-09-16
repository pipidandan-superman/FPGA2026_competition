/************************************************************************
 * File Name       : yolo_gemm_array.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_gemm_array
 * Description     : M10 integrated GEMM PE array (architecture baseline
 *                   section 3.1/3.3, SIM-8x8 instance = OC_EDGE 8 x
 *                   N_EDGE 8, 64 MAC/beat): assembles M1-M9 into the
 *                   output-stationary tile engine.
 *
 *                   Per layer (descriptor accepted in ctrl S_IDLE):
 *                     for n_tile: for oc_tile:
 *                       loader fills the inactive bank (W rows via DMA +
 *                       requant params via DMA block reads, X tile via
 *                       addrgen + the X-plane byte port)
 *                       -> bank_rdy; S_TILE waits tile_rdy (bank_rdy AND
 *                       3*OC_EDGE param prefetch into wrapper regs)
 *                       -> K beats: wbuf row broadcast x xbuf column
 *                          broadcast -> 32 pe_pack (OC row x N col pair)
 *                          -> acc (N_LANES = OC_EDGE*N_EDGE int32)
 *                       -> requant tail: 1 output/beat, rq_idx decode
 *                          (oc_local,n_local) -> requant -> SiLU LUT
 *                          -> y_we/y_addr/y_wdata (3-stage pipeline)
 *
 *                   Bank choreography (double buffer, deadlock-free):
 *                     bank_busy[b] = ctrl reading data (S_K, rd_bank=b)
 *                                    OR ctrl prefetching (S_TILE, rd_bank
 *                                    =b, bank_rdy[b] set)
 *                     loader starts a tile when its target bank (layer
 *                     start bank XOR tile parity) is neither busy nor
 *                     rdy; bank_rdy clears on S_K entry (consumed).
 *                     ctrl waiting in S_TILE with bank_rdy=0 is NOT
 *                     busy -- the loader may always finish the bank the
 *                     compute side is waiting on.
 *
 *                   Numeric contract: bit-identical to yolo_conv_core
 *                   (M0 gate) -- integer sums are order-independent;
 *                   pe_pack carries the M1 bias-layout corrections
 *                   internally, acc adds plain int32 lanes.
 *
 *                   X-plane port contract: x_rdata_i must be valid
 *                   combinationally in the same cycle as x_addr_o
 *                   (LUTRAM-style); the tile write pipeline retimes to
 *                   a synchronous source at M11 (DDR streaming).
 *
 *                   Y write path (V1.2, M12 A1): the requant tail is
 *                   segmented into per-oc-row DMA write commands -- a
 *                   row (n_tail bytes at ybase + oc_g*n_total +
 *                   n_tile*N_EDGE, arbitrary byte alignment) is captured
 *                   into the segmenter's row buffer as the tail beats
 *                   land, then pushed to u_dma_wr (yolo_dma_wr V1.2,
 *                   unaligned starts) as one linear write command.
 *                   Backpressure: a row-START beat is admitted (ctrl
 *                   S_RQ advances) only when the segmenter is idle AND
 *                   the d1..d9 pipe holds zero admitted beats
 *                   (seg_infl_r == 0) -- the idle term alone is
 *                   unsound: pre-edge state reads IDLE for 9 cycles
 *                   after an admission, so len-1 row sequences pushed
 *                   4 row-starts per idle window and 3 landed in
 *                   SEG_CMD, dropped (run02, 23 bytes). With both
 *                   terms zero, nothing in flight can take the
 *                   segmenter out of idle before the admitted beat
 *                   lands. Mid-row beats never stall (row depth =
 *                   N_EDGE >= n_tail).
 *                   The stall only bites at the d0 issue point: beats
 *                   already in flight (d1..d9) drain into the buffer,
 *                   so the requant/LUT valid pipelines stay pulsed and
 *                   are never frozen mid-beat (no valid-hold needed in
 *                   yolo_requant/yolo_silu_lut -- zero changes there).
 *
 *                   layer_done/all_done are drain-gated: they pulse one
 *                   cycle when ctrl finishes AND the segmenter is back
 *                   idle (last row's B collected) -- only then may the
 *                   PS read Y.
 *
 *                   Layer-switch races handled by construction: the row
 *                   command length is captured at the d1 stage together
 *                   with the cfg terms it needs (n_total, ybase --
 *                   V1.10), the oc*n_total multiply registers its own
 *                   product at the d1->d2 edge and the address
 *                   completes at the d2->d3 edge -- no cfg is read
 *                   after d1, so a back-to-back next descriptor
 *                   accept refreshing cfg cannot touch an in-flight
 *                   beat's address; the captured row parameters are
 *                   carried down the pipeline and the bytes land 9
 *                   cycles later (V1.9 pipe depth) -- the captured
 *                   row parameters are immune.
 *
 *                   Constraint: OC_EDGE/N_EDGE powers of two (row/col
 *                   index decode uses low counter bits).
 * Dependencies    : rtl/yolo_ctrl.v (V1.8), rtl/yolo_dma.v,
 *                   rtl/yolo_dma_wr.v (V1.2), rtl/yolo_wbuf.v,
 *                   rtl/yolo_xbuf.v, rtl/yolo_addrgen.v,
 *                   rtl/yolo_pe_pack.v, rtl/yolo_acc.v,
 *                   rtl/yolo_requant.v, rtl/yolo_silu_lut.v
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M10). Sequential
 *     requant tail (1/beat) -- overlap pipelining deferred as a
 *     perf-only change; X plane via direct byte port; Y as an observed
 *     output stream (write master is M11+/M12 scope).
 *   - V1.2 (2026-09-16) by LSL : M12 A1 Y 真 AXI 写主：新增 dsc_ybase
 *     描述符字段；Y 行段化器 + u_dma_wr 实例（AXI 写通道端口取代
 *     y_we/y_addr/y_wdata 观测口）；ctrl 升 V1.2（rq_rdy_i 接段化器
 *     行首准入）；ldone/adone 排空门控（段化器回闲才脉冲）。数值
 *     合同不变（装填值/求和次序/写地址逐字节唯一——Y 写序与镜像
 *     布局无关）。门重跑：M10/M11（TB 换 AXI 写 BFM 散写镜像）。
 *   - V1.2a (2026-09-16) by LSL : run02 揪出行首准入在途竞态——
 *     准入读前沿前 seg_state_r，len-1 行序列每 IDLE 窗口放进 4 个
 *     行首拍（1 吸收 + 3 落在 SEG_CMD 被丢，M10 计划恰丢 23 字节）。
 *     修复：行首准入 = 段化器 IDLE 且 d1..d3 在途计数清零
 *     （seg_infl_r：准入 +1 / 落地 -1）；ywr_idle_w 同判据（堵
 *     ctrl_ldone 贴尾 3 拍早脉冲窗口）。
 *   - V1.2b (2026-09-16) by LSL : pe_pack V1.1（DSP48E1 源语直例，
 *     M12 B0 DSP 超限修复）新增 clk_i 端口，例化点透传 clk_i；
 *     数值路径不变（M10/M11 门重跑承证）。
 *   - V1.3 (2026-09-16) by LSL : pe_pack V1.2（UG479 v1.10 严格合规：
 *     DSP 三级流水 AREG/BREG/MREG/PREG=1，PE 延迟 0→3 拍）适配——
 *     例化点透传 rst_n；acc 使能改 wrow_vld 延 3 拍（acc_en_d3_r），
 *     配合 yolo_ctrl V1.3 的 S_DRAIN 排空态。数值不变、时序合同
 *     +3 拍（M1→M4→M8→M10→M11 门链重跑承证）。
 *   - V1.4 (2026-09-16) by LSL : B0 dbg7c 时序修复批（授权"①②③
 *     合并批"）——(a) requant 尾重定时：yolo_requant V1.1 5 级流水
 *     （en 拍 d1 → y_pre 拍 d6），lut en 改 rq_en_d6_r，行参数 sideband
 *     链延伸到 d7，段化器落地拍 d3→d7，seg_infl_r 加宽 3→4 位
 *     （d0..d7 在途峰值 7——最旧落地拍与第 8 次准入同沿相消）；ctrl
 *     侧仍用现成 rq_rdy_i 反压，行首
 *     准入判据不变（IDLE && 在途 0）。(b) acc 高扇出 CE 修复
 *     （−15.2ns 纯布线）：单实例 u_acc 改为按 8 lane 分组例化，
 *     每组独立的 acc_en_d3/acc_clr 寄存副本（d1/d2 两级共享，
 *     第三级与 clr 逐组复制）；clr 注册 +1 拍（S_TILE 拉伸 1 拍
 *     进 S_K，首个 acc 写沿 ≥ S_K+4，裕量 3 拍，安全）。(c) 删除
 *     本层 ctrl_rq_last_w 的 oc_tail*n_tail 每拍动态乘，改接
 *     yolo_ctrl V1.4 新导出口 rq_last_o。数值合同不变（requant
 *     数值函数逐位等价；acc 分组只是布线复制）。门重跑：M5/M7
 *     （单元）→ M8 → M4/M10 → M11 全链 + B0 OOC。
 *   - V1.5 (2026-09-16) by LSL : B0 dbg8d 迭代 2（v14 剩余 top owner
 *     修复）——(a) rq_addr −6.5ns/17 级：d0 行解码的 oi*n_tail 比较
 *     环 + oc_g*n_total 乘法 + 32 位加链全组合进 row_addr_d1 捕获，
 *     改为 fire 门控增量计数器 oc_loc_q/n_loc_q（复位挂末拍 FIRE 与
 *     描述符接受沿——不挂 ctrl_rq_last 电平，行首末拍被段化器拖延
 *     时计数器须保持本拍解码值；准入拍前进，与准入流 1:1 等价）
 *     + d1 捕获 oc_g/n_base（移位/小加法）+ d1→d2 沿一次寄存乘法
 *     算 row_addr（cfg/tiling 竞态按 NBA 沿分析安全：末拍 d1 采集
 *     读旧 tile 计数；cfg 最早 end-L+2 刷新，d2 采集在 end-L+1 读
 *     旧值）。(b) CE 高扇出纯布线 −4.2ns×2：acc 分组 en/clr 副本被
 *     综合合并成跨组网线，加 (* max_fanout = 32 *)；
 *     rq_en_d1_r→requant 首级 CE 加 (* max_fanout = 16 *)。数值路
 *     径不变。门重跑：M8 + M10 + B0 v15。
 *   - V1.6 (2026-09-17) by LSL : xbuf BMG 输出寄存合同（xbuf V2.2，
 *     2026-09-17 用户授权）+ dbg8g 剩余 owner——(a) W 操作数对齐：xbuf
 *     读延迟 1→2，PE 墙前加一级 W 广播寄存 wrow_d1_r，两操作数同在
 *     D+2 入墙（乘积 D+5）；acc 使能链 3→4 级（共享 d1..d3 + 逐组
 *     d4，max_fanout 属性保持）；ctrl S_DRAIN 3→4（V1.8）。周期行为
 *     仅整体 +1 拍平移，数值字节不变。(b) wbuf 写束一级寄存（dbg8g
 *     wbuf −1.283ns/4L：装载 FSM→行 WE 解码直通 BRAM WE 脚）——六信
 *     号同拍平移；tile_load_done 增 !wpipe_we_q 排空判据（bank_rdy/
 *     tgt_bank 切换不领先末字节，无跨 bank 泄漏）。门重跑：M4/M8
 *     （黄金再生成，延迟平移）+ M5/M7 + M10 + B0 v18。
 *   - V1.7 (2026-09-17) by LSL : M10 v18 失败根因修复——xbuf V2.2
 *     读流水两级均 ENB 门控（M4 黄金合同），末 K 拍的 word[K-1] 提交
 *     进 stage1 后再无读使能沿，永远到不了 stage2/DOUT：末拍 X 操作数
 *     错取 word[K-2]（M10 实证 lane(0,0) acc +198 = beat26 乘积用
 *     word[25] 代 word[26]，159 = W[26]*word[25]；其余 26 拍逐字节全
 *     对）。修复：末拍后补一拍 flush 读（xren_flush_q，raddr 重采
 *     k_cnt 保持值 K，stage1 装垃圾但永不提交）——末字按时于 D+2
 *     入墙。v17（延迟 1 合同）无第二级故无此病理。纯延迟平移（同
 *     2026-09-17 授权合同），xbuf/ctrl/其余模块不动。门重跑：M10 v19
 *     + B0 v19（M4/M5/M7/M8 不涉 gemm_array 变更面，v18 结果有效）。
 *   - V1.8 (2026-09-17) by LSL : B0 迭代 11 适配——requant V1.2f 流水
 *     5→6 级（DSP P 内发火修复，en 拍 d1 → y_pre 拍 d7）。本模块 Y 尾
 *     不消费 requant 的 vld_o，而是以延迟 en 链重建有效：LUT en 改
 *     rq_en_d7_r，sideband 链延伸到 d8，段化器 SEG_IDLE 改读 d8，在途
 *     计数不变（d0..d8 峰值 8，仍 4 位）。纯延迟平移（同授权合同），
 *     数值字节不变；ctrl 不动（S_DRAIN 长度由 acc 排空链决定，与
 *     requant 深度无关）。门重跑：M10 v25 + M12 csr v25 + B0 v25
 *     （M5 v25/M7 v25 单元已过；M4/M8 不涉变更面）。
 *   - V1.9 (2026-09-17) by LSL : B0 迭代 12 适配——requant V1.2g 流水
 *     6→7 级（乘法操作数直通重寄存 sum_x_r/m_x_r，DSP 级联 AREG/BREG
 *     吸收；v25 OOC 唯一 owner sum_r→PCIN −0.079）。尾链再伸一级：
 *     LUT en rq_en_d8_r、sideband d9、SEG_IDLE 读 d9、在途计数峰值
 *     8→9（仍 4 位）。纯延迟平移（同授权合同），数值字节不变；ctrl
 *     不动（同 V1.8 论证）。门重跑：M10 v26 + M12 csr v26 + B0 v26
 *     （M5 v26 单元；M7 addrgen 不涉变更面）。
 *   - V1.10 (2026-09-17) by LSL : B0 迭代 13——v26 OOC 唯一 owner 家族
 *     oc_g_d1_r→row_addr DSP PCIN −0.031（V1.5 融合 mult+add 映射
 *     2-DSP 级联，首 DSP 被组合穿越 A→mult→adder→PCOUT 4.04ns，与
 *     requant V1.2g 修的同病理）。拆分：16x16 乘法自带寄存积
 *     row_prod_d2_r（单 DSP PREG，弧内无级联）；ybase+n_base 布线
 *     并行加 row_sum_d2_r；d3 沿合并 row_addr_d3_r。cfg 项（n_total/
 *     ybase）改 d1 快照——d1 后不再读 cfg，V1.5 的 NBA 次序论证由
 *     构造退役。mod-2^32 加法结合律，逐位等价；d9 呈现拍不变，M10/
 *     M12 应与 v26 逐拍相同。门重跑：M10 v27 + M12 csr v27 + B0 v27
 *     （M5/M7 不涉变更面，v26 单元结果有效）。
 ************************************************************************/

module yolo_gemm_array #(
    parameter OC_EDGE = 8,                   // tile output rows (SIM 8)
    parameter N_EDGE  = 8,                   // tile output cols (SIM 8)
    parameter K_MAX   = 2304,                // deepest K tier
    parameter AW      = 12,                  // ceil(log2 K_MAX)
    parameter ROW_AW  = 3,                   // ceil(log2 OC_EDGE)
    parameter COL_AW  = 3,                   // ceil(log2 N_EDGE)
    parameter ADDR_W  = 32,                  // AXI/DMA address width
    parameter LEN_W   = 24,                  // DMA command length width
    parameter OC_AW   = 11,                  // descriptor OC total
    parameter N_AW    = 16,                  // descriptor N total
    parameter K_AW    = 12,                  // descriptor K total
    parameter TILE_AW = 12,                  // tile counters / tails
    parameter MAX_BURST = 16                 // DMA beats per burst
) (
    input  wire                  clk_i,
    input  wire                  rst_n,
    // ---- layer descriptor stream (accepted in ctrl S_IDLE) ----
    input  wire                  dsc_valid_i,
    output wire                  dsc_ready_o,
    input  wire [OC_AW-1:0]      dsc_oc_i,     // layer OC total
    input  wire [N_AW-1:0]       dsc_n_i,      // layer N total (=OH*OW)
    input  wire [K_AW-1:0]       dsc_k_i,      // layer K (=IC*KH*KW)
    input  wire                  dsc_last_i,
    // im2col geometry (captured at accept, feeds addrgen)
    input  wire [15:0]           dsc_ih_i,
    input  wire [15:0]           dsc_iw_i,
    input  wire [15:0]           dsc_ow_i,
    input  wire [15:0]           dsc_ic_i,
    input  wire [7:0]            dsc_kh_i,
    input  wire [7:0]            dsc_kw_i,
    input  wire [7:0]            dsc_sh_i,
    input  wire [7:0]            dsc_sw_i,
    input  wire [7:0]            dsc_ph_i,
    input  wire [7:0]            dsc_pw_i,
    input  wire                  dsc_first_i,  // 1: pad=-128 (z fold)
    input  wire                  dsc_act_i,    // 1: SiLU LUT, 0: bypass
    // DDR byte base addresses (per layer)
    input  wire [ADDR_W-1:0]     dsc_wbase_i,  // W[oc][K] rows
    input  wire [ADDR_W-1:0]     dsc_xbase_i,  // X plane (CHW bytes)
    input  wire [ADDR_W-1:0]     dsc_ybase_i,  // Y plane [oc][n_total] rows
    input  wire [ADDR_W-1:0]     dsc_bbase_i,  // bias_eff words (LE,4B)
    input  wire [ADDR_W-1:0]     dsc_mbase_i,  // M words (LE,4B)
    input  wire [ADDR_W-1:0]     dsc_sbase_i,  // shift bytes
    // ---- AXI4 read master for W/params (yolo_dma) ----
    output wire [ADDR_W-1:0]     araddr_o,
    output wire [7:0]            arlen_o,
    output wire [2:0]            arsize_o,
    output wire [1:0]            arburst_o,
    output wire                  arvalid_o,
    input  wire                  arready_i,
    input  wire [63:0]           rdata_i,
    input  wire                  rlast_i,
    input  wire                  rvalid_i,
    output wire                  rready_o,
    // ---- AXI4 write master for Y (yolo_dma_wr, V1.2) ----
    output wire [ADDR_W-1:0]     awaddr_o,
    output wire [7:0]            awlen_o,
    output wire [2:0]            awsize_o,
    output wire [1:0]            awburst_o,
    output wire                  awvalid_o,
    input  wire                  awready_i,
    output wire [63:0]           wdata_o,
    output wire [7:0]            wstrb_o,
    output wire                  wlast_o,
    output wire                  wvalid_o,
    input  wire                  wready_i,
    input  wire                  bvalid_i,
    input  wire [1:0]            bresp_i,
    output wire                  bready_o,
    // ---- X plane byte read (comb contract, see header; streaming = A2) ----
    output wire [ADDR_W-1:0]     x_addr_o,
    input  wire [7:0]            x_rdata_i,
    // ---- SiLU LUT table write (preload per layer; TB/software) ----
    input  wire                  lut_we_i,
    input  wire [7:0]            lut_waddr_i,
    input  wire [7:0]            lut_wdata_i,
    // ---- status ----
    output wire                  layer_done_o,
    output wire                  all_done_o,
    output wire                  busy_o
);

    localparam N_LANES  = OC_EDGE * N_EDGE;      // 64 accumulator lanes
    localparam N_PAIRS  = N_EDGE / 2;            // pe_pack col pairs
    localparam PFC_N    = 3 * OC_EDGE;           // prefetch field count
    // parameter-derived vectors (bit-select on parameters is illegal)
    localparam [3:0]    OC_EDGE_4  = OC_EDGE;
    localparam [5:0]    OC_EDGE_6  = OC_EDGE;
    localparam [5:0]    PFC_M_LOW  = 2 * OC_EDGE;
    localparam [5:0]    PFC_LAST   = PFC_N - 1;
    localparam [7:0]    OC_EDGE_8  = OC_EDGE;
    localparam [9:0]    OC_EDGE4_10= OC_EDGE * 4;
    localparam [15:0]   N_EDGE_16  = N_EDGE;
    localparam [TILE_AW-1:0] N_EDGE_T = N_EDGE;

    // =================================================================
    // ctrl (V1.4) -- tile/layer sequencer
    // =================================================================
    wire                  ctrl_dsc_rdy;
    wire                  ctrl_acc_clr;
    wire                  ctrl_beat_en;
    wire [K_AW-1:0]       ctrl_k_cnt;
    wire                  ctrl_rq_en;
    wire [TILE_AW-1:0]    ctrl_rq_idx;
    wire                  ctrl_rq_last;     // V1.4: ctrl rq_last_o
    wire                  ctrl_wr_bank;
    wire                  ctrl_rd_bank;
    wire [TILE_AW-1:0]    ctrl_oc_tile;
    wire [TILE_AW-1:0]    ctrl_n_tile;
    wire [TILE_AW-1:0]    ctrl_n_tail;
    wire [TILE_AW-1:0]    ctrl_oc_tail;
    wire                  ctrl_ldone;
    wire                  ctrl_adone;
    wire                  ctrl_busy;

    // bank choreography state (scalars: no net arrays / no mem reads
    // in continuous assignments)
    reg                   bank_rdy0_r;
    reg                   bank_rdy1_r;
    wire                  tile_rdy_w;

    // Y row segmenter state (driven at the tail section; declared here
    // because the ctrl admission signal rq_ack_w reads it)
    localparam SEG_IDLE = 2'd0;   // empty; absorbs a row-start byte
    localparam SEG_FILL = 2'd1;   // filling the row buffer
    localparam SEG_CMD  = 2'd2;   // pushing the write command
    localparam SEG_DR   = 2'd3;   // feeding source, waiting for done
    reg [1:0]             seg_state_r;
    reg [3:0]             seg_infl_r;  // V1.4: admitted-at-d0, not-yet-
                                      // landed (d0..d7 pipe, peak 7)
    wire                  rq_ack_w;   // tail admission (assigned below)

    yolo_ctrl #(
        .OC_EDGE  (OC_EDGE),
        .N_EDGE   (N_EDGE),
        .OC_AW    (OC_AW),
        .N_AW     (N_AW),
        .K_AW     (K_AW),
        .TILE_AW  (TILE_AW)
    ) u_ctrl (
        .clk_i         (clk_i),
        .rst_n         (rst_n),
        .dsc_valid_i   (dsc_valid_i),
        .dsc_ready_o   (ctrl_dsc_rdy),
        .dsc_oc_i      (dsc_oc_i),
        .dsc_n_i       (dsc_n_i),
        .dsc_k_i       (dsc_k_i),
        .dsc_last_i    (dsc_last_i),
        .tile_rdy_i    (tile_rdy_w),
        .rq_rdy_i      (rq_ack_w),      // V1.2: Y segmenter admission
        .acc_clr_o     (ctrl_acc_clr),
        .beat_en_o     (ctrl_beat_en),
        .k_cnt_o       (ctrl_k_cnt),
        .rq_en_o       (ctrl_rq_en),
        .rq_idx_o      (ctrl_rq_idx),
        .rq_last_o     (ctrl_rq_last),   // V1.4: registered-limit flag
        .wr_bank_o     (ctrl_wr_bank),
        .rd_bank_o     (ctrl_rd_bank),
        .oc_tile_o     (ctrl_oc_tile),
        .n_tile_o      (ctrl_n_tile),
        .n_tail_o      (ctrl_n_tail),
        .oc_tail_o     (ctrl_oc_tail),
        .layer_done_o  (ctrl_ldone),
        .all_done_o    (ctrl_adone),
        .busy_o        (ctrl_busy)
    );

    wire dsc_accept_w = dsc_valid_i && ctrl_dsc_rdy;
    assign dsc_ready_o = ctrl_dsc_rdy;

    // per-bank views
    wire bank_rdy_rd_w  = ctrl_rd_bank ? bank_rdy1_r : bank_rdy0_r;
    wire bank_busy0_w = ((ctrl_beat_en || (ctrl_acc_clr && bank_rdy0_r))
                         && (ctrl_rd_bank == 1'b0));
    wire bank_busy1_w = ((ctrl_beat_en || (ctrl_acc_clr && bank_rdy1_r))
                         && (ctrl_rd_bank == 1'b1));

    // =================================================================
    // layer cfg shadow (captured at accept; y addressing + loader walk)
    // =================================================================
    reg [N_AW-1:0]    cfg_n_total_r;
    reg [OC_AW-1:0]   cfg_oc_total_r;
    reg [K_AW-1:0]    cfg_k_r;
    reg [15:0]        cfg_ih_r, cfg_iw_r, cfg_ow_r, cfg_ic_r;
    reg [7:0]         cfg_kh_r, cfg_kw_r, cfg_sh_r, cfg_sw_r;
    reg [7:0]         cfg_ph_r, cfg_pw_r;
    reg               cfg_first_r;
    reg               cfg_act_r;
    reg [ADDR_W-1:0]  cfg_wbase_r, cfg_xbase_r, cfg_ybase_r;
    reg [ADDR_W-1:0]  cfg_bbase_r;
    reg [ADDR_W-1:0]  cfg_mbase_r, cfg_sbase_r;
    reg [TILE_AW-1:0] cfg_oc_tiles_r, cfg_n_tiles_r;

    // tail width helper (same expression as ctrl tail_calc)
    function [TILE_AW-1:0] tail_of;
        input [TILE_AW-1:0] total;
        input [TILE_AW-1:0] tiles;
        input [TILE_AW-1:0] idx;
        input [TILE_AW-1:0] t_edge;
        begin
            if (idx == tiles - 1'b1) begin
                tail_of = total - (tiles - 1'b1) * t_edge;
            end else begin
                tail_of = t_edge;
            end
        end
    endfunction

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            cfg_n_total_r <= {N_AW{1'b0}};
            cfg_oc_total_r<= {OC_AW{1'b0}};
            cfg_k_r       <= {K_AW{1'b0}};
            cfg_ih_r      <= 16'd0;  cfg_iw_r <= 16'd0;
            cfg_ow_r      <= 16'd0;  cfg_ic_r <= 16'd0;
            cfg_kh_r      <= 8'd0;   cfg_kw_r <= 8'd0;
            cfg_sh_r      <= 8'd0;   cfg_sw_r <= 8'd0;
            cfg_ph_r      <= 8'd0;   cfg_pw_r <= 8'd0;
            cfg_first_r   <= 1'b0;
            cfg_act_r     <= 1'b0;
            cfg_wbase_r   <= {ADDR_W{1'b0}};
            cfg_xbase_r   <= {ADDR_W{1'b0}};
            cfg_ybase_r   <= {ADDR_W{1'b0}};
            cfg_bbase_r   <= {ADDR_W{1'b0}};
            cfg_mbase_r   <= {ADDR_W{1'b0}};
            cfg_sbase_r   <= {ADDR_W{1'b0}};
            cfg_oc_tiles_r<= {TILE_AW{1'b0}};
            cfg_n_tiles_r <= {TILE_AW{1'b0}};
        end else if (dsc_accept_w) begin
            cfg_n_total_r <= dsc_n_i;
            cfg_oc_total_r<= dsc_oc_i;
            cfg_k_r       <= dsc_k_i;
            cfg_ih_r      <= dsc_ih_i;  cfg_iw_r <= dsc_iw_i;
            cfg_ow_r      <= dsc_ow_i;  cfg_ic_r <= dsc_ic_i;
            cfg_kh_r      <= dsc_kh_i;  cfg_kw_r <= dsc_kw_i;
            cfg_sh_r      <= dsc_sh_i;  cfg_sw_r <= dsc_sw_i;
            cfg_ph_r      <= dsc_ph_i;  cfg_pw_r <= dsc_pw_i;
            cfg_first_r   <= dsc_first_i;
            cfg_act_r     <= dsc_act_i;
            cfg_wbase_r   <= dsc_wbase_i;
            cfg_xbase_r   <= dsc_xbase_i;
            cfg_ybase_r   <= dsc_ybase_i;
            cfg_bbase_r   <= dsc_bbase_i;
            cfg_mbase_r   <= dsc_mbase_i;
            cfg_sbase_r   <= dsc_sbase_i;
            cfg_oc_tiles_r<= (dsc_oc_i + OC_EDGE - 1) / OC_EDGE;
            cfg_n_tiles_r <= (dsc_n_i + N_EDGE - 1) / N_EDGE;
        end
    end

    // =================================================================
    // tile loader: walks the same n-outer/oc-inner grid ahead of ctrl
    // =================================================================
    localparam S_LDESC = 2'd0;   // wait for descriptor
    localparam S_LCHK  = 2'd1;   // wait target bank free
    localparam S_LRUN  = 2'd2;   // fill the tile (W DMA + X addrgen)

    reg [1:0]           ldr_state_r;
    reg [TILE_AW-1:0]   load_oc_r, load_n_r;
    reg                 layer_bank0_r;    // ctrl.rd_bank at accept
    reg                 load_parity_r;    // tiles loaded this layer & 1
    reg                 loaded_all_q;     // all tiles of layer loaded
    reg                 tgt_bank_r;       // bank being filled
    reg [3:0]           cmd_idx_r;        // 0..OC_EDGE-1 data, 8 b, 9 m, 10 s
    reg                 cmd_wait_r;       // command in flight
    reg                 wcmd_done_q;      // W sequence complete
    reg                 xgen_done_q;      // X fill complete
    reg                 xgen_start_r;     // 1-cycle start pulse
    reg [K_AW-1:0]      kbyte_cnt_r;      // byte within data command
    reg [5:0]           pbyte_cnt_r;      // byte within param command
    reg [31:0]          pword_sr;         // 4B LE assembly shifter

    wire [TILE_AW-1:0] load_n_tail_w = tail_of(cfg_n_total_r,
                                               cfg_n_tiles_r, load_n_r,
                                               N_EDGE_T);
    wire               more_tiles_w = !((load_oc_r == cfg_oc_tiles_r - 1'b1)
                                       && (load_n_r == cfg_n_tiles_r - 1'b1));
    wire               tgt_bank_w = layer_bank0_r ^ load_parity_r;
    wire               bank_busy_tgt_w = tgt_bank_w ? bank_busy1_w
                                                    : bank_busy0_w;
    wire               bank_rdy_tgt_w  = tgt_bank_w ? bank_rdy1_r
                                                    : bank_rdy0_r;
    wire [15:0]        xgen_nstart_w = load_n_r * N_EDGE_16;

    // ---- W command decode (idx -> type/address/length) ----
    wire       cmd_is_data_w = (cmd_idx_r < OC_EDGE_4);
    wire       cmd_is_bias_w = (cmd_idx_r == 4'd8);
    wire       cmd_is_m_w    = (cmd_idx_r == 4'd9);
    // else shift (idx 10)
    // W rows are stored 8-byte-row padded (DMA contract: cmd_addr 8B
    // aligned): row stride kpad = ceil(K/8)*8, global row = tile*OC_EDGE+r
    wire [31:0] kpad_w      = ((({20'd0, cfg_k_r}) + 32'd7) >> 3) << 3;
    wire [31:0] oc_base_w   = load_oc_r * OC_EDGE;
    wire [31:0] cmd_addr_w  = cmd_is_data_w ?
          (cfg_wbase_r + (oc_base_w + {28'd0, cmd_idx_r}) * kpad_w)
        : cmd_is_bias_w ? (cfg_bbase_r + oc_base_w * 4)
        : cmd_is_m_w    ? (cfg_mbase_r + oc_base_w * 4)
                        : (cfg_sbase_r + oc_base_w);
    wire [LEN_W-1:0] cmd_len_w = cmd_is_data_w ? {12'd0, cfg_k_r}
        : (cmd_idx_r == 4'd10) ? {17'd0, OC_EDGE_8}
                               : {14'd0, OC_EDGE4_10};

    // ---- DMA instance ----
    wire               dma_cmd_rdy_w;
    wire               dma_done_w;
    wire               dma_dv_w;
    wire [7:0]         dma_byte_w;
    wire               dma_cmd_go_w = (ldr_state_r == S_LRUN) && !cmd_wait_r
                                      && !wcmd_done_q;

    yolo_dma #(
        .ADDR_W    (ADDR_W),
        .LEN_W     (LEN_W),
        .MAX_BURST (MAX_BURST)
    ) u_dma (
        .clk_i       (clk_i),
        .rst_n       (rst_n),
        .cmd_valid_i (dma_cmd_go_w),
        .cmd_ready_o (dma_cmd_rdy_w),
        .cmd_addr_i  (cmd_addr_w[ADDR_W-1:0]),
        .cmd_len_i   (cmd_len_w),
        .done_o      (dma_done_w),
        .araddr_o    (araddr_o),
        .arlen_o     (arlen_o),
        .arsize_o    (arsize_o),
        .arburst_o   (arburst_o),
        .arvalid_o   (arvalid_o),
        .arready_i   (arready_i),
        .rdata_i     (rdata_i),
        .rlast_i     (rlast_i),
        .rvalid_i    (rvalid_i),
        .rready_o    (rready_o),
        .out_valid_o (dma_dv_w),
        .out_data_o  (dma_byte_w),
        .out_ready_i (1'b1)                    // wbuf port absorbs 1 B/cyc
    );

    // ---- addrgen + X plane address (comb: base + plane offset) ----
    wire          xgen_done_pulse_w;
    wire          xgen_vld_w;
    wire          xgen_pad_w;
    wire [7:0]    xgen_pval_w;
    wire [15:0]   xgen_k_w, xgen_n_w;
    wire [ADDR_W-1:0] xgen_off_w;
    wire [ADDR_W-1:0] xgen_addr_w = cfg_xbase_r + xgen_off_w;
    assign x_addr_o = xgen_addr_w;

    yolo_addrgen #(
        .AW (ADDR_W)
    ) u_addrgen (
        .clk_i    (clk_i),
        .rst_n    (rst_n),
        .start_i  (xgen_start_r),
        .ih_i     (cfg_ih_r),
        .iw_i     (cfg_iw_r),
        .ow_i     (cfg_ow_r),
        .ic_i     (cfg_ic_r),
        .kh_i     (cfg_kh_r),
        .kw_i     (cfg_kw_r),
        .sh_i     (cfg_sh_r),
        .sw_i     (cfg_sw_r),
        .ph_i     (cfg_ph_r),
        .pw_i     (cfg_pw_r),
        // addrgen ports are 16-bit; cfg_k_r (K_AW) and the tile tail
        // (TILE_AW) are narrower -- zero-extend (both <= 16 by param check)
        .k_len_i  ({{(16-K_AW){1'b0}}, cfg_k_r}),
        .n_start_i(xgen_nstart_w),
        .n_len_i  ({{(16-TILE_AW){1'b0}}, load_n_tail_w}),
        .first_i  (cfg_first_r),
        .busy_o   (),
        .done_o   (xgen_done_pulse_w),
        .vld_o    (xgen_vld_w),
        .x_addr_o (xgen_off_w),
        .pad_o    (xgen_pad_w),
        .pad_val_o(xgen_pval_w),
        .k_o      (xgen_k_w),
        .n_o      (xgen_n_w)
    );

    // ---- wbuf / xbuf instances ----
    wire [OC_EDGE*8-1:0] wrow_data_w;
    wire                 wrow_vld_w;
    wire [N_EDGE*8-1:0]  xcol_data_w;
    wire                 xcol_vld_w;

    wire               pren_w;
    wire [1:0]         psel_w;
    wire [ROW_AW-1:0]  prow_w;
    wire [31:0]        pdata_w;
    wire               pdata_vld_w;

    wire               wb_we_w;
    wire [1:0]         wb_sel_w;
    wire [ROW_AW-1:0]  wb_row_w;
    wire [AW-1:0]      wb_addr_w;
    wire [31:0]        wb_data_w;

    // V1.6 (dbg8g wbuf -1.283ns/4L: loader FSM -> row-WE decode ran
    // straight to the row BRAM WE pins): the whole wbuf write bundle is
    // staged one cycle. tile_load_done additionally waits !wpipe_we_q,
    // so bank_rdy (and the tgt_bank_r switch back in S_LCHK) can never
    // lead the last staged byte -- no cross-bank leak, no early tile_rdy.
    // (declared before the u_wbuf instance below: the port connections
    // must not create implicit nets)
    reg               wpipe_we_q;
    reg [1:0]         wpipe_sel_q;
    reg [ROW_AW-1:0]  wpipe_row_q;
    reg [AW-1:0]      wpipe_addr_q;
    reg [31:0]        wpipe_data_q;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            wpipe_we_q   <= 1'b0;
            wpipe_sel_q  <= 2'd0;
            wpipe_row_q  <= {ROW_AW{1'b0}};
            wpipe_addr_q <= {AW{1'b0}};
            wpipe_data_q <= 32'd0;
        end else begin
            wpipe_we_q   <= wb_we_w;
            wpipe_sel_q  <= wb_sel_w;
            wpipe_row_q  <= wb_row_w;
            wpipe_addr_q <= wb_addr_w;
            wpipe_data_q <= wb_data_w;
        end
    end

    yolo_wbuf #(
        .N_ROWS (OC_EDGE),
        .K_MAX  (K_MAX),
        .AW     (AW),
        .ROW_AW (ROW_AW)
    ) u_wbuf (
        .clk_i      (clk_i),
        .rst_n      (rst_n),
        .we_i       (wpipe_we_q),
        .wr_bank_i  (tgt_bank_r),
        .wr_sel_i   (wpipe_sel_q),
        .wrow_i     (wpipe_row_q),
        .waddr_i    (wpipe_addr_q),
        .wdata_i    (wpipe_data_q),
        .rd_bank_i  (ctrl_rd_bank),
        .ren_i      (ctrl_beat_en),
        .raddr_i    (ctrl_k_cnt[AW-1:0]),
        .dout_o     (wrow_data_w),
        .dout_vld_o (wrow_vld_w),
        .pren_i     (pren_w),
        .psel_i     (psel_w),
        .prow_i     (prow_w),
        .pdata_o    (pdata_w),
        .pdata_vld_o(pdata_vld_w)
    );

    // V1.7 (xbuf V2.2 trap fix): the BMG output register commits stage2
    // only on a read-enabled edge (ENB gates BOTH stages, M4 golden
    // contract) -- every beat's word lands at the NEXT read-enabled edge,
    // which for beats 0..K-2 is the following beat, but the LAST beat's
    // word would stay trapped in stage1 forever (its stage2 commit edge
    // never comes; the K-loop is the only reader). One flush read right
    // after the last beat supplies that edge: stage2 <= word[K-1] just in
    // time for the wall's D+2 operand meeting; stage1 re-samples (k_cnt
    // holds K, junk never committed). M10 v18 dbg: lane(0,0) acc +198 =
    // beat-26 product served with word[25] instead of word[26].
    reg xren_flush_q;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            xren_flush_q <= 1'b0;
        end else begin
            xren_flush_q <= ctrl_beat_en && (ctrl_k_cnt == cfg_k_r - 1'b1);
        end
    end
    wire xren_w = ctrl_beat_en || xren_flush_q;

    yolo_xbuf #(
        .N_COLS (N_EDGE),
        .K_MAX  (K_MAX),
        .AW     (AW),
        .COL_AW (COL_AW)
    ) u_xbuf (
        .clk_i      (clk_i),
        .rst_n      (rst_n),
        .we_i       (xgen_vld_w && (ldr_state_r == S_LRUN)),
        .wr_bank_i  (tgt_bank_r),
        .wcol_i     (xgen_n_w[COL_AW-1:0]),
        .waddr_i    (xgen_k_w[AW-1:0]),
        .wdata_i    (xgen_pad_w ? xgen_pval_w : x_rdata_i),
        .rd_bank_i  (ctrl_rd_bank),
        .ren_i      (xren_w),
        .raddr_i    (ctrl_k_cnt[AW-1:0]),
        .dout_o     (xcol_data_w),
        .dout_vld_o (xcol_vld_w)
    );

    // ---- write decode: data rows / bias / m / shift blocks ----
    wire pbyte_word_w = (pbyte_cnt_r[1:0] == 2'd3);   // 4th byte of a word
    assign wb_we_w  = (ldr_state_r == S_LRUN) && dma_dv_w
                      && (cmd_is_data_w || (cmd_idx_r == 4'd10)
                          || ((cmd_is_bias_w || cmd_is_m_w) && pbyte_word_w));
    assign wb_sel_w = cmd_is_data_w ? 2'd0 : cmd_is_bias_w ? 2'd1
                       : cmd_is_m_w ? 2'd2 : 2'd3;
    assign wb_row_w = cmd_is_data_w ? cmd_idx_r[ROW_AW-1:0]
                      : (cmd_idx_r == 4'd10) ? pbyte_cnt_r[ROW_AW-1:0]
                      : pbyte_cnt_r[5:2];             // bias/m: byte/4
    assign wb_addr_w= cmd_is_data_w ? kbyte_cnt_r[AW-1:0] : {AW{1'b0}};
    assign wb_data_w= cmd_is_data_w ? {24'd0, dma_byte_w}
                      : (cmd_is_bias_w || cmd_is_m_w)
                        ? {dma_byte_w, pword_sr[31:8]} : {24'd0, dma_byte_w};

    // ---- loader FSM + byte counters (single drivers) ----
    wire tile_load_done_w = (ldr_state_r == S_LRUN) && wcmd_done_q
                            && xgen_done_q && !wpipe_we_q;

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            ldr_state_r   <= S_LDESC;
            load_oc_r     <= {TILE_AW{1'b0}};
            load_n_r      <= {TILE_AW{1'b0}};
            layer_bank0_r <= 1'b0;
            load_parity_r <= 1'b0;
            loaded_all_q  <= 1'b0;
            tgt_bank_r    <= 1'b0;
            cmd_idx_r     <= 4'd0;
            cmd_wait_r    <= 1'b0;
            wcmd_done_q   <= 1'b0;
            xgen_done_q   <= 1'b0;
            xgen_start_r  <= 1'b0;
        end else begin
            xgen_start_r <= 1'b0;
            case (ldr_state_r)
                S_LDESC: begin
                    if (dsc_accept_w) begin
                        load_oc_r     <= {TILE_AW{1'b0}};
                        load_n_r      <= {TILE_AW{1'b0}};
                        layer_bank0_r <= ctrl_rd_bank;
                        load_parity_r <= 1'b0;
                        loaded_all_q  <= 1'b0;
                        ldr_state_r   <= S_LCHK;
                    end
                end
                S_LCHK: begin
                    if (loaded_all_q) begin
                        // layer fully loaded: park in S_LDESC so the next
                        // dsc_accept resets the walk (load_oc/load_n/
                        // parity). Without this the loader sticks here --
                        // !loaded_all_q blocks forever and the next layer's
                        // ctrl waits in S_TILE without tile_rdy.
                        ldr_state_r <= S_LDESC;
                    end else if (!bank_busy_tgt_w
                                  && !bank_rdy_tgt_w) begin
                        tgt_bank_r  <= tgt_bank_w;
                        cmd_idx_r   <= 4'd0;
                        cmd_wait_r  <= 1'b0;
                        wcmd_done_q <= 1'b0;
                        xgen_done_q <= 1'b0;
                        xgen_start_r<= 1'b1;
                        ldr_state_r <= S_LRUN;
                    end
                end
                S_LRUN: begin
                    if (!wcmd_done_q) begin
                        if (dma_cmd_go_w && dma_cmd_rdy_w) begin
                            cmd_wait_r <= 1'b1;      // accepted this edge
                        end else if (cmd_wait_r && dma_done_w) begin
                            cmd_wait_r <= 1'b0;
                            if (cmd_idx_r == 4'd10) begin
                                wcmd_done_q <= 1'b1;
                            end else begin
                                cmd_idx_r <= cmd_idx_r + 4'd1;
                            end
                        end
                    end
                    if (xgen_done_pulse_w) begin
                        xgen_done_q <= 1'b1;
                    end
                    if (tile_load_done_w) begin
                        load_parity_r <= ~load_parity_r;
                        if (more_tiles_w) begin
                            // oc inner, n outer (same order as ctrl)
                            if (load_oc_r == cfg_oc_tiles_r - 1'b1) begin
                                load_oc_r <= {TILE_AW{1'b0}};
                                load_n_r  <= load_n_r + 1'b1;
                            end else begin
                                load_oc_r <= load_oc_r + 1'b1;
                            end
                        end else begin
                            loaded_all_q <= 1'b1;
                        end
                        ldr_state_r <= S_LCHK;   // S_LCHK re-routes if done
                    end
                end
                default: ldr_state_r <= S_LDESC;
            endcase
        end
    end

    // delivered-byte counters + LE word assembly for the in-flight cmd
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            kbyte_cnt_r <= {K_AW{1'b0}};
            pbyte_cnt_r <= 6'd0;
            pword_sr    <= 32'd0;
        end else if (ldr_state_r == S_LRUN) begin
            if (dma_cmd_go_w && dma_cmd_rdy_w) begin
                kbyte_cnt_r <= {K_AW{1'b0}};   // command boundary
                pbyte_cnt_r <= 6'd0;
            end else if (dma_dv_w) begin
                if (cmd_is_data_w) begin
                    kbyte_cnt_r <= kbyte_cnt_r + 1'b1;
                end else begin
                    pbyte_cnt_r <= pbyte_cnt_r + 1'b1;
                    if (cmd_is_bias_w || cmd_is_m_w) begin
                        pword_sr <= {dma_byte_w, pword_sr[31:8]};
                    end
                end
            end
        end
    end

    // bank_rdy: set at tile load completion, cleared at ctrl consumption
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            bank_rdy0_r <= 1'b0;
            bank_rdy1_r <= 1'b0;
        end else begin
            if (ctrl_beat_en) begin
                if (ctrl_rd_bank) bank_rdy1_r <= 1'b0;  // consumed
                else              bank_rdy0_r <= 1'b0;
            end
            if (tile_load_done_w) begin
                if (tgt_bank_r) bank_rdy1_r <= 1'b1;
                else            bank_rdy0_r <= 1'b1;
            end
        end
    end

    // =================================================================
    // param prefetch: 3*OC_EDGE fields -> wrapper regs during S_TILE
    // =================================================================
    reg [OC_EDGE*32-1:0] pb_flat_r;      // bias_eff
    reg [OC_EDGE*32-1:0] pm_flat_r;      // M
    reg [OC_EDGE*8-1:0]  ps_flat_r;      // shift
    reg [5:0]            pfc_cnt_r;      // issued field count
    reg [5:0]            cap_cnt_r;      // captured field count
    reg                  params_rdy_r;
    reg [1:0]            psel_d1_r;      // capture-stage request shadow
    reg [ROW_AW-1:0]     prow_d1_r;

    wire pfc_active_w = ctrl_acc_clr && bank_rdy_rd_w && !params_rdy_r;
    assign pren_w = pfc_active_w && (pfc_cnt_r < OC_EDGE_6 * 3);
    assign psel_w = (pfc_cnt_r < OC_EDGE_6) ? 2'd1
                  : (pfc_cnt_r < PFC_M_LOW) ? 2'd2 : 2'd3;
    assign prow_w = pfc_cnt_r[ROW_AW-1:0];

    // ctrl tile change points: advance (last rq beat) / new descriptor
    // (V1.4: the oc_tail*n_tail multiply moved into ctrl's registered
    //  rq_limit_r compare, exported as rq_last_o)
    wire ctrl_rq_last_w = ctrl_rq_last;
    wire tile_change_w  = ctrl_rq_last_w || dsc_accept_w;

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            pfc_cnt_r   <= 6'd0;
            cap_cnt_r   <= 6'd0;
            params_rdy_r<= 1'b0;
            psel_d1_r   <= 2'd0;
            prow_d1_r   <= {ROW_AW{1'b0}};
            pb_flat_r   <= {(OC_EDGE*32){1'b0}};
            pm_flat_r   <= {(OC_EDGE*32){1'b0}};
            ps_flat_r   <= {(OC_EDGE*8){1'b0}};
        end else begin
            psel_d1_r <= psel_w;
            prow_d1_r <= prow_w;
            if (pren_w) begin
                pfc_cnt_r <= pfc_cnt_r + 1'b1;
            end
            if (pdata_vld_w) begin
                cap_cnt_r <= cap_cnt_r + 1'b1;
                if (psel_d1_r == 2'd1) begin
                    pb_flat_r[prow_d1_r*32 +: 32] <= pdata_w;
                end else if (psel_d1_r == 2'd2) begin
                    pm_flat_r[prow_d1_r*32 +: 32] <= pdata_w;
                end else begin
                    ps_flat_r[prow_d1_r*8 +: 8]  <= pdata_w[7:0];
                end
                if (cap_cnt_r == PFC_LAST) begin
                    params_rdy_r <= 1'b1;
                end
            end
            if (tile_change_w) begin
                pfc_cnt_r    <= 6'd0;
                cap_cnt_r    <= 6'd0;
                params_rdy_r <= 1'b0;
            end
        end
    end

    // =================================================================
    // K-loop datapath: broadcast read -> pe_pack wall -> acc
    // =================================================================
    wire [N_LANES*32-1:0] acc_q_w;
    wire [N_LANES*32-1:0] acc_d_w;
    wire [N_LANES*17-1:0] pe_p_w;

    // V1.6 (xbuf V2.2 contract): the X operand now arrives one cycle
    // later (BMG primitives output register, read latency 2) than the
    // W operand (wbuf, latency 1) -- stage the W broadcast one cycle
    // so both operands enter the PE wall together. Unconditional load
    // mirrors the wbuf output hold (the reg just re-samples the held
    // value between beats).
    reg [OC_EDGE*8-1:0] wrow_d1_r;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            wrow_d1_r <= {(OC_EDGE*8){1'b0}};
        end else begin
            wrow_d1_r <= wrow_data_w;
        end
    end

    genvar gr, gc;
    generate
        for (gr = 0; gr < OC_EDGE; gr = gr + 1) begin : g_pe_row
            for (gc = 0; gc < N_PAIRS; gc = gc + 1) begin : g_pe_pair
                yolo_pe_pack u_pe (
                    .clk_i(clk_i),
                    .rst_n_i(rst_n),          // V1.3: DSP pipeline resets
                    .x0_i (xcol_data_w[(gc*2)*8 +: 8]),
                    .x1_i (xcol_data_w[(gc*2+1)*8 +: 8]),
                    .w_i  (wrow_d1_r[gr*8 +: 8]),
                    .p0_o (pe_p_w[(gr*N_EDGE + gc*2)*17 +: 17]),
                    .p1_o (pe_p_w[(gr*N_EDGE + gc*2+1)*17 +: 17])
                );
                // sign-extend 17b products into 32b addends
                assign acc_d_w[(gr*N_EDGE + gc*2)*32 +: 32]
                    = {{15{pe_p_w[(gr*N_EDGE + gc*2)*17 + 16]}},
                       pe_p_w[(gr*N_EDGE + gc*2)*17 +: 17]};
                assign acc_d_w[(gr*N_EDGE + gc*2+1)*32 +: 32]
                    = {{15{pe_p_w[(gr*N_EDGE + gc*2+1)*17 + 16]}},
                       pe_p_w[(gr*N_EDGE + gc*2+1)*17 +: 17]};
            end
        end
    endgenerate

    // V1.3: the PE wall is 3-cycle pipelined (pe_pack V1.2, UG479
    // three-stage multiply) -- w/x dout in cycle D yields products in
    // D+3, so the acc enable rides a matching 3-deep valid delay. The
    // ctrl S_DRAIN state (yolo_ctrl V1.3) holds S_RQ off for 3 cycles
    // after the last K beat so the final products land before the
    // requant lane mux samples acc_q.
    // V1.4: the en fanout to N_LANES CE pins was a pure-routing -15.2ns
    // path (dbg7c: ctrl FSM replica -> acc CE, 1 logic level) -- the
    // chain is now shared for 2 stages, then replicated per 8-lane
    // group. The clr is registered per group as well (+1 cycle vs the
    // direct level: last clear edge = S_TILE exit +1, first acc write
    // edge >= S_TILE exit +5 -- margin >= 3 edges; and the last S_RQ
    // beat's acc capture edge (d1) still precedes the first clear edge).
    // V1.6 (xbuf V2.2): operands now meet at D+2 (w staged +1, x BMG
    // output reg +1), products D+5 -> the en chain is 4 deep and ctrl
    // S_DRAIN is 4 cycles (yolo_ctrl V1.8; clr margin grows to >=4).
    reg acc_en_d1_r, acc_en_d2_r, acc_en_d3_r;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            acc_en_d1_r <= 1'b0;
            acc_en_d2_r <= 1'b0;
            acc_en_d3_r <= 1'b0;
        end else begin
            acc_en_d1_r <= wrow_vld_w;
            acc_en_d2_r <= acc_en_d1_r;
            acc_en_d3_r <= acc_en_d2_r;
        end
    end

    localparam ACC_GRP_LANES = 8;             // lanes per replicated en/clr
    localparam N_ACC_GRP     = N_LANES / ACC_GRP_LANES;

    genvar ga;
    generate
        for (ga = 0; ga < N_ACC_GRP; ga = ga + 1) begin : g_acc
            // V1.5: synth MERGED the per-group copies into one net whose
            // replicas still spanned groups (dbg8d acc CE -4.15ns);
            // max_fanout forces re-replication within each group's scope
            (* max_fanout = 32 *) reg acc_en_d4_g_r;   // per-group 4th en
            (* max_fanout = 32 *) reg acc_clr_d1_g_r;  // per-group registered clr
            always @(posedge clk_i or negedge rst_n) begin
                if (!rst_n) begin
                    acc_en_d4_g_r  <= 1'b0;
                    acc_clr_d1_g_r <= 1'b0;
                end else begin
                    acc_en_d4_g_r  <= acc_en_d3_r;
                    acc_clr_d1_g_r <= ctrl_acc_clr;
                end
            end
            yolo_acc #(
                .N_LANES (ACC_GRP_LANES),
                .DATA_W  (32)
            ) u_acc_g (
                .clk_i (clk_i),
                .rst_n (rst_n),
                .clr_i (acc_clr_d1_g_r),
                .en_i  (acc_en_d4_g_r),       // V1.6: wrow_vld delayed 4
                .d_i   (acc_d_w[ga*ACC_GRP_LANES*32 +: ACC_GRP_LANES*32]),
                .q_o   (acc_q_w[ga*ACC_GRP_LANES*32 +: ACC_GRP_LANES*32])
            );
        end
    endgenerate

    // =================================================================
    // requant tail: d0 decode + admission, pulsed valid pipeline, Y row
    // segmenter + AXI write master (V1.2)
    // =================================================================
    // d0 decode (V1.5): the admitted S_RQ beats of a tile are exactly
    // the idx sequence 0..rq_limit with row-major idx = oc_loc*n_tail +
    // n_loc, so oc_loc/n_loc are maintained INCREMENTALLY: fire-gated
    // advance (mid-tile beats), reset at the last beat's FIRE and at
    // descriptor accept (both terms = 0 == idx 0, always a row start).
    // The reset is keyed on the FIRE, not on the ctrl_rq_last LEVEL:
    // a stalled last-beat offer (row-start beats can wait for the
    // segmenter) must not reset the counters under the beat -- they
    // hold the beat's true decode until it is admitted. NBA keeps the
    // firing beat's d1 capture reading the pre-reset values. Replaces
    // the per-beat oi*n_tail compare loop (dbg8d rq_addr owner,
    // -6.5ns / 17 levels); values identical at every beat.
    reg [ROW_AW-1:0]     oc_loc_q;
    reg [COL_AW-1:0]     n_loc_q;
    wire [TILE_AW-1:0]   n_tail_m1_w = ctrl_n_tail - 1'b1;
    wire                 n_loc_last_w = ({{(TILE_AW-COL_AW){1'b0}},
                                          n_loc_q} == n_tail_m1_w);

    wire         row_start_d0_w = (n_loc_q == {COL_AW{1'b0}});
    // d0 partial terms for the row address: shifts + small adds only
    // (the oc_g*n_total multiply moved to the d1->d2 edge below)
    wire [15:0]  oc_g_d0_w  = ctrl_oc_tile * OC_EDGE + oc_loc_q;
    wire [15:0]  n_base_d0_w = ctrl_n_tile * N_EDGE;

    // admission (ctrl V1.2 rq_rdy_i): mid-row beats always admitted
    // (row depth = N_EDGE >= n_tail); a row-start beat only when the
    // segmenter is idle AND the d1..d9 pipe holds no admitted beats
    // (seg_infl_r, maintained next to the segmenter FSM below). The
    // in-flight term is MANDATORY (run02 bug, 23 lost bytes): the
    // pre-edge seg_state_r still reads IDLE for 9 cycles (V1.9 pipe
    // depth) after the previous row-start was admitted, so len-1 row
    // sequences let multiple row-starts through per idle window --
    // only the first lands in SEG_IDLE, the rest land in SEG_CMD and
    // are dropped (5+12+6 = 23 in the M10 plan). Zero occupancy + idle
    // means nothing in flight can still take the segmenter out of idle.
    assign rq_ack_w = !row_start_d0_w
                      || ((seg_state_r == SEG_IDLE) && (seg_infl_r == 4'd0));
    wire rq_fire_w = ctrl_rq_en && rq_ack_w;

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            oc_loc_q <= {ROW_AW{1'b0}};
            n_loc_q  <= {COL_AW{1'b0}};
        end else if (rq_fire_w && ctrl_rq_last_w) begin
            // tile's last beat admitted: next admitted beat is the
            // next tile's idx 0 (S_RQ advance / S_LDONE both >=1
            // cycle away; dsc_accept is mutually exclusive with S_RQ)
            oc_loc_q <= {ROW_AW{1'b0}};
            n_loc_q  <= {COL_AW{1'b0}};
        end else if (dsc_accept_w) begin
            oc_loc_q <= {ROW_AW{1'b0}};
            n_loc_q  <= {COL_AW{1'b0}};
        end else if (rq_fire_w) begin
            if (n_loc_last_w) begin
                n_loc_q  <= {COL_AW{1'b0}};
                oc_loc_q <= oc_loc_q + 1'b1;
            end else begin
                n_loc_q <= n_loc_q + 1'b1;
            end
        end
    end

    // d1 capture is FIRE-gated: a held S_RQ must not re-issue the beat
    // (valid pipeline stays pulsed -- requant/lut need no hold support).
    // V1.4: requant is a 5-stage pipe (en d1 -> y_pre d6), so the en
    // shadow chain now runs d2..d6 to meet the LUT capture at d6.
    // V1.8: requant V1.2f is a 6-stage pipe (en d1 -> y_pre d7), the
    // chain runs one deeper to meet the LUT capture at d7.
    // V1.9: requant V1.2g is a 7-stage pipe (en d1 -> y_pre d8), the
    // chain runs one deeper still to meet the LUT capture at d8.
    // V1.5: 106 CE loads on this enable made pure ROUTING the requant
    // path owner (dbg8d -4.15ns / 0 levels); max_fanout=16 splits it
    (* max_fanout = 16 *) reg rq_en_d1_r;
    reg                  rq_en_d2_r, rq_en_d3_r;
    reg                  rq_en_d4_r, rq_en_d5_r, rq_en_d6_r;
    reg                  rq_en_d7_r;                       // V1.8
    reg                  rq_en_d8_r;                       // V1.9
    reg [ROW_AW-1:0]     oc_loc_d1_r;
    reg [COL_AW-1:0]     n_loc_d1_r;
    reg                  row_start_d1_r;
    reg [TILE_AW-1:0]    row_len_d1_r;
    // V1.5: d1 captures the row-address PARTIAL terms (shift + small
    // add each). V1.10: the cfg terms are snapshotted here as well
    // (n_tot_d1_r/ybase_d1_r) and the oc_g*n_total multiply is a
    // REGISTERED step at the d2 edge (row_prod_d2_r below), off the
    // d0/d1 critical paths
    reg [15:0]           oc_g_d1_r;
    reg [15:0]           n_base_d1_r;
    reg [N_AW-1:0]       n_tot_d1_r;   // V1.10: cfg snapshot at d1
    reg [ADDR_W-1:0]     ybase_d1_r;   // V1.10: cfg snapshot at d1

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            rq_en_d1_r    <= 1'b0;
            oc_loc_d1_r   <= {ROW_AW{1'b0}};
            n_loc_d1_r    <= {COL_AW{1'b0}};
            row_start_d1_r<= 1'b0;
            row_len_d1_r  <= {TILE_AW{1'b0}};
            oc_g_d1_r     <= 16'd0;
            n_base_d1_r   <= 16'd0;
            n_tot_d1_r    <= {N_AW{1'b0}};
            ybase_d1_r    <= {ADDR_W{1'b0}};
        end else begin
            rq_en_d1_r <= rq_fire_w;
            if (rq_fire_w) begin
                oc_loc_d1_r    <= oc_loc_q;
                n_loc_d1_r     <= n_loc_q;
                row_start_d1_r <= row_start_d0_w;
                row_len_d1_r   <= ctrl_n_tail;
                oc_g_d1_r      <= oc_g_d0_w;
                n_base_d1_r    <= n_base_d0_w;
                n_tot_d1_r     <= cfg_n_total_r;
                ybase_d1_r     <= cfg_ybase_r;
            end
        end
    end

    // accumulator lane mux at d1 (registered oc_loc; acc holds at S_RQ)
    reg [31:0]       acc_sel_r;
    integer li;
    wire [31:0]      lane_idx_w = oc_loc_d1_r * N_EDGE + n_loc_d1_r;
    always @(*) begin
        acc_sel_r = 32'd0;
        for (li = N_LANES - 1; li >= 0; li = li - 1) begin
            if (lane_idx_w == li) begin
                acc_sel_r = acc_q_w[li*32 +: 32];
            end
        end
    end

    wire signed [31:0] rq_bias_w = pb_flat_r[oc_loc_d1_r*32 +: 32];
    wire signed [31:0] rq_m_w    = pm_flat_r[oc_loc_d1_r*32 +: 32];
    wire [7:0]         rq_shift_w= ps_flat_r[oc_loc_d1_r*8 +: 8];

    wire signed [7:0]  y_pre_w;
    wire               y_pre_vld_w;
    wire [7:0]         y_lut_w;
    wire               y_lut_vld_w;

    yolo_requant #(
        .ACC_W (32)
    ) u_requant (
        .clk_i   (clk_i),
        .rst_n   (rst_n),
        .en_i    (rq_en_d1_r),
        .acc_i   (acc_sel_r),
        .bias_i  (rq_bias_w),
        .m_i     (rq_m_w),
        .shift_i (rq_shift_w),
        .y_pre_o (y_pre_w),
        .vld_o   (y_pre_vld_w)
    );

    yolo_silu_lut #(
        .DW (8),
        .AW (8)
    ) u_lut (
        .clk_i    (clk_i),
        .rst_n    (rst_n),
        .we_i     (lut_we_i),
        .waddr_i  (lut_waddr_i),
        .wdata_i  (lut_wdata_i),
        .en_i     (rq_en_d8_r),      // V1.9: y_pre lands d8 (7-stage requant V1.2g)
        .act_i    (cfg_act_r),
        .y_pre_i  (y_pre_w),
        .y_o      (y_lut_w),
        .vld_o    (y_lut_vld_w)
    );

    // d2..d9 sideband shift: row params ride alongside the byte; at d9
    // they present on the same cycle as y_lut_vld_w (pulse-aligned).
    // V1.4: chain stretched 2 -> 6 deep to track the 5-stage requant
    // (byte lands d7, one cycle after the d6 LUT capture).
    // V1.8: one deeper still -- requant V1.2f en d1 -> y_pre d7, LUT
    // captures at d7 and the byte lands d8.
    // V1.9: and one more -- requant V1.2g en d1 -> y_pre d8, LUT
    // captures at d8 and the byte lands d9.
    // V1.10: the address leg joins this shift at d3 (product + sum
    // registered at d2, combined at d3) instead of entering at d2.
    reg                  row_start_d2_r, row_start_d3_r;
    reg                  row_start_d4_r, row_start_d5_r;
    reg                  row_start_d6_r, row_start_d7_r;
    reg                  row_start_d8_r;                        // V1.8
    reg                  row_start_d9_r;                        // V1.9
    reg [TILE_AW-1:0]    row_len_d2_r, row_len_d3_r;
    reg [TILE_AW-1:0]    row_len_d4_r, row_len_d5_r;
    reg [TILE_AW-1:0]    row_len_d6_r, row_len_d7_r;
    reg [TILE_AW-1:0]    row_len_d8_r;                          // V1.8
    reg [TILE_AW-1:0]    row_len_d9_r;                          // V1.9
    reg [ADDR_W-1:0]     row_addr_d3_r;
    reg [ADDR_W-1:0]     row_addr_d4_r, row_addr_d5_r;
    reg [ADDR_W-1:0]     row_addr_d6_r, row_addr_d7_r;
    reg [ADDR_W-1:0]     row_addr_d8_r;                         // V1.8
    reg [ADDR_W-1:0]     row_addr_d9_r;                         // V1.9
    // V1.10: address pipeline splits -- multiply product and the
    // ybase+n_base sum register separately at d2, combine at d3
    // (row_addr_d2_r retired; the d9 presentation is unchanged)
    reg [31:0]           row_prod_d2_r;   // 16x16 product, single DSP PREG
    reg [ADDR_W-1:0]     row_sum_d2_r;    // ybase + n_base, fabric add

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            rq_en_d2_r     <= 1'b0;
            rq_en_d3_r     <= 1'b0;
            rq_en_d4_r     <= 1'b0;
            rq_en_d5_r     <= 1'b0;
            rq_en_d6_r     <= 1'b0;
            rq_en_d7_r     <= 1'b0;
            rq_en_d8_r     <= 1'b0;
            row_start_d2_r <= 1'b0;
            row_start_d3_r <= 1'b0;
            row_start_d4_r <= 1'b0;
            row_start_d5_r <= 1'b0;
            row_start_d6_r <= 1'b0;
            row_start_d7_r <= 1'b0;
            row_start_d8_r <= 1'b0;
            row_start_d9_r <= 1'b0;
            row_len_d2_r <= {TILE_AW{1'b0}};
            row_len_d3_r <= {TILE_AW{1'b0}};
            row_len_d4_r <= {TILE_AW{1'b0}};
            row_len_d5_r <= {TILE_AW{1'b0}};
            row_len_d6_r <= {TILE_AW{1'b0}};
            row_len_d7_r <= {TILE_AW{1'b0}};
            row_len_d8_r <= {TILE_AW{1'b0}};
            row_len_d9_r <= {TILE_AW{1'b0}};
            row_prod_d2_r <= 32'd0;
            row_sum_d2_r  <= {ADDR_W{1'b0}};
            row_addr_d3_r<= {ADDR_W{1'b0}};
            row_addr_d4_r<= {ADDR_W{1'b0}};
            row_addr_d5_r<= {ADDR_W{1'b0}};
            row_addr_d6_r<= {ADDR_W{1'b0}};
            row_addr_d7_r<= {ADDR_W{1'b0}};
            row_addr_d8_r<= {ADDR_W{1'b0}};
            row_addr_d9_r<= {ADDR_W{1'b0}};
        end else begin
            rq_en_d2_r     <= rq_en_d1_r;
            rq_en_d3_r     <= rq_en_d2_r;
            rq_en_d4_r     <= rq_en_d3_r;
            rq_en_d5_r     <= rq_en_d4_r;
            rq_en_d6_r     <= rq_en_d5_r;
            rq_en_d7_r     <= rq_en_d6_r;
            rq_en_d8_r     <= rq_en_d7_r;
            row_start_d2_r <= row_start_d1_r;
            row_start_d3_r <= row_start_d2_r;
            row_start_d4_r <= row_start_d3_r;
            row_start_d5_r <= row_start_d4_r;
            row_start_d6_r <= row_start_d5_r;
            row_start_d7_r <= row_start_d6_r;
            row_start_d8_r <= row_start_d7_r;
            row_start_d9_r <= row_start_d8_r;
            row_len_d2_r   <= row_len_d1_r;
            row_len_d3_r   <= row_len_d2_r;
            row_len_d4_r   <= row_len_d3_r;
            row_len_d5_r   <= row_len_d4_r;
            row_len_d6_r   <= row_len_d5_r;
            row_len_d7_r   <= row_len_d6_r;
            row_len_d8_r   <= row_len_d7_r;
            row_len_d9_r   <= row_len_d8_r;
            // V1.10: the V1.5 fused mult+add mapped a 2-DSP cascade
            // whose first DSP was traversed combinationally (v26 OOC
            // owner oc_g_d1_r -> row_addr DSP PCIN -0.031: 4.04ns
            // A->mult->adder->PCOUT internal traverse, fabric FF
            // launch + PCIN setup around it). Split: the 16x16
            // multiply gets its own registered product (single DSP
            // with PREG -- no cascade in the arc), the two adds run
            // in fabric in parallel and combine one cycle later.
            // mod-2^32 addition is associative -- bit-exact against
            // the fused form. cfg terms are d1 snapshots, so no cfg
            // is read after d1 (V1.5's NBA race argument retired by
            // construction). d9 presentation unchanged.
            row_prod_d2_r  <= oc_g_d1_r * n_tot_d1_r;
            row_sum_d2_r   <= ybase_d1_r + n_base_d1_r;
            row_addr_d3_r  <= row_prod_d2_r + row_sum_d2_r;
            row_addr_d4_r  <= row_addr_d3_r;
            row_addr_d5_r  <= row_addr_d4_r;
            row_addr_d6_r  <= row_addr_d5_r;
            row_addr_d7_r  <= row_addr_d6_r;
            row_addr_d8_r  <= row_addr_d7_r;
            row_addr_d9_r  <= row_addr_d8_r;
        end
    end

    // =================================================================
    // Y row segmenter + AXI write master (yolo_dma_wr V1.2)
    // (seg_state_r / SEG_* declared above near the ctrl instance)
    // =================================================================
    reg [N_EDGE*8-1:0]  seg_buf_r;        // row buffer (n_tail <= N_EDGE)
    reg [4:0]           seg_fill_r;       // bytes landed this row
    reg [4:0]           seg_sent_r;       // bytes handed to the writer
    reg [ADDR_W-1:0]    seg_addr_r;       // row command address
    reg [TILE_AW-1:0]   seg_len_r;        // row length
    reg                 seg_cmd_go_q;     // command accepted (source phase)

    wire                seg_in_fire_w = y_lut_vld_w;   // d9 byte pulse
    wire [12:0]         seg_fill_nx_w = {8'd0, seg_fill_r} + 13'd1;
    wire                row_done_w    = (seg_fill_nx_w
                                         >= {1'b0, seg_len_r});

    // d1..d9 pipe occupancy: +1 per d0 admission (rq_fire_w), -1 per
    // d9 landing -- exact because every admitted beat pulses
    // y_lut_vld_w exactly once 9 cycles later and nothing else enters
    // the pipe (back-to-back beats peak at 9: the oldest decrement
    // cancels the would-be 10th increment at the same edge). Feeds the
    // row-start admission term above.
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            seg_infl_r <= 4'd0;
        end else begin
            if (rq_fire_w && !seg_in_fire_w)
                seg_infl_r <= seg_infl_r + 4'd1;
            else if (seg_in_fire_w && !rq_fire_w)
                seg_infl_r <= seg_infl_r - 4'd1;
        end
    end

    wire                wr_cmd_rdy_w;
    wire                wr_done_w;
    wire                wr_src_rdy_w;
    wire                seg_src_vld_w = seg_cmd_go_q
                                        && (seg_sent_r < seg_fill_r);
    wire [7:0]          seg_src_data_w = seg_buf_r[seg_sent_r*8 +: 8];

    yolo_dma_wr #(
        .ADDR_W    (ADDR_W),
        .LEN_W     (LEN_W),
        .MAX_BURST (MAX_BURST)
    ) u_dma_wr (
        .clk_i       (clk_i),
        .rst_n       (rst_n),
        .cmd_valid_i (seg_state_r == SEG_CMD),
        .cmd_ready_o (wr_cmd_rdy_w),
        .cmd_addr_i  (seg_addr_r),
        .cmd_len_i   ({{(LEN_W-TILE_AW){1'b0}}, seg_len_r}),
        .done_o      (wr_done_w),
        .src_valid_i (seg_src_vld_w),
        .src_data_i  (seg_src_data_w),
        .src_ready_o (wr_src_rdy_w),
        .awaddr_o    (awaddr_o),
        .awlen_o     (awlen_o),
        .awsize_o    (awsize_o),
        .awburst_o   (awburst_o),
        .awvalid_o   (awvalid_o),
        .awready_i   (awready_i),
        .wdata_o     (wdata_o),
        .wstrb_o     (wstrb_o),
        .wlast_o     (wlast_o),
        .wvalid_o    (wvalid_o),
        .wready_i    (wready_i),
        .bvalid_i    (bvalid_i),
        .bresp_i     (bresp_i),
        .bready_o    (bready_o)
    );

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            seg_state_r <= SEG_IDLE;
            seg_fill_r  <= 5'd0;
            seg_sent_r  <= 5'd0;
            seg_addr_r  <= {ADDR_W{1'b0}};
            seg_len_r   <= {TILE_AW{1'b0}};
            seg_cmd_go_q<= 1'b0;
        end else begin
            case (seg_state_r)
                SEG_IDLE: begin
                    // admission guarantees this byte is a row start
                    if (seg_in_fire_w) begin
                        seg_buf_r[0 +: 8] <= y_lut_w;
                        seg_addr_r <= row_addr_d9_r;
                        seg_len_r  <= row_len_d9_r;
                        seg_fill_r <= 5'd1;
                        seg_sent_r <= 5'd0;
                        if (13'd1 >= {1'b0, row_len_d9_r}) begin
                            seg_state_r <= SEG_CMD;   // single-byte row
                        end else begin
                            seg_state_r <= SEG_FILL;
                        end
                    end
                end
                SEG_FILL: begin
                    if (seg_in_fire_w) begin
                        seg_buf_r[seg_fill_r*8 +: 8] <= y_lut_w;
                        seg_fill_r <= seg_fill_r + 5'd1;
                        if (row_done_w) begin
                            seg_state_r <= SEG_CMD;
                        end
                    end
                end
                SEG_CMD: begin
                    if (wr_cmd_rdy_w) begin          // cmd_valid held 1
                        seg_cmd_go_q <= 1'b1;
                        seg_state_r  <= SEG_DR;
                    end
                end
                SEG_DR: begin
                    if (seg_src_vld_w && wr_src_rdy_w) begin
                        seg_sent_r <= seg_sent_r + 5'd1;
                    end
                    if (wr_done_w) begin             // B drained
                        seg_state_r <= SEG_IDLE;
                        seg_fill_r  <= 5'd0;
                        seg_cmd_go_q<= 1'b0;
                    end
                end
                default: seg_state_r <= SEG_IDLE;
            endcase
        end
    end

    // drain-gated layer/all done: pulse only when the segmenter is
    // quiescent -- idle AND no admitted beats still in the d1..d9 pipe
    // (ctrl_ldone can land within 9 cycles of the last d0 issue, when
    // the last row-start has not even reached the segmenter; the
    // in-flight term closes that window). The last row's write command
    // has its B collected at the pulse -- only then may the PS read Y.
    reg ldone_pend_r, adone_pend_r;
    wire ywr_idle_w = (seg_state_r == SEG_IDLE) && (seg_infl_r == 4'd0);

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            ldone_pend_r <= 1'b0;
            adone_pend_r <= 1'b0;
        end else if (ctrl_ldone) begin
            ldone_pend_r <= 1'b1;
            adone_pend_r <= ctrl_adone;
        end else if (ywr_idle_w && ldone_pend_r) begin
            ldone_pend_r <= 1'b0;
            adone_pend_r <= 1'b0;
        end
    end

    assign tile_rdy_w   = bank_rdy_rd_w & params_rdy_r;
    assign layer_done_o = ldone_pend_r && ywr_idle_w;
    assign all_done_o   = layer_done_o && adone_pend_r;
    assign busy_o       = ctrl_busy || (ldr_state_r != S_LDESC)
                          || !ywr_idle_w || ldone_pend_r;

endmodule
