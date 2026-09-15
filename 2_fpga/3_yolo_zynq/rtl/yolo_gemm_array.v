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
 *                   Layer-switch races handled by construction: tile
 *                   coords / rq_idx / n_tail are captured at rq_en into
 *                   the _d1 stage (ctrl resets them one cycle after the
 *                   last rq beat); the y address is computed at the
 *                   requant-en stage and delayed 2 stages, so the last
 *                   write of a layer lands 3 cycles after its last rq
 *                   beat -- cfg (n_total) captured at the back-to-back
 *                   descriptor accept cannot collide.
 *
 *                   Constraint: OC_EDGE/N_EDGE powers of two (row/col
 *                   index decode uses low counter bits).
 * Dependencies    : rtl/yolo_ctrl.v (V1.1), rtl/yolo_dma.v,
 *                   rtl/yolo_wbuf.v, rtl/yolo_xbuf.v,
 *                   rtl/yolo_addrgen.v, rtl/yolo_pe_pack.v,
 *                   rtl/yolo_acc.v, rtl/yolo_requant.v,
 *                   rtl/yolo_silu_lut.v
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M10). Sequential
 *     requant tail (1/beat) -- overlap pipelining deferred as a
 *     perf-only change; X plane via direct byte port; Y as an observed
 *     output stream (write master is M11+/M12 scope).
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
    // ---- X plane byte read (comb contract, see header) ----
    output wire [ADDR_W-1:0]     x_addr_o,
    input  wire [7:0]            x_rdata_i,
    // ---- SiLU LUT table write (preload per layer; TB/software) ----
    input  wire                  lut_we_i,
    input  wire [7:0]            lut_waddr_i,
    input  wire [7:0]            lut_wdata_i,
    // ---- Y output stream (byte per output, index-addressed) ----
    output wire                  y_we_o,
    output wire [ADDR_W-1:0]     y_addr_o,
    output wire [7:0]            y_wdata_o,
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
    // ctrl (V1.1) -- tile/layer sequencer
    // =================================================================
    wire                  ctrl_dsc_rdy;
    wire                  ctrl_acc_clr;
    wire                  ctrl_beat_en;
    wire [K_AW-1:0]       ctrl_k_cnt;
    wire                  ctrl_rq_en;
    wire [TILE_AW-1:0]    ctrl_rq_idx;
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
        .acc_clr_o     (ctrl_acc_clr),
        .beat_en_o     (ctrl_beat_en),
        .k_cnt_o       (ctrl_k_cnt),
        .rq_en_o       (ctrl_rq_en),
        .rq_idx_o      (ctrl_rq_idx),
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
    reg [ADDR_W-1:0]  cfg_wbase_r, cfg_xbase_r, cfg_bbase_r;
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

    yolo_wbuf #(
        .N_ROWS (OC_EDGE),
        .K_MAX  (K_MAX),
        .AW     (AW),
        .ROW_AW (ROW_AW)
    ) u_wbuf (
        .clk_i      (clk_i),
        .rst_n      (rst_n),
        .we_i       (wb_we_w),
        .wr_bank_i  (tgt_bank_r),
        .wr_sel_i   (wb_sel_w),
        .wrow_i     (wb_row_w),
        .waddr_i    (wb_addr_w),
        .wdata_i    (wb_data_w),
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
        .ren_i      (ctrl_beat_en),
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
                            && xgen_done_q;

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
    wire ctrl_rq_last_w = ctrl_rq_en
                          && (ctrl_rq_idx == ctrl_oc_tail * ctrl_n_tail
                                             - 1'b1);
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

    genvar gr, gc;
    generate
        for (gr = 0; gr < OC_EDGE; gr = gr + 1) begin : g_pe_row
            for (gc = 0; gc < N_PAIRS; gc = gc + 1) begin : g_pe_pair
                yolo_pe_pack u_pe (
                    .x0_i (xcol_data_w[(gc*2)*8 +: 8]),
                    .x1_i (xcol_data_w[(gc*2+1)*8 +: 8]),
                    .w_i  (wrow_data_w[gr*8 +: 8]),
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

    yolo_acc #(
        .N_LANES (N_LANES),
        .DATA_W  (32)
    ) u_acc (
        .clk_i (clk_i),
        .rst_n (rst_n),
        .clr_i (ctrl_acc_clr),
        .en_i  (wrow_vld_w),          // data valid 1 beat after ren
        .d_i   (acc_d_w),
        .q_o   (acc_q_w)
    );

    // =================================================================
    // requant tail: decode, mux, 3-stage output pipeline
    // =================================================================
    reg                  rq_en_d1_r, rq_en_d2_r;
    reg [TILE_AW-1:0]    rq_idx_d1_r;
    reg [TILE_AW-1:0]    oc_tile_d1_r, n_tile_d1_r, n_tail_d1_r;
    reg [ADDR_W-1:0]     y_addr_d1_r, y_addr_d2_r;

    // stage-1 capture at rq_en (ctrl resets idx/tails the cycle after)
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            rq_en_d1_r    <= 1'b0;
            rq_idx_d1_r   <= {TILE_AW{1'b0}};
            oc_tile_d1_r  <= {TILE_AW{1'b0}};
            n_tile_d1_r   <= {TILE_AW{1'b0}};
            n_tail_d1_r   <= {TILE_AW{1'b0}};
        end else begin
            rq_en_d1_r <= ctrl_rq_en;
            if (ctrl_rq_en) begin
                rq_idx_d1_r  <= ctrl_rq_idx;
                oc_tile_d1_r <= ctrl_oc_tile;
                n_tile_d1_r  <= ctrl_n_tile;
                n_tail_d1_r  <= ctrl_n_tail;
            end
        end
    end

    // (oc_local, n_local) decode at the requant-en stage
    reg [ROW_AW-1:0] oc_loc_r;
    reg [COL_AW-1:0] n_loc_r;
    reg [31:0]       acc_sel_r;
    integer oi, li;
    wire [31:0]      lane_idx_w = oc_loc_r * N_EDGE + n_loc_r;
    always @(*) begin
        // row-major idx = oc_loc*n_tail + n_loc: ascending loop so the
        // LAST assignment is the LARGEST oi with oi*n_tail <= idx (a
        // descending overwrite loop would always collapse to oi = 1)
        oc_loc_r = {ROW_AW{1'b0}};
        for (oi = 1; oi < OC_EDGE; oi = oi + 1) begin
            if (rq_idx_d1_r >= oi * n_tail_d1_r) begin
                oc_loc_r = oi[ROW_AW-1:0];
            end
        end
        n_loc_r = rq_idx_d1_r - oc_loc_r * n_tail_d1_r;
        acc_sel_r = 32'd0;
        for (li = N_LANES - 1; li >= 0; li = li - 1) begin
            if (lane_idx_w == li) begin
                acc_sel_r = acc_q_w[li*32 +: 32];
            end
        end
    end

    wire signed [31:0] rq_bias_w = pb_flat_r[oc_loc_r*32 +: 32];
    wire signed [31:0] rq_m_w    = pm_flat_r[oc_loc_r*32 +: 32];
    wire [7:0]         rq_shift_w= ps_flat_r[oc_loc_r*8 +: 8];

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
        .en_i     (rq_en_d2_r),
        .act_i    (cfg_act_r),
        .y_pre_i  (y_pre_w),
        .y_o      (y_lut_w),
        .vld_o    (y_lut_vld_w)
    );

    // y address computed at the requant-en stage, delayed 2 stages
    wire [31:0] y_addr_w = ((oc_tile_d1_r * OC_EDGE + oc_loc_r)
                            * cfg_n_total_r)
                           + n_tile_d1_r * N_EDGE + n_loc_r;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            rq_en_d2_r  <= 1'b0;
            y_addr_d1_r <= {ADDR_W{1'b0}};
            y_addr_d2_r <= {ADDR_W{1'b0}};
        end else begin
            rq_en_d2_r <= rq_en_d1_r;
            if (rq_en_d1_r) begin
                y_addr_d1_r <= y_addr_w[ADDR_W-1:0];
            end
            y_addr_d2_r <= y_addr_d1_r;
        end
    end

    assign y_we_o    = y_lut_vld_w;        // = rq_en delayed 3 stages
    assign y_addr_o  = y_addr_d2_r;
    assign y_wdata_o = y_lut_w;

    assign tile_rdy_w   = bank_rdy_rd_w & params_rdy_r;
    assign layer_done_o = ctrl_ldone;
    assign all_done_o   = ctrl_adone;
    assign busy_o       = ctrl_busy || (ldr_state_r != S_LDESC);

endmodule
