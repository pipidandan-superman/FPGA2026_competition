/************************************************************************
 * File Name       : yolo_addrgen.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_addrgen
 * Description     : M7 im2col address generator for the X-tile fill
 *                   path (architecture baseline sections 3.1/3.5).
 *                   Walks one N_EDGE-wide output tile of the im2col
 *                   matrix: n (tile-local column) outer, k inner,
 *                   one beat per cycle:
 *                     k   = ic*(KH*KW) + kh*KW + kw   (K-order contract,
 *                           same decomposition as yolo_conv_core V1.1)
 *                     ih  = oy*SH + kh - PH ;  iw = ox*SW + kw - PW
 *                     pad = !(0<=ih<IH && 0<=iw<IW)
 *                     x_addr = ic*(IH*IW) + ih*IW + iw   (X plane CHW)
 *                   Pad beats bypass memory and supply the zero-point
 *                   fold constant instead (first layer -128, later
 *                   layers 0) -- baseline 3.5 first-layer z-fold.
 *
 *                   Geometry is sampled at the start_i pulse into
 *                   internal registers (descriptor semantics for M8).
 *                   Tail tiles: n_len_i is programmed pre-clamped by
 *                   the controller (addrgen trusts it).
 *                   Plane size contract: IC*IH*IW < 2^31, N < 2^16.
 *
 *                   V1.1 timing closure restructure (B0 dbg7c: the
 *                   V1.0 capture-beat combinational divide
 *                   n_start/ow was the -31ns owner, 95 logic levels;
 *                   the per-beat oy*sh/ox*sw/ih*iw multiply chains
 *                   fed the xbuf -10.8ns path):
 *                     - start -> beat0 now runs S_DIV (16-cycle
 *                       shift-subtract divider, quotient+remainder)
 *                       -> S_PREP1 (layer-constant products:
 *                       oy*sh, ox*sw, ih*iw, sh*iw, (kh-1)*iw)
 *                       -> S_PREP2 (ih0 capture + m_iw sub)
 *                       -> S_PREP3 (row_off init multiply) -> S_RUN.
 *                       Latency 0 -> 21 cycles; the loader only waits
 *                       for done_o so the contract impact is +21 idle
 *                       cycles per tile, fully hidden under the
 *                       parallel W DMA fill (>= 264 beats).
 *                     - S_RUN per-beat work is ADDS ONLY (row_off /
 *                       plane_base increment, two 32-bit adds for the
 *                       address). Invariants (init at PREP, maintained
 *                       by +/- constants at each counter event):
 *                         oy_sh  = oy*sh         (+= sh on oy wrap)
 *                         ox_sw  = ox*sw          (+= sw, ->0 on wrap)
 *                         row_off= (oy_sh+kh-ph)*iw_c
 *                                  (+= iw_c on kh+1 ; -= (kh_c-1)*iw_c
 *                                   on kh->0 ; on oy wrap -(kh_c-1)*iw_c
 *                                   +sh*iw_c = +m_iw_r, one add (V1.2))
 *                         plane_base = ic*ih*iw  (+= plane_sz on ic+1,
 *                                   ->0 at k end)
 *                       Beat values are bit-identical to the V1.0
 *                   direct decode for all in-contract geometries
 *                   (golden stream unchanged, M7 gate rerun).
 *
 *                   V1.2 timing restructure (B0 dbg8e: the pad/window
 *                   decode running straight out to the X-buffer write
 *                   port was the -1.98ns / 11-level owner; the S_RUN
 *                   last-k sub+add chain on row_off_r was -1.54ns):
 *                     - all beat outputs (vld/x_addr/pad/pad_val/k/n)
 *                       presented through OUTPUT REGISTER stages (V1.2:
 *                       one cycle; V1.3: capture + presentation, two
 *                       cycles after their internal S_RUN beat -- the
 *                       window compare moved off the add chain). Stream
 *                       values identical, +1 cycle shift; start ->
 *                       beat0 19 -> 20 cycles, still fully hidden.
 *                       done_o keeps the V1.1 relation: pulses exactly
 *                       one cycle after the last PRESENTED beat with
 *                       vld_o already low (done_d1_r two-stage).
 *                     - oy-wrap row_off update folds sh*iw - (kh-1)*iw
 *                       into the layer constant m_iw_r: ONE wide add
 *                       either way (two parallel adders + mux) instead
 *                       of a serial sub+add (same value mod 2^42).
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M7).
 *   - V1.1 (2026-09-16) by LSL : iterative divide + incremental per-
 *     beat address (B0 -31ns root cause fix); beat stream unchanged.
 *     另修 iw_full_w 26 位线上的 [AW-1:0] 越界位选（先符号扩展到
 *     32 位——M7 首跑 beat4 起 x 的根因）。
 *   - V1.2 (2026-09-16) by LSL : 输出寄存级（vld/x_addr/pad/pad_val/
 *     k/n 全部 +1 拍呈现，start→beat0 19→20 拍；done_o 保持"末呈现
 *     拍后一拍脉冲、vld 已落"关系）+ oy 环绕 row_off 更新折叠
 *     m_iw_r 单加（并行双加法器+选择，模 2^42 逐位等价）。修 dbg8e
 *     xbuf −1.98ns/11L（pad 解码直通 BMG DIADI）与 addrgen
 *     −1.54ns/8L（last_k 串行减加）。字节流值不变（+1 拍平移）。
 *     门重跑：M7 + M4 + M10 + B0 v16。dbg8f 后再精化：m_iw_r 装载
 *     从 S_PREP1 挪到 S_PREP2，改用已寄存的 sh_iw_r/kh1_iw_r 做纯
 *     寄存器减（S_PREP1 原式重建了两个乘法，9 级，成了 dbg8f
 *     −1.732ns 顶_owner；首用最早在首 S_RUN 拍末，就绪裕量 ≥1 拍）。
 *     值不变。门重跑：M7 v17 + M10 v17 + B0 v17。精化二（dbg8g
 *     addrgen −1.463ns/9L：oy_sh_r→row_off_r，PREP2 的 (oy_sh−ph)*iw
 *     26×16 乘法与 m_iw 减法同拍）：增 S_PREP3 态——ih0 于 PREP2 寄
 *     存、PREP3 单独做乘法（DSP 吸收），start→beat0 20→21 拍（仍远
 *     小于 W 填充 ≥264 拍）。值不变。门重跑：M7 v18 + M10 v18 + B0 v18。
 *   - V1.3 (2026-09-17) by LSL : B0 v24 ooc 残档两族位精确修复：
 *     ① kh_r→pad_o/x_addr_o −0.158/−0.138——窗口解码（ih_full =
 *     oy_sh+kh−ph 串行加减 4L → 边界比较 → in_b 选择）全部挤在内部
 *     S_RUN 拍与输出寄存之间的一个周期里。拆为两级输出寄存：A 级
 *     捕获内部拍中间量（ih_full/iw_full/完整和 x_addr + vld/k/n，
 *     仅加法、自寄存器发火），B 级呈现（边界比较 3L + in_b 选择，
 *     从 A 级 FF 发火）。节拍流值逐位不变，呈现比 V1.2 整体 +1 拍
 *     （start→beat0 21→22，仍远小于 W 填充 ≥264 拍；done_o 保持
 *     "末呈现拍后一拍脉冲"关系，链上加 lastb_d_r）。首版把 B 级比
 *     较写进了 A 级同沿——pad_o 实际消费的是上一拍捕获的窗口（连
 *     续 pad 拍掩住了错位；M7 v25a FAIL errors=66637，首个错恰在
 *     首个域内拍 beat4，transcript 留档 m7_v25a_xsim_fail.log）。
 *     ② k_len_c→row_off_r −0.157/−0.121——last_k = (k_cnt ==
 *     k_len_c−1) 的 16 位减+比较直接选择 42 位 row_off 更新路径。
 *     改为超前一时钟拍预测：k_len_m1_c 在描述符接受沿一次登记，
 *     每拍把"下一拍 k_cnt 是否到末拍"的比较结果写入 last_k 寄存器
 *     （归纳可证：beat N 的 last_k 恒等于旧式 (k_cnt==k_len_c−1)，含
 *     k_len==1 与 PREP3 首拍装载），S_RUN 的 row_off 更新选择从 FF
 *     发火，只剩单个 42 位加法器。
 *     门重跑：M7 v25（v25a FAIL 后修正复跑）+ M10 v25 + M12 csr v25
 *     + B0 v25。
 ************************************************************************/

module yolo_addrgen #(
    parameter AW = 32                       // X plane byte address width
) (
    input  wire          clk_i,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [15:0]   ih_i,              // input height
    input  wire [15:0]   iw_i,              // input width
    input  wire [15:0]   ow_i,              // output width (n -> oy/ox)
    input  wire [15:0]   ic_i,              // input channels (K2304 -> 256)
    input  wire [7:0]    kh_i,              // kernel height
    input  wire [7:0]    kw_i,              // kernel width
    input  wire [7:0]    sh_i,              // stride h
    input  wire [7:0]    sw_i,              // stride w
    input  wire [7:0]    ph_i,              // pad h
    input  wire [7:0]    pw_i,              // pad w
    input  wire [15:0]   k_len_i,           // K = IC*KH*KW
    input  wire [15:0]   n_start_i,         // tile first output index
    input  wire [15:0]   n_len_i,           // tile width (pre-clamped)
    input  wire          first_i,           // 1: pad=-128 (z fold), 0: pad=0
    output wire          busy_o,
    output reg           done_o,            // 1-cycle pulse, one cycle
                                           // AFTER the last presented beat
    output reg           vld_o,             // 1 beat/cycle while running
    output reg  [AW-1:0] x_addr_o,          // X plane byte address (CHW)
    output reg           pad_o,             // 1 = pad beat (bypass memory)
    output reg  [7:0]    pad_val_o,         // -128 (first) or 0
    output reg  [15:0]   k_o,               // K index (column BRAM depth)
    output reg  [15:0]   n_o                // tile-local column index
);

    localparam S_IDLE  = 3'd0;
    localparam S_DIV   = 3'd1;              // 16-cycle shift-subtract divide
    localparam S_PREP1 = 3'd2;              // layer-constant products
    localparam S_PREP2 = 3'd3;              // m_iw sub + ih0 capture
    localparam S_PREP3 = 3'd4;              // row_off init multiply (V1.2)
    localparam S_RUN   = 3'd5;

    reg [2:0]         state;
    reg [15:0]        n_loc;
    reg [15:0]        oy_r;
    reg [15:0]        ox_r;
    reg [15:0]        k_cnt;
    reg [15:0]        ic_r;
    reg [7:0]         kh_r;
    reg [7:0]         kw_r;
    // captured geometry
    reg [15:0]        ih_c;
    reg [15:0]        iw_c;
    reg [15:0]        ow_c;
    reg [7:0]         sh_c;
    reg [7:0]         sw_c;
    reg [7:0]         ph_c;
    reg [7:0]         pw_c;
    reg [7:0]         kh_c;
    reg [7:0]         kw_c;
    reg [15:0]        k_len_c;
    reg [15:0]        n_len_c;
    reg               first_c;

    // ---- V1.1 divider state (S_DIV) ----
    reg [15:0]        n_saved_r;            // dividend
    reg [15:0]        div_d_r;              // divisor (ow)
    reg [16:0]        rem_r;                // partial remainder
    reg [15:0]        quo_r;                // quotient
    reg [4:0]         div_cnt_r;            // bit counter 16..1
    wire               n_bit_w  = n_saved_r[div_cnt_r - 5'd1];
    wire [16:0]        rem_sh_w = {rem_r[15:0], n_bit_w};
    wire               ge_w     = (rem_sh_w >= {1'b0, div_d_r});

    // ---- V1.1 derived per-beat state (invariants, see header) ----
    reg [23:0]        oy_sh_r;              // oy*sh
    reg [23:0]        ox_sw_r;              // ox*sw
    reg [23:0]        sh_iw_r;              // sh*iw_c
    reg [23:0]        kh1_iw_r;             // (kh_c-1)*iw_c
    reg signed [41:0] m_iw_r;               // V1.2: sh_iw - kh1_iw (last_k
                                            // wrap update as ONE add)
    reg signed [25:0] ih0_r;                // V1.2: oy_sh - ph (PREP2
                                            // capture; PREP3 multiplies)
    reg [31:0]        plane_sz_c;           // ih_c*iw_c
    reg [31:0]        plane_base_r;         // ic_r * plane_sz_c
    reg signed [41:0] row_off_r;            // (oy_sh+kh-ph)*iw_c
    // S_PREP1 products
    wire signed [25:0] ih0_w = $signed(oy_sh_r) - $signed({18'd0, ph_c});
    // signed zero-extends for the add/sub constants (sign discipline:
    // every concat entering signed arithmetic is $signed-wrapped)
    wire signed [41:0] iw_sext_w  = $signed({26'd0, iw_c});
    wire signed [41:0] kh1_iw_sext_w = $signed({18'd0, kh1_iw_r});

    // ---- per-beat window decode: adds only ----
    wire signed [25:0] ih_full_w = $signed(oy_sh_r) + $signed({18'd0, kh_r})
                                   - $signed({18'd0, ph_c});
    wire signed [25:0] iw_full_w = $signed(ox_sw_r) + $signed({18'd0, kw_r})
                                   - $signed({18'd0, pw_c});
    wire signed [25:0] ih_lim_w = $signed({10'd0, ih_c});
    wire signed [25:0] iw_lim_w = $signed({10'd0, iw_c});
    // (V1.3: the in_b compare itself moved to the presentation cycle,
    //  reading the captured ih_full_r/iw_full_r -- see in_b_d_w below)

    // low-32 adds: two's-complement addition is sign-agnostic, the
    // wrapped bit pattern equals the V1.0 32-bit expression exactly
    // (iw_full sign-extended 26->32 first: a bare [AW-1:0] part-select
    // on the 26-bit wire reads bits 31:26 out of bounds -> x in sim)
    wire signed [31:0] iw_full_32_w = iw_full_w;
    wire [AW-1:0] x_addr_w = plane_base_r + row_off_r[AW-1:0]
                             + iw_full_32_w;

    // ---- internal beat values (V1.2: feed the output register stage;
    //      the pad/window decode no longer runs straight out to the
    //      X-buffer write port -- dbg8e xbuf owner -1.98ns/11L) ----
    wire              vld_int_w    = (state == S_RUN);
    wire [7:0]        pad_val_int_w= first_c ? 8'h80 : 8'h00;

    // ---- V1.3: window decode split across TWO output-register stages
    //      (v24 owner kh_r -> pad_o/x_addr_o -0.158/-0.138: the whole
    //      ih_full add-sub chain + boundary compares + in_b mux shared
    //      the single cycle between the internal beat and the output
    //      registers). Stage A captures the internal beat's
    //      intermediates (adds only, launched from registers); stage B
    //      presents, running the boundary compares and the in_b select
    //      off the CAPTURED values (compare 3L + mux, from FFs).
    //      Presented stream: values bit-identical, one cycle later than
    //      V1.2 (start -> beat0 21 -> 22 cycles, still fully hidden
    //      under the >=264-beat W fill). ih_c/iw_c are layer-static, no
    //      staleness. FIRST CUT put pad_o's compare in stage A's edge --
    //      it consumed the PREVIOUS beat's captured window (pad beats
    //      masked it; M7 v25a FAIL errors=66637 first at the first
    //      in-bounds beat); the two-stage form keeps vld/pad/x_addr
    //      aligned.
    reg              vld_a_r;        // stage-A beat record
    reg [15:0]       k_a_r;
    reg [15:0]       n_a_r;
    reg [7:0]        pad_val_a_r;
    reg signed [25:0] ih_full_a_r;   // beat N's window rows
    reg signed [25:0] iw_full_a_r;
    reg [AW-1:0]     x_addr_a_r;     // beat N's full address sum
    wire              in_b_d_w = (ih_full_a_r >= 0)
                              && (ih_full_a_r < ih_lim_w)
                              && (iw_full_a_r >= 0)
                              && (iw_full_a_r < iw_lim_w);

    assign busy_o    = (state != S_IDLE);

    // beat-end compares (shared by the FSM and the done pulse)
    // V1.3: last_k is PREDICTED one beat ahead into a register (v24 owner
    // k_len_c -> row_off_r -0.157: the 16b sub+compare steered the 42b
    // row_off update mux in the same edge). k_len_m1_c is registered once
    // at descriptor accept; each edge stores whether the NEXT beat's
    // k_cnt hits the last K index -- by induction last_k at beat N equals
    // the old (k_cnt == k_len_c-1) exactly, including k_len == 1 and the
    // PREP3 load for the first S_RUN beat.
    reg [15:0]        k_len_m1_c;
    reg               last_k;
    wire last_n = (n_loc == n_len_c - 16'd1);
    wire ox_wrap_w = (ox_r == ow_c - 16'd1);
    wire kw_last_w = (kw_r == kw_c - 8'd1);
    wire kh_last_w = (kh_r == kh_c - 8'd1);

    // V1.2/V1.3 output path: stage A captures the internal S_RUN beat
    // (window decode intermediates + bookkeeping), stage B presents every
    // beat output TWO cycles after its internal S_RUN cycle (V1.3: +1 vs
    // V1.2; stream values identical, consumers are vld-gated). done_o
    // keeps the same relation -- pulses exactly one cycle after the LAST
    // PRESENTED beat, vld_o already low (lastb_d_r + done_d1_r chain).
    reg lastb_d_r;
    reg done_d1_r;
    wire last_beat_int_w = vld_int_w && last_k && last_n;

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            vld_a_r      <= 1'b0;
            k_a_r        <= 16'd0;
            n_a_r        <= 16'd0;
            pad_val_a_r  <= 8'h00;
            ih_full_a_r  <= 26'sd0;
            iw_full_a_r  <= 26'sd0;
            x_addr_a_r   <= {AW{1'b0}};
            lastb_d_r    <= 1'b0;
            vld_o        <= 1'b0;
            x_addr_o     <= {AW{1'b0}};
            pad_o        <= 1'b0;
            pad_val_o    <= 8'h00;
            k_o          <= 16'd0;
            n_o          <= 16'd0;
            done_d1_r    <= 1'b0;
            done_o       <= 1'b0;
        end else begin
            // stage A: capture the internal beat
            vld_a_r      <= vld_int_w;
            k_a_r        <= k_cnt;
            n_a_r        <= n_loc;
            pad_val_a_r  <= pad_val_int_w;
            ih_full_a_r  <= ih_full_w;
            iw_full_a_r  <= iw_full_w;
            x_addr_a_r   <= x_addr_w;
            lastb_d_r    <= last_beat_int_w;
            // stage B: presentation (compare + select from stage-A FFs)
            vld_o        <= vld_a_r;
            x_addr_o     <= in_b_d_w ? x_addr_a_r : {AW{1'b0}};
            pad_o        <= ~in_b_d_w;
            pad_val_o    <= pad_val_a_r;
            k_o          <= k_a_r;
            n_o          <= n_a_r;
            done_d1_r    <= lastb_d_r;
            done_o       <= done_d1_r;
        end
    end

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            n_loc    <= 16'd0;
            oy_r     <= 16'd0;
            ox_r     <= 16'd0;
            k_cnt    <= 16'd0;
            ic_r     <= 16'd0;
            kh_r     <= 8'd0;
            kw_r     <= 8'd0;
            ih_c     <= 16'd0;
            iw_c     <= 16'd0;
            ow_c     <= 16'd0;
            sh_c     <= 8'd0;
            sw_c     <= 8'd0;
            ph_c     <= 8'd0;
            pw_c     <= 8'd0;
            kh_c     <= 8'd0;
            kw_c     <= 8'd0;
            k_len_c  <= 16'd0;
            n_len_c  <= 16'd0;
            first_c  <= 1'b0;
            n_saved_r<= 16'd0;
            div_d_r  <= 16'd0;
            rem_r    <= 17'd0;
            quo_r    <= 16'd0;
            div_cnt_r<= 5'd0;
            oy_sh_r  <= 24'd0;
            ox_sw_r  <= 24'd0;
            sh_iw_r  <= 24'd0;
            kh1_iw_r <= 24'd0;
            plane_sz_c    <= 32'd0;
            plane_base_r  <= 32'd0;
            row_off_r     <= 42'sd0;
            m_iw_r        <= 42'sd0;
            ih0_r         <= 26'sd0;
            k_len_m1_c    <= 16'd0;
            last_k        <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        // descriptor capture (geometry sampled once)
                        ih_c     <= ih_i;
                        iw_c     <= iw_i;
                        ow_c     <= ow_i;
                        kh_c     <= kh_i;
                        kw_c     <= kw_i;
                        sh_c     <= sh_i;
                        sw_c     <= sw_i;
                        ph_c     <= ph_i;
                        pw_c     <= pw_i;
                        k_len_c  <= k_len_i;
                        k_len_m1_c <= k_len_i - 16'd1;  // V1.3: registered
                                                        // once, off the
                                                        // per-beat compare
                        n_len_c  <= n_len_i;
                        first_c  <= first_i;
                        // divider init: oy = n_start/ow, ox = n_start%ow
                        // (ow=0 degenerates to garbage, same trust level
                        //  as the V1.0 combinational divide)
                        n_saved_r<= n_start_i;
                        div_d_r  <= ow_i;
                        rem_r    <= 17'd0;
                        quo_r    <= 16'd0;
                        div_cnt_r<= 5'd16;
                        state    <= S_DIV;
                    end
                end
                S_DIV: begin
                    // restoring division, MSB first: bit div_cnt-1
                    rem_r <= ge_w ? (rem_sh_w - {1'b0, div_d_r}) : rem_sh_w;
                    quo_r[div_cnt_r - 5'd1] <= ge_w;
                    div_cnt_r <= div_cnt_r - 5'd1;
                    if (div_cnt_r == 5'd1) begin
                        state <= S_PREP1;
                    end
                end
                S_PREP1: begin
                    // layer-constant products (parallel, off the beat
                    // path). Widths exact: 16x8<2^24, 8x16<2^24, 16x16<2^32
                    oy_sh_r  <= quo_r * sh_c;
                    ox_sw_r  <= rem_r[15:0] * sw_c;
                    plane_sz_c <= ih_c * iw_c;
                    sh_iw_r  <= sh_c * iw_c;
                    kh1_iw_r <= (kh_c - 8'd1) * iw_c;  // kh_c>=1 contract
                    state    <= S_PREP2;
                end
                S_PREP2: begin
                    oy_r   <= quo_r;
                    ox_r   <= rem_r[15:0];
                    // V1.2: last_k oy-wrap constant = sh_iw - kh1_iw
                    // off the REGISTERED PREP1 products (reg-reg sub,
                    // ~5 levels; loading it in S_PREP1 rebuilt the two
                    // multiplies and became the dbg8f -1.73ns owner).
                    // Ready >= 1 cycle before the first possible last_k.
                    m_iw_r       <= $signed({18'd0, sh_iw_r})
                                  - $signed({18'd0, kh1_iw_r});
                    // V1.2 (dbg8g): row_off init (oy_sh-ph)*iw was a
                    // 26x16 multiply + the m_iw sub in ONE PREP cycle
                    // (oy_sh_r -> row_off_r -1.463ns/9L) -- the ih0 term
                    // registers here, PREP3 below gives the multiply
                    // its own cycle (DSP-absorbable, ~2-3L).
                    ih0_r        <= ih0_w;
                    plane_base_r <= 32'd0;
                    n_loc   <= 16'd0;
                    k_cnt   <= 16'd0;
                    ic_r    <= 16'd0;
                    kh_r    <= 8'd0;
                    kw_r    <= 8'd0;
                    state   <= S_PREP3;
                end
                S_PREP3: begin
                    // row_off init = (oy*sh - ph)*iw, one registered
                    // multiply alone in this cycle (V1.2; was in PREP2)
                    row_off_r <= ih0_r * $signed({26'd0, iw_c});
                    // V1.3: first S_RUN beat's last_k (k_cnt loads 0)
                    last_k    <= (16'd0 == k_len_m1_c);
                    state     <= S_RUN;
                end
                S_RUN: begin
                    if (last_k) begin
                        // k end: ic/kh reset to 0 (row_off -= (kh-1)*iw;
                        // oy wrap folds the sh*iw term into m_iw_r -- ONE
                        // wide add either way, V1.2), n advances, plane
                        // restarts
                        k_cnt   <= 16'd0;
                        // next beat's k_cnt = 0: predict its last_k
                        last_k  <= (16'd0 == k_len_m1_c);
                        ic_r    <= 16'd0;
                        kh_r    <= 8'd0;
                        kw_r    <= 8'd0;
                        plane_base_r <= 32'd0;
                        row_off_r   <= ox_wrap_w ? (row_off_r + m_iw_r)
                                                  : (row_off_r - kh1_iw_sext_w);
                        if (last_n) begin
                            state  <= S_IDLE;
                        end else begin
                            n_loc <= n_loc + 16'd1;
                            ox_r  <= ox_wrap_w ? 16'd0 : (ox_r + 16'd1);
                            oy_r  <= ox_wrap_w ? (oy_r + 16'd1) : oy_r;
                            ox_sw_r <= ox_wrap_w ? 24'd0 : (ox_sw_r + sw_c);
                            oy_sh_r <= ox_wrap_w ? (oy_sh_r + sh_c) : oy_sh_r;
                        end
                    end else begin
                        k_cnt <= k_cnt + 16'd1;
                        // V1.3: predict the NEXT beat's last_k off the
                        // next k_cnt (= k_cnt+1 here) -- the row_off
                        // update mux below then selects from a FF
                        last_k <= ((k_cnt + 16'd1) == k_len_m1_c);
                        if (kw_last_w) begin
                            kw_r <= 8'd0;
                            if (kh_last_w) begin
                                // kh wrap: ic advances, ih -> oy_sh-ph
                                kh_r <= 8'd0;
                                ic_r <= ic_r + 16'd1;
                                plane_base_r <= plane_base_r + plane_sz_c;
                                row_off_r    <= row_off_r - kh1_iw_sext_w;
                            end else begin
                                // kh+1: ih += 1
                                kh_r <= kh_r + 8'd1;
                                row_off_r <= row_off_r + iw_sext_w;
                            end
                        end else begin
                            kw_r <= kw_r + 8'd1;
                        end
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
