/************************************************************************
 * File Name       : yolo_ctrl.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ctrl
 * Description     : M8 tile/layer sequencer (architecture baseline
 *                   section 3.1): walks each layer descriptor as
 *                     for n_tile in ceil(N/N_EDGE):
 *                       for oc_tile in ceil(OC/OC_EDGE):
 *                         acc clr (>=1 cyc, waits tile_rdy_i in V1.1)
 *                         -> K beats (1/cyc) -> requant tail beats
 *                   Tail tiles clamp the last n/oc tile width; layer
 *                   switch = descriptor accept back to back with the
 *                   layer_done pulse (S_LDONE, 1 cycle). rd_bank toggles
 *                   on every tile ADVANCE (continuous across layers);
 *                   wr_bank is its complement (DMA fills the inactive
 *                   bank). all_done pulses on the last layer's done.
 *
 *                   Phase pacing note: requant here is 1 output/beat
 *                   (no time-multiplexing) -- the M8 gate covers tile
 *                   sequencing; REQUANT_UNITS overlap pacing is an
 *                   M10 integration concern.
 *
 *                   V1.1 (M10 integration): S_TILE now waits for
 *                   tile_rdy_i (tile data loaded + params prefetched)
 *                   before entering S_K. The wait stretches acc_clr_o
 *                   (level decode of S_TILE) -- harmless, the array
 *                   accumulator is held at 0 while en=0; all other
 *                   outputs are unaffected. With tile_rdy_i tied high
 *                   the module is cycle-identical to V1.0. Outputs are
 *                   combinational functions of registered state and
 *                   counters only (settle after the clock edge).
 *
 *                   V1.2 (M12 A1): S_RQ now waits for rq_rdy_i before
 *                   advancing rq_cnt (Y write backpressure: the array's
 *                   requant tail stalls when its AXI write master
 *                   command channel is busy). During the stall rq_en_o
 *                   (level) and rq_idx_o hold stable -- a proper
 *                   req/ack offer. With rq_rdy_i tied high the module
 *                   is cycle-identical to V1.1.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M8).
 *   - V1.1 (2026-09-15) by LSL : S_TILE wait state on tile_rdy_i (M10:
 *     buffer-load pacing -- per-tile DMA load far exceeds K beats, the
 *     K loop must not read a half-filled bank). Gate rerun: run02.
 *   - V1.2 (2026-09-16) by LSL : S_RQ wait on rq_rdy_i (M12 A1: Y 写
 *     背压；接高电平与 V1.1 周期等价). Gate rerun: run03.
 *   - V1.3 (2026-09-16) by LSL : 新增 S_DRAIN 态（S_K→3 拍→S_RQ），
 *     配合 pe_pack V1.2 三级流水（UG479）——末 3 个 K 拍乘积在 PE
 *     墙内排空后 requant 才可采样 acc_q。所有输出在 DRAIN 拍为 0
 *     （busy 除外）。门重跑：M8 黄金再生成 + M4/M10/M11 链。
 *   - V1.4 (2026-09-16) by LSL : B0 dbg7c ctrl −11.6ns（14 级）修复
 *     ——rq_last_w 原为 oc_tail_r*n_tail_r 每拍动态乘+比较，改为
 *     rq_limit_r（尾宽设定沿一次性登记）+ 纯 12 位比较；另导出
 *     rq_last_o（S_RQ 拍的末拍指示，取代 gemm_array 侧的同型动态
 *     乘）。周期行为与 V1.3 逐拍等价（limit 登记后最早 5 拍才可能
 *     进 S_RQ）。门重跑：M8（黄金不变）+ M4/M10/M11 链。
 *   - V1.5 (2026-09-16) by LSL : B0 dbg8d ctrl −5.6ns（11 级）修复
 *     ——V1.4 的 rq_limit 登记式在 S_IDLE 接受拍/S_RQ 前进拍仍是
 *     tail_calc×tail_calc−1 的 11 级乘法链（oc_tiles_r→rq_limit 乘
 *     法器 LUT）。改为 S_TILE 拍从已寄存的 oc_tail_r*n_tail_r−1 计
 *     算（寄存器×寄存器，2~3 级）：两条进入 S_TILE 的路径（S_IDLE
 *     接受、S_RQ 前进）的前一拍都已装好 oc/n_tail_r；S_TILE 因参数
 *     预取至少拉伸 ~26 拍，rq_limit 就绪比 S_RQ 首用早 ≥30 拍。输
 *     出周期行为不变（M8 黄金不变）。
 *   - V1.6 (2026-09-16) by LSL : B0 dbg8e ctrl −1.86ns（12 级）修复
 *     ——S_RQ 前进拍的 tail_calc（比较+常乘+减法 12 级链）改为：
 *     接受拍一次性预存末 tile 尾宽 oc/n_tail_last_r（= total−
 *     (tiles−1)*edge），前进拍 = next_oc/n_last_w 比较 + 2:1 选择
 *     （4~5 级）；tail_calc 函数删除。尾宽值与各拍装载值逐位等价
 *     （M8 黄金不变）；oc/n_total_r 保留但不再被读（综合剪除）。
 *     门重跑：M8（黄金不变）+ M10 + B0 v16。
 *   - V1.7 (2026-09-17) by LSL : B0 dbg8f ctrl −1.116ns/12 级——V1.6 前进
 *     拍仍是 last_oc→next_n→比较→选择 12 级链（oc_tiles_r→n_tail_r）。
 *     改为前进拍纯寄存器装载 oc/n_tail_next_r（每拍在 case 外用
 *     “下一 tile 是否末 tile”的直比式暂存：oc 侧 oc_tile==oc_tiles−2
 *     或环绕且 tiles==1；n 侧分两态——oc 不环绕时 n 保持（保持到的
 *     tile 若已是末 n 行仍要装 n_tail_last），环绕时 n+1（n_tile==
 *     n_tiles−2））。首版漏了 n 保持态（M8 v17 FAIL errors=365，末
 *     n 行中段 tile 全装了 N_EDGE），M8 v17b TB_CTRL_PASS
 *     compared=706403 黄金不变。门重跑：M8 v17b + M10 v17 + B0 v17。
 *   - V1.8 (2026-09-17) by LSL : xbuf BMG 输出寄存合同（V2.2，用户授权）
 *     ——读延迟 1→2 拍使 X 操作数晚一拍到 PE 墙，gemm_array 侧 W 操作
 *     数加一级对齐寄存、acc 使能 3→4 拍，故 S_DRAIN 3→4 拍（末 K 拍
 *     tk → acc 落地 tk+5 → requant 采样 tk+6）。周期行为变化仅每 tile
 *     +1 拍排空；M8 黄金再生成（drain_cycles 6813→9084，数值字节
 *     不变——授权原文）。门重跑：M8 v18（黄金再生成）+ M10 v18 + B0 v18。
 ************************************************************************/

module yolo_ctrl #(
    parameter OC_EDGE = 16,                 // output rows per tile
    parameter N_EDGE  = 16,                 // output columns per tile
    parameter OC_AW   = 11,                 // ceil(log2 OC_max=1280)
    parameter N_AW    = 16,                 // ceil(log2 N_max=25600)
    parameter K_AW    = 12,                 // ceil(log2 K_max=2304)
    parameter TILE_AW = 12                  // tile counters / tails / rq idx
) (
    input  wire               clk_i,
    input  wire               rst_n,
    // layer descriptor stream (accepted in S_IDLE)
    input  wire               dsc_valid_i,
    output wire               dsc_ready_o,
    input  wire [OC_AW-1:0]   dsc_oc_i,     // layer OC total
    input  wire [N_AW-1:0]    dsc_n_i,      // layer N total
    input  wire [K_AW-1:0]    dsc_k_i,      // layer K total
    input  wire               dsc_last_i,   // last layer of the network
    // tile readiness (V1.1): S_TILE holds (acc_clr_o stays high) until
    // the wrapper reports the tile's W/X bank loaded + params prefetched
    input  wire               tile_rdy_i,
    // K-loop array interface
    output wire               acc_clr_o,    // 1-cycle pulse per tile
    output wire               beat_en_o,
    output wire [K_AW-1:0]    k_cnt_o,      // 0..K-1 during beat_en_o
    // requant tail interface (rq_idx = oc_local*n_tail + n_local);
    // rq_rdy_i (V1.2): per-output backpressure from the array's Y
    // segmenter -- S_RQ holds (en/idx stable) until accepted;
    // rq_last_o (V1.4): registered-limit last-beat flag for the
    // wrapper (replaces its own oc_tail*n_tail multiply)
    input  wire               rq_rdy_i,
    output wire               rq_en_o,
    output wire [TILE_AW-1:0] rq_idx_o,
    output wire               rq_last_o,
    // tile bookkeeping / double-buffer steering
    output wire               wr_bank_o,    // = ~rd_bank_o (inactive bank)
    output wire               rd_bank_o,
    output wire [TILE_AW-1:0] oc_tile_o,
    output wire [TILE_AW-1:0] n_tile_o,
    output wire [TILE_AW-1:0] n_tail_o,     // clamped tail width
    output wire [TILE_AW-1:0] oc_tail_o,
    // layer/sequence done
    output wire               layer_done_o, // 1-cycle pulse per layer
    output wire               all_done_o,   // pulse on the last layer
    output wire               busy_o
);

    localparam S_IDLE  = 3'd0;
    localparam S_TILE  = 3'd1;              // acc clear (1 cycle)
    localparam S_K     = 3'd2;              // K beats
    localparam S_RQ    = 3'd3;              // requant tail beats
    localparam S_LDONE = 3'd4;              // layer done pulse (1 cycle)
    localparam S_DRAIN = 3'd5;              // V1.3: 3-cycle PE drain

    reg [2:0]        state_r;
    reg [OC_AW-1:0]  oc_total_r;
    reg [N_AW-1:0]   n_total_r;
    reg [K_AW-1:0]   k_total_r;
    reg              last_r;
    reg [TILE_AW-1:0] oc_tiles_r;           // ceil(OC/OC_EDGE)
    reg [TILE_AW-1:0] n_tiles_r;            // ceil(N/N_EDGE)
    reg [TILE_AW-1:0] oc_tile_r;
    reg [TILE_AW-1:0] n_tile_r;
    reg [TILE_AW-1:0] oc_tail_r;
    reg [TILE_AW-1:0] n_tail_r;
    // V1.6: last-tile tails precomputed once per layer (at accept);
    // the S_RQ advance loads them via a compare+mux instead of the
    // 12-level tail_calc chain (dbg8e ctrl -1.856ns owner)
    reg [TILE_AW-1:0] oc_tail_last_r;
    reg [TILE_AW-1:0] n_tail_last_r;
    // V1.7: tail VALUES of the tile being advanced TO, staged every
    // cycle the tile counters hold; the advance edge itself is a
    // reg->reg load (dbg8f ctrl -1.116ns / 12L owner was
    // oc_tiles_r -> last_oc -> next_n -> compare -> mux -> n_tail_r)
    reg [TILE_AW-1:0] oc_tail_next_r;
    reg [TILE_AW-1:0] n_tail_next_r;
    reg [K_AW-1:0]    k_cnt_r;
    reg [TILE_AW-1:0] rq_cnt_r;
    reg [TILE_AW-1:0] rq_limit_r;           // V1.4: oc_tail*n_tail-1,
                                            // loaded at tail updates
    reg [1:0]         drain_cnt_r;          // V1.3: S_DRAIN beat counter
    reg               rd_bank_r;

    localparam [TILE_AW-1:0] OC_EDGE_W = OC_EDGE;
    localparam [TILE_AW-1:0] N_EDGE_W  = N_EDGE;

    // descriptor ceil divisions (constant divisors -> parameter OC/N_EDGE)
    wire [31:0] oc_tiles_w = (dsc_oc_i + OC_EDGE - 1) / OC_EDGE;
    wire [31:0] n_tiles_w  = (dsc_n_i + N_EDGE - 1) / N_EDGE;
    // V1.6: last-tile tail VALUES (same arithmetic the tail_calc
    // function evaluated per advance; computed once here)
    wire [31:0] oc_tail_last_w = dsc_oc_i - (oc_tiles_w - 32'd1) * OC_EDGE;
    wire [31:0] n_tail_last_w  = dsc_n_i  - (n_tiles_w  - 32'd1) * N_EDGE;

    // tile advance decode (n outer, oc inner -- section 3.1)
    wire               last_oc_tile_w = (oc_tile_r == oc_tiles_r - 1'b1);
    wire               last_n_tile_w  = (n_tile_r == n_tiles_r - 1'b1);
    wire               last_tile_w    = last_oc_tile_w && last_n_tile_w;
    wire [TILE_AW-1:0] next_oc_tile_w = last_oc_tile_w ?
                                        {TILE_AW{1'b0}} : (oc_tile_r + 1'b1);
    wire [TILE_AW-1:0] next_n_tile_w  = last_oc_tile_w ?
                                        (n_tile_r + 1'b1) : n_tile_r;
    // V1.7: is the tile being ADVANCED TO the last in its axis -- direct
    // off the CURRENT tile counters, folding the next_oc/next_n +1/wrap
    // chain. oc always changes: its next is last iff oc_tile ==
    // oc_tiles-2 (no wrap) or oc wraps and tiles == 1 (tile 0 is the
    // only/last tile). n either HOLDS (oc advances: the advanced-to
    // tile keeps n_tile_r -- last iff it already IS the last n tile)
    // or advances on oc wrap (next n = n+1 -- last iff n_tile ==
    // n_tiles-2; n_tiles==1 never wraps, last_tile ends the layer).
    wire               oc_next_is_last_w = (oc_tile_r == (oc_tiles_r - 2'd2))
                                           || (last_oc_tile_w
                                               && (oc_tiles_r == 32'd1));
    wire               n_next_is_last_w  = last_oc_tile_w
                                          ? (n_tile_r == (n_tiles_r - 2'd2))
                                          : last_n_tile_w;
    wire               rq_last_w      = (rq_cnt_r == rq_limit_r);
    wire               k_last_w       = (k_cnt_r == k_total_r - 1'b1);

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state_r    <= S_IDLE;
            oc_total_r <= {OC_AW{1'b0}};
            n_total_r  <= {N_AW{1'b0}};
            k_total_r  <= {K_AW{1'b0}};
            last_r     <= 1'b0;
            oc_tiles_r <= {TILE_AW{1'b0}};
            n_tiles_r  <= {TILE_AW{1'b0}};
            oc_tile_r  <= {TILE_AW{1'b0}};
            n_tile_r   <= {TILE_AW{1'b0}};
            oc_tail_r  <= {TILE_AW{1'b0}};
            n_tail_r   <= {TILE_AW{1'b0}};
            oc_tail_last_r <= {TILE_AW{1'b0}};
            n_tail_last_r  <= {TILE_AW{1'b0}};
            oc_tail_next_r <= {TILE_AW{1'b0}};
            n_tail_next_r  <= {TILE_AW{1'b0}};
            k_cnt_r    <= {K_AW{1'b0}};
            rq_cnt_r   <= {TILE_AW{1'b0}};
            rq_limit_r <= {TILE_AW{1'b0}};
            drain_cnt_r<= 2'd0;
            rd_bank_r  <= 1'b0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (dsc_valid_i) begin
                        oc_total_r <= dsc_oc_i;
                        n_total_r  <= dsc_n_i;
                        k_total_r  <= dsc_k_i;
                        last_r     <= dsc_last_i;
                        oc_tiles_r <= oc_tiles_w[TILE_AW-1:0];
                        n_tiles_r  <= n_tiles_w[TILE_AW-1:0];
                        oc_tile_r  <= {TILE_AW{1'b0}};
                        n_tile_r   <= {TILE_AW{1'b0}};
                        // V1.6: first tile's tails via the same mux
                        // shape as the advance below (first tile is
                        // the last iff tiles == 1)
                        oc_tail_last_r <= oc_tail_last_w[TILE_AW-1:0];
                        n_tail_last_r  <= n_tail_last_w[TILE_AW-1:0];
                        oc_tail_r  <= (oc_tiles_w == 32'd1)
                                        ? oc_tail_last_w[TILE_AW-1:0]
                                        : OC_EDGE_W;
                        n_tail_r   <= (n_tiles_w == 32'd1)
                                        ? n_tail_last_w[TILE_AW-1:0]
                                        : N_EDGE_W;
                        // V1.4/V1.5: rq_limit is computed in S_TILE
                        // from the tails loaded here (registered
                        // multiply, off the per-beat path)
                        k_cnt_r    <= {K_AW{1'b0}};
                        rq_cnt_r   <= {TILE_AW{1'b0}};
                        state_r    <= S_TILE;
                    end
                end
                S_TILE: begin
                    // V1.5: rq_limit = oc_tail*n_tail-1 off REGISTERED
                    // tails (loaded by whichever edge entered S_TILE);
                    // recomputed harmlessly while tile_rdy stretches.
                    rq_limit_r <= oc_tail_r * n_tail_r - 1'b1;
                    if (tile_rdy_i) begin
                        state_r <= S_K;     // acc_clr via comb decode (may stretch)
                    end
                end
                S_K: begin
                    k_cnt_r <= k_cnt_r + 1'b1;   // holds K after last beat
                    if (k_last_w) begin
                        rq_cnt_r   <= {TILE_AW{1'b0}};
                        drain_cnt_r<= 2'd0;
                        state_r    <= S_DRAIN;   // V1.3: drain 3 first
                    end
                end
                S_DRAIN: begin
                    // V1.3: beat_en low; the last 3 K-beat products are
                    // still in the PE wall (pe_pack V1.2 three-stage
                    // pipeline + gemm_array V1.3 acc_en_d3). S_RQ may
                    // only start once the final acc write has landed:
                    // last ren at tk -> acc edge tk+4 -> rq lane-mux
                    // sample tk+5, drain occupies tk+1..tk+3.
                    // V1.8: xbuf BMG primitives output register (xbuf
                    // V2.2 contract, 2026-09-17 用户授权) -- X operand
                    // and the W staging reg both land D+2, products
                    // D+5: last ren at tk -> acc edge tk+5 -> rq
                    // sample tk+6, drain occupies tk+1..tk+4 (4 拍).
                    drain_cnt_r <= drain_cnt_r + 1'b1;
                    if (drain_cnt_r == 2'd3) begin
                        state_r <= S_RQ;
                    end
                end
                S_RQ: begin
                    if (rq_rdy_i) begin
                        if (rq_last_w) begin
                            rq_cnt_r <= {TILE_AW{1'b0}};
                            k_cnt_r  <= {K_AW{1'b0}};
                            if (last_tile_w) begin
                                state_r <= S_LDONE;
                            end else begin
                                oc_tile_r <= next_oc_tile_w;
                                n_tile_r  <= next_n_tile_w;
                                // V1.7: advance consumes the STAGED tail
                                // values (computed off the pre-advance
                                // counters = the advanced-to tile; reg->reg
                                // load, no decode in this edge)
                                oc_tail_r <= oc_tail_next_r;
                                n_tail_r  <= n_tail_next_r;
                                rd_bank_r <= ~rd_bank_r;
                                state_r   <= S_TILE;
                            end
                        end else begin
                            rq_cnt_r <= rq_cnt_r + 1'b1;
                        end
                    end
                end
                S_LDONE: begin
                    state_r <= S_IDLE;
                end
                default: begin
                    state_r <= S_IDLE;
                end
            endcase

            // V1.7: stage the advance-time tail values every cycle (they
            // track the CURRENT tile counters; after any state change the
            // next edge re-stages off the new counters -- first advance is
            // always >= S_TILE+S_K beats away, always fresh). Stale during
            // S_IDLE pre-accept; never consumed there.
            oc_tail_next_r <= oc_next_is_last_w ? oc_tail_last_r : OC_EDGE_W;
            n_tail_next_r  <= n_next_is_last_w  ? n_tail_last_r  : N_EDGE_W;
        end
    end

    // outputs: combinational on registered state/counters only
    assign dsc_ready_o  = (state_r == S_IDLE);
    assign busy_o       = (state_r != S_IDLE);
    assign acc_clr_o    = (state_r == S_TILE);
    assign beat_en_o    = (state_r == S_K);
    assign k_cnt_o      = k_cnt_r;
    assign rq_en_o      = (state_r == S_RQ);
    assign rq_idx_o     = rq_cnt_r;
    assign rq_last_o    = (state_r == S_RQ) && rq_last_w;
    assign rd_bank_o    = rd_bank_r;
    assign wr_bank_o    = ~rd_bank_r;
    assign oc_tile_o    = oc_tile_r;
    assign n_tile_o     = n_tile_r;
    assign n_tail_o     = n_tail_r;
    assign oc_tail_o    = oc_tail_r;
    assign layer_done_o = (state_r == S_LDONE);
    assign all_done_o   = (state_r == S_LDONE) && last_r;

endmodule
