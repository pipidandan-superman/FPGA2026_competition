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
    // segmenter -- S_RQ holds (en/idx stable) until accepted
    input  wire               rq_rdy_i,
    output wire               rq_en_o,
    output wire [TILE_AW-1:0] rq_idx_o,
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
    reg [K_AW-1:0]    k_cnt_r;
    reg [TILE_AW-1:0] rq_cnt_r;
    reg [1:0]         drain_cnt_r;          // V1.3: S_DRAIN beat counter
    reg               rd_bank_r;

    // last-tile tile width: full edge except the clamped last column/row
    function [TILE_AW-1:0] tail_calc;
        input [TILE_AW-1:0] total;
        input [TILE_AW-1:0] tiles;
        input [TILE_AW-1:0] idx;
        input [TILE_AW-1:0] t_edge;
        begin
            if (idx == tiles - 1'b1) begin
                tail_calc = total - (tiles - 1'b1) * t_edge;
            end else begin
                tail_calc = t_edge;
            end
        end
    endfunction

    // descriptor ceil divisions (constant divisors -> parameter OC/N_EDGE)
    wire [31:0] oc_tiles_w = (dsc_oc_i + OC_EDGE - 1) / OC_EDGE;
    wire [31:0] n_tiles_w  = (dsc_n_i + N_EDGE - 1) / N_EDGE;

    // tile advance decode (n outer, oc inner -- section 3.1)
    wire               last_oc_tile_w = (oc_tile_r == oc_tiles_r - 1'b1);
    wire               last_n_tile_w  = (n_tile_r == n_tiles_r - 1'b1);
    wire               last_tile_w    = last_oc_tile_w && last_n_tile_w;
    wire [TILE_AW-1:0] next_oc_tile_w = last_oc_tile_w ?
                                        {TILE_AW{1'b0}} : (oc_tile_r + 1'b1);
    wire [TILE_AW-1:0] next_n_tile_w  = last_oc_tile_w ?
                                        (n_tile_r + 1'b1) : n_tile_r;
    wire               rq_last_w      = (rq_cnt_r == oc_tail_r * n_tail_r - 1'b1);
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
            k_cnt_r    <= {K_AW{1'b0}};
            rq_cnt_r   <= {TILE_AW{1'b0}};
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
                        oc_tail_r  <= tail_calc(dsc_oc_i, oc_tiles_w,
                                                 {TILE_AW{1'b0}}, OC_EDGE);
                        n_tail_r   <= tail_calc(dsc_n_i, n_tiles_w,
                                                 {TILE_AW{1'b0}}, N_EDGE);
                        k_cnt_r    <= {K_AW{1'b0}};
                        rq_cnt_r   <= {TILE_AW{1'b0}};
                        state_r    <= S_TILE;
                    end
                end
                S_TILE: begin
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
                    drain_cnt_r <= drain_cnt_r + 1'b1;
                    if (drain_cnt_r == 2'd2) begin
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
                                oc_tail_r <= tail_calc(oc_total_r, oc_tiles_r,
                                                       next_oc_tile_w, OC_EDGE);
                                n_tail_r  <= tail_calc(n_total_r, n_tiles_r,
                                                       next_n_tile_w, N_EDGE);
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
    assign rd_bank_o    = rd_bank_r;
    assign wr_bank_o    = ~rd_bank_r;
    assign oc_tile_o    = oc_tile_r;
    assign n_tile_o     = n_tile_r;
    assign n_tail_o     = n_tail_r;
    assign oc_tail_o    = oc_tail_r;
    assign layer_done_o = (state_r == S_LDONE);
    assign all_done_o   = (state_r == S_LDONE) && last_r;

endmodule
