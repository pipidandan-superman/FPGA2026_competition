/************************************************************************
 * File Name       : tb_yolo_acc_dual.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_acc_dual
 * Description     : Standalone gate TB for the MAC-cell dual INT32
 *                   accumulator (PE manual section 10 accumulator row).
 *
 *   Oracle principle (independent of the DUT adder):
 *     The TB keeps its own INT64 partial sums and updates them at the
 *     drive edge with plain 64-bit adds -- never by reading the DUT.
 *     A pass requires the DUT's INT32 accumulator to equal the INT64
 *     oracle sign-extended bit-for-bit (any wrap in the contract
 *     domain would mismatch), per GEMM manual section 14: integer
 *     accumulation is checked against a WIDER independent oracle.
 *
 *   Check discipline (every armed negedge, no sampled-window gaps):
 *     - active lanes:  acc_o === sext64(eacc)   (value + hold + no
 *       premature update, all in one invariant);
 *     - masked lanes:  acc_o === snapshot taken at the tile's first_k
 *       beat (structural mask must never touch state);
 *     - acc_done_o === a posedge mirror of (in_valid & last_k): done
 *       pulses exactly once per completed tile, never during
 *       rst/clr, never for last_k without in_valid;
 *     - conservation: tiles_done === tiles_started - aborted.
 *
 *   Drive discipline (lesson from the PE TB, enforced structurally):
 *     EVERY negedge from arm to finish drives the inputs -- gaps use
 *     gapn(), which drives an idle beat each cycle. A bare
 *     @(negedge) after a valid beat would leave in_valid=1 on the
 *     wires and re-sample the product at the next posedge.
 *
 *     $random modulo must be computed on the UNSIGNED concat in
 *     expression context: idx = {$random(seed)} % N. Assigning the
 *     concat to a signed integer FIRST re-signs it -- negative
 *     array indices silently vanish whole tiles and X arguments pass
 *     4-state compares vacuously. beat() carries an X-tripwire so
 *     that failure class is loud, not silent.
 *
 *   Phases (PE manual section 10 accumulator row):
 *     A1 K_SWEEP        K=1/27/32/576/2304 contiguous tiles
 *     A2 RESUME         K=2304 as [576,1152,576] and K=64 as
 *                       [1,1,27,1,34] with idle gaps (no first_k on
 *                       block boundaries -- partial sums preserved)
 *     A3 CLEAR_RESTART  mid-tile clr -> zeros verified -> fresh tiles;
 *                       clr while idle right after a done; raw
 *                       clr+valid same-edge priority probe
 *     A4 MASK           masks 01/10/11, lane re-activation across
 *                       back-to-back tiles, masked lane on first_k
 *     A5 STALL          25% idle beats with stale/random products,
 *                       one raw last_k beat with in_valid=0
 *     A6 RESET_MID      rst mid-K=2304 (tile lost, no done); rst on
 *                       the last beat's edge (reset priority KILLS
 *                       the last product -- tile aborts, no done);
 *                       fresh tiles after each
 *     A7 K1_CORNER      first_k=last_k same beat, extreme products
 *     A8 EXTREME_SUM    K=2304 constants: +16384 (manual section 8
 *                       bound +37,748,736 pinned by literal), -16384,
 *                       +/-17-bit stress (65535/-65536), alternate
 *     A9 RANDOM_TILES   200 tiles, random K/mask/gaps/idles/corners,
 *                       half back-to-back restarts (next first_k the
 *                       beat right after last_k)
 *
 *   Timing conventions (mirror the PE TB):
 *     - stimulus at negedge (NBA); the DUT samples at the following
 *       posedge; the DUT state and the TB oracle/orientation
 *       registers commit in the same NBA region, so the negedge
 *       checker always sees a consistent pre/post pair;
 *     - acc_done_o and the tile-start/done orientation flags are
 *       posedge mirrors, compared one negedge later.
 *
 *   EES markers: EES_SUMMARY checks=<n> errors=<n>
 *                EES_VIVADO_RESULT PASS|FAIL
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release.
 ************************************************************************/

`timescale 1ns / 1ps

module tb_yolo_acc_dual;

    // ---- clock: 100 MHz ----
    reg clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    // ---- DUT wiring ----
    reg                rst_i;
    reg                clr_i;
    reg                in_valid_i;
    reg  signed [16:0] p0_i, p1_i;
    reg  [1:0]         lane_mask_i;
    reg                first_k_i, last_k_i;
    wire signed [31:0] acc0_o, acc1_o;
    wire               acc_done_o;

    yolo_acc_dual dut (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .clr_i       (clr_i),
        .in_valid_i  (in_valid_i),
        .p0_i        (p0_i),
        .p1_i        (p1_i),
        .lane_mask_i (lane_mask_i),
        .first_k_i   (first_k_i),
        .last_k_i    (last_k_i),
        .acc0_o      (acc0_o),
        .acc1_o      (acc1_o),
        .acc_done_o  (acc_done_o)
    );

    // ---- bookkeeping ----
    integer checks = 0;
    integer errors = 0;
    integer tiles_started = 0, tiles_done = 0, tiles_aborted = 0;
    reg     active_tile = 1'b0;
    string  phase = "init";
    reg     chk_en = 1'b0;
    // manual section 8 bound pin (A8 first tile)
    integer a8_pin_pend = 0;

    // ---- independent INT64 oracle + tile orientation ----
    reg signed [63:0] eacc0 = 64'sd0, eacc1 = 64'sd0;
    reg [1:0]  cur_mask = 2'b11;      // lanes compared vs oracle this tile
    reg [31:0] snap0 = 32'd0, snap1 = 32'd0; // masked-lane snapshots

    // posedge mirrors: what the DUT orientation logic should have done
    reg exp_done_r = 1'b0, exp_start_r = 1'b0;
    always @(posedge clk_i) begin
        if (rst_i || clr_i) begin
            exp_done_r  <= 1'b0;
            exp_start_r <= 1'b0;
        end else begin
            exp_done_r  <= in_valid_i & last_k_i;
            exp_start_r <= in_valid_i & first_k_i;
        end
    end

    // ---- checker: one process, blocking, fully deterministic ----
    always @(negedge clk_i) begin
        if (chk_en) begin
            checks = checks + 1;
            if (rst_i || clr_i) begin
                // the posedge just before this negedge cleared state
                if (exp_done_r) begin
                    // a done pulse raced the clear: its products had
                    // all entered earlier -- legal, count it
                    tiles_done = tiles_done + 1;
                    active_tile = 1'b0;
                end else if (active_tile) begin
                    tiles_aborted = tiles_aborted + 1;
                    active_tile = 1'b0;
                end
                if (({{32{acc0_o[31]}}, acc0_o} !== eacc0) ||
                    ({{32{acc1_o[31]}}, acc1_o} !== eacc1)) begin
                    errors = errors + 1;
                    $display("EES_ACC_ERR phase=%s cleared-state acc0=%0d acc1=%0d exp=%0d/%0d",
                             phase, acc0_o, acc1_o, eacc0, eacc1);
                end
            end else begin
                // value invariants every cycle (active lanes vs INT64)
                if (cur_mask[0] && ({{32{acc0_o[31]}}, acc0_o} !== eacc0)) begin
                    errors = errors + 1;
                    $display("EES_ACC_ERR phase=%s lane0 acc=%0d exp64=%0d",
                             phase, acc0_o, eacc0);
                end
                if (cur_mask[1] && ({{32{acc1_o[31]}}, acc1_o} !== eacc1)) begin
                    errors = errors + 1;
                    $display("EES_ACC_ERR phase=%s lane1 acc=%0d exp64=%0d",
                             phase, acc1_o, eacc1);
                end
                // masked lanes: frozen since this tile's first_k beat
                if (!cur_mask[0] && (acc0_o !== snap0)) begin
                    errors = errors + 1;
                    $display("EES_ACC_ERR phase=%s masked lane0 moved: %0d -> %0d",
                             phase, snap0, acc0_o);
                end
                if (!cur_mask[1] && (acc1_o !== snap1)) begin
                    errors = errors + 1;
                    $display("EES_ACC_ERR phase=%s masked lane1 moved: %0d -> %0d",
                             phase, snap1, acc1_o);
                end
                // done pulse exactness
                if (acc_done_o !== exp_done_r) begin
                    errors = errors + 1;
                    $display("EES_ACC_ERR phase=%s done=%b exp=%b",
                             phase, acc_done_o, exp_done_r);
                end
                if (exp_done_r) begin
                    tiles_done = tiles_done + 1;
                    if (a8_pin_pend == 1) begin
                        a8_pin_pend = 0;
                        if (acc0_o !== 32'sd37748736) begin
                            errors = errors + 1;
                            $display("EES_ACC_ERR A8 manual-bound pin acc0=%0d want 37748736",
                                     acc0_o);
                        end else
                            $display("EES_ACC_INFO A8 manual s8 bound pinned: %0d",
                                     acc0_o);
                    end
                end
                if (exp_start_r)
                    tiles_started = tiles_started + 1;
                // a K=1 tile (first_k=last_k same beat) completes in the
                // SAME mirror cycle -- nothing stays active afterwards
                if (exp_start_r && !exp_done_r)
                    active_tile = 1'b1;
                else if (exp_done_r)
                    active_tile = 1'b0;
            end
        end
    end

    // ---- stimulus: one product beat at negedge ----
    // raw first/last tags: a tag may be driven high together with
    // in_valid=0 (A5 negative probe); both DUT and mirrors gate on
    // in_valid, the oracle updates only on val.
    task automatic beat(input signed [16:0] q0, input signed [16:0] q1,
                        input [1:0] msk, input val,
                        input fk, input lk);
        begin
            // X-tripwire: X reaching both the oracle and the DUT would
            // pass every 4-state compare vacuously -- fail loudly here
            if ((^q0 === 1'bx) || (^q1 === 1'bx)) begin
                errors = errors + 1;
                $display("EES_ACC_ERR phase=%s X product in stimulus q0=%b q1=%b",
                         phase, q0, q1);
            end
            if (val) begin
                if (fk) begin
                    if (msk[0]) eacc0 <= {{47{q0[16]}}, q0};
                    if (msk[1]) eacc1 <= {{47{q1[16]}}, q1};
                end else begin
                    if (msk[0]) eacc0 <= eacc0 + {{47{q0[16]}}, q0};
                    if (msk[1]) eacc1 <= eacc1 + {{47{q1[16]}}, q1};
                end
            end
            if (val && fk) begin
                cur_mask <= msk;
                if (!msk[0]) snap0 <= acc0_o;   // pre-edge port value
                if (!msk[1]) snap1 <= acc1_o;
            end
            p0_i        <= q0;
            p1_i        <= q1;
            lane_mask_i <= msk;
            in_valid_i  <= val;
            first_k_i   <= fk;
            last_k_i    <= lk;
        end
    endtask

    // idle beat: garbage inputs, valid=0 (mask = current tile's)
    task automatic idle_beat(input signed [16:0] q0, input signed [16:0] q1);
        begin
            beat(q0, q1, cur_mask, 1'b0, 1'b0, 1'b0);
        end
    endtask

    // n gap cycles, EVERY negedge driven (no stimulus leakage)
    task automatic gapn(input integer n);
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) begin
                @(negedge clk_i);
                idle_beat(-17'sd999, 17'sd777);
            end
        end
    endtask

    // synchronous tile clear; caller lands on a driven negedge (after
    // gapn). Array contract: stop issuing + drain the PE pipeline
    // before asserting clr.
    task automatic do_clr;
        begin
            clr_i      <= 1'b1;
            eacc0      <= 64'sd0;
            eacc1      <= 64'sd0;
            cur_mask   <= 2'b11;
            in_valid_i <= 1'b0;
            first_k_i  <= 1'b0;
            last_k_i   <= 1'b0;
            @(negedge clk_i);
            clr_i <= 1'b0;
        end
    endtask

    // mid-stream reset: clears oracle + orientation like a cold start
    task automatic do_rst(input integer ncyc);
        integer c;
        begin
            rst_i      <= 1'b1;
            eacc0      <= 64'sd0;
            eacc1      <= 64'sd0;
            cur_mask   <= 2'b11;
            in_valid_i <= 1'b0;
            first_k_i  <= 1'b0;
            last_k_i   <= 1'b0;
            for (c = 0; c < ncyc; c = c + 1)
                @(negedge clk_i);
            rst_i <= 1'b0;
        end
    endtask

    // ---- product pools ----
    // realistic: what an INT8xINT8 product can be (|p| <= 16384)
    // stress: any 17-bit value (port width; |sum| stays < 2^31)
    reg signed [16:0] corners [0:7];
    initial begin
        corners[0]= 17'sd16384;  corners[1]=-17'sd16384;
        corners[2]= 17'sd0;      corners[3]= 17'sd1;
        corners[4]=-17'sd1;      corners[5]= 17'sd65535;
        corners[6]=-17'sd65536;  corners[7]= 17'sd32767;
    end

    integer rs1 = 32'd20260919, rs2 = 32'd770219, rs3 = 32'd13571114;
    integer r32;
    reg signed [16:0] q0, q1;

    function signed [16:0] draw_realistic(input integer dummy);
        integer v;
        begin
            r32 = $random(rs1);
            v = r32 % 16385;              // -16384..16384 (signed draw)
            draw_realistic = v[16:0];
        end
    endfunction

    // ---- phase tally probe (debug aid, also documents accounting) ----
    task automatic tally;
        begin
            $display("EES_ACC_TALLY phase=%s started=%0d done=%0d aborted=%0d",
                     phase, tiles_started, tiles_done, tiles_aborted);
        end
    endtask

    // ---- main stimulus ----
    integer i, k, n, kk;
    integer Ks [0:4];
    integer splitA [0:2];
    integer splitB [0:4];
    reg [1:0] msk;
    integer gap;

    initial begin
        Ks[0]=1; Ks[1]=27; Ks[2]=32; Ks[3]=576; Ks[4]=2304;
        splitA[0]=576; splitA[1]=1152; splitA[2]=576;
        splitB[0]=1; splitB[1]=1; splitB[2]=27; splitB[3]=1; splitB[4]=34;

        rst_i       = 1'b1;
        clr_i       = 1'b0;
        in_valid_i  = 1'b0;
        p0_i        = 17'sd0;
        p1_i        = 17'sd0;
        lane_mask_i = 2'b11;
        first_k_i   = 1'b0;
        last_k_i    = 1'b0;

        repeat (10) @(negedge clk_i);
        rst_i <= 1'b0;
        gapn(2);
        chk_en <= 1'b1;                   // arm on a driven idle beat
        @(negedge clk_i);

        // ============ A1: K sweep, contiguous tiles ============
        tally;
        phase = "A1_K_SWEEP";
        for (k = 0; k < 5; k = k + 1) begin
            kk = Ks[k];
            for (i = 0; i < kk; i = i + 1) begin
                @(negedge clk_i);
                beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                     (i == 0), (i == kk-1));
            end
            gapn(3);
        end

        // ============ A2: K-block resume (partial sums held) ============
        tally;
        phase = "A2_RESUME_2304";
        n = 0;
        for (k = 0; k < 3; k = k + 1) begin
            kk = splitA[k];
            for (i = 0; i < kk; i = i + 1) begin
                @(negedge clk_i);
                beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                     (n == 0), (n == 2303));
                n = n + 1;
            end
            if (k < 2)                     // garbage on idle beats
                gapn(5 + 8*k);
        end
        gapn(2);

        tally;
        phase = "A2_RESUME_64_IRREG";
        n = 0;
        for (k = 0; k < 5; k = k + 1) begin
            kk = splitB[k];
            for (i = 0; i < kk; i = i + 1) begin
                @(negedge clk_i);
                beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                     (n == 0), (n == 63));
                n = n + 1;
            end
            if (k < 4) begin
                gap = {$random(rs2)} % 3 + 1;
                gapn(gap);
            end
        end
        gapn(2);

        // ============ A3: clear restart ============
        tally;
        phase = "A3_CLEAR_RESTART";
        for (i = 0; i < 50; i = i + 1) begin
            @(negedge clk_i);
            beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                 (i == 0), 1'b0);          // aborted mid-tile, no last_k
        end
        gapn(1); do_clr;                   // clr AFTER the beats landed
        gapn(3);
        for (i = 0; i < 27; i = i + 1) begin
            @(negedge clk_i);
            beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                 (i == 0), (i == 26));
        end
        gapn(1); do_clr;                   // clr while idle, after done
        @(negedge clk_i);
        beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
             1'b1, 1'b1);                  // K=1 immediately after clr
        gapn(2);

        // A3c: raw clr+valid same-edge priority probe (product killed)
        @(negedge clk_i);
        beat(17'sd4242, -17'sd2424, 2'b11, 1'b1, 1'b1, 1'b0);
        clr_i <= 1'b1;                     // same negedge, valid stays 1
        eacc0 <= 64'sd0; eacc1 <= 64'sd0; cur_mask <= 2'b11;
        @(negedge clk_i);
        clr_i <= 1'b0; in_valid_i <= 1'b0; // clear resolves both now
        first_k_i <= 1'b0; last_k_i <= 1'b0;
        gapn(2);

        // ============ A4: masks + lane re-activation ============
        tally;
        phase = "A4_MASK";
        for (k = 0; k < 3; k = k + 1) begin
            msk = (k == 0) ? 2'b01 : (k == 1) ? 2'b10 : 2'b11;
            for (i = 0; i < 27; i = i + 1) begin
                @(negedge clk_i);
                beat(draw_realistic(0), draw_realistic(0), msk, 1'b1,
                     (i == 0), (i == 26));
            end
            gapn(2);
        end
        // back-to-back re-activation: stale lane re-initialized by first_k
        for (k = 0; k < 3; k = k + 1) begin
            msk = (k == 0) ? 2'b01 : (k == 1) ? 2'b10 : 2'b11;
            for (i = 0; i < 9; i = i + 1) begin
                @(negedge clk_i);
                beat(draw_realistic(0), draw_realistic(0), msk, 1'b1,
                     (i == 0), (i == 8));
            end
            // NO gap: next tile's first_k lands the beat after last_k
        end
        gapn(1);
        // K=1 with a masked lane on the first_k beat
        @(negedge clk_i);
        beat(draw_realistic(0), draw_realistic(0), 2'b01, 1'b1, 1'b1, 1'b1);
        gapn(2);

        // ============ A5: stalls, stale inputs, raw last_k probe ============
        tally;
        phase = "A5_STALL";
        n = 0;
        for (i = 0; i < 576; i = i + 1) begin
            r32 = {$random(rs3)};
            if ((r32 % 4) == 0) begin      // ~25% idle with random inputs
                @(negedge clk_i);
                idle_beat(draw_realistic(0), draw_realistic(0));
            end
            if (n == 300) begin            // raw last_k, in_valid=0: no done
                @(negedge clk_i);
                beat(17'sd55, -17'sd66, 2'b11, 1'b0, 1'b0, 1'b1);
            end
            @(negedge clk_i);
            beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                 (n == 0), (n == 575));
            n = n + 1;
        end
        gapn(2);

        // ============ A6: mid-stream resets ============
        tally;
        phase = "A6_RESET_MID";
        for (i = 0; i < 1000; i = i + 1) begin
            @(negedge clk_i);
            beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                 (i == 0), 1'b0);          // lost mid-tile: no done may fire
        end
        gapn(1); do_rst(2);
        gapn(2);
        for (i = 0; i < 27; i = i + 1) begin
            @(negedge clk_i);
            beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                 (i == 0), (i == 26));
        end
        gapn(2);
        // rst asserted on the LAST beat's edge: reset priority KILLS the
        // last product before accumulation -- tile aborts, done must
        // never fire for it; then state clears and a fresh K=1 runs
        for (i = 0; i < 32; i = i + 1) begin
            @(negedge clk_i);
            beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1,
                 (i == 0), (i == 31));
            if (i == 31) begin
                rst_i      <= 1'b1;        // same negedge as the last beat
                eacc0      <= 64'sd0;
                eacc1      <= 64'sd0;
                cur_mask   <= 2'b11;
                in_valid_i <= 1'b0;
                first_k_i  <= 1'b0;
                last_k_i   <= 1'b0;
            end
        end
        @(negedge clk_i);
        rst_i <= 1'b0;
        gapn(2);
        @(negedge clk_i);
        beat(draw_realistic(0), draw_realistic(0), 2'b11, 1'b1, 1'b1, 1'b1);
        gapn(2);

        // ============ A7: K=1 corners (first_k = last_k) ============
        tally;
        phase = "A7_K1_CORNER";
        for (k = 0; k < 5; k = k + 1) begin
            @(negedge clk_i);
            beat(corners[k], corners[7-k], 2'b11, 1'b1, 1'b1, 1'b1);
            @(negedge clk_i);
            idle_beat(17'sd0, 17'sd0);
        end

        // ============ A8: extreme sums (manual s8 domain pin) ============
        tally;
        phase = "A8_EXTREME_SUM";
        a8_pin_pend = 1;
        for (i = 0; i < 2304; i = i + 1) begin
            @(negedge clk_i);
            beat(17'sd16384, 17'sd16384, 2'b11, 1'b1,
                 (i == 0), (i == 2303));   // -> +37,748,736 (s8 bound)
        end
        gapn(1); do_clr;
        for (i = 0; i < 2304; i = i + 1) begin
            @(negedge clk_i);
            beat(-17'sd16384, -17'sd16384, 2'b11, 1'b1,
                 (i == 0), (i == 2303));   // -> -37,748,736
        end
        gapn(1); do_clr;
        for (i = 0; i < 2304; i = i + 1) begin
            @(negedge clk_i);
            beat(17'sd65535, -17'sd65536, 2'b11, 1'b1,
                 (i == 0), (i == 2303));   // 17-bit port-width stress
        end
        gapn(1); do_clr;
        for (i = 0; i < 2304; i = i + 1) begin
            @(negedge clk_i);
            beat((i[0] ? -17'sd16384 : 17'sd16384),
                 (i[0] ? 17'sd16384 : -17'sd16384), 2'b11, 1'b1,
                 (i == 0), (i == 2303));
        end
        gapn(2);

        // ============ A9: random tiles ============
        tally;
        phase = "A9_RANDOM_TILES";
        for (n = 0; n < 200; n = n + 1) begin
            // unsigned modulo ON the concat (expression context):
            // assigning to signed r32 first would re-sign it -> X index
            kk = Ks[{$random(rs1)} % 5];
            r32 = $random(rs2);            // signed ok: only bits used
            msk = r32[1:0];
            if (msk == 2'b00) msk = 2'b11;
            if ((n & 1) == 0) begin
                gap = 0;                    // back-to-back restart
            end else begin
                gap = {$random(rs3)} % 6;
            end
            if (n > 0 && gap > 0)
                gapn(gap);
            for (i = 0; i < kk; i = i + 1) begin
                r32 = {$random(rs2)};
                if ((r32 % 5) == 0) begin   // ~20% intra-tile idle
                    @(negedge clk_i);
                    idle_beat(draw_realistic(0), draw_realistic(0));
                end
                @(negedge clk_i);
                if ((i & 15) == 0) begin    // corner injection
                    q0 = corners[{$random(rs3)} % 8];
                    q1 = corners[{$random(rs3)} % 8];
                end else begin
                    q0 = draw_realistic(0);
                    q1 = draw_realistic(0);
                end
                beat(q0, q1, msk, 1'b1, (i == 0), (i == kk-1));
            end
        end
        gapn(4);

        // ============ summary ============
        tally;
        phase = "SUMMARY";
        if (tiles_done !== tiles_started - tiles_aborted) begin
            errors = errors + 1;
            $display("EES_ACC_ERR conservation started=%0d done=%0d aborted=%0d",
                     tiles_started, tiles_done, tiles_aborted);
        end
        $display("EES_ACC_INFO tiles started=%0d done=%0d aborted=%0d",
                 tiles_started, tiles_done, tiles_aborted);
        $display("EES_SUMMARY checks=%0d errors=%0d", checks, errors);
        if (errors == 0)
            $display("EES_VIVADO_RESULT PASS");
        else
            $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

    // ---- watchdog: ~165k beats = ~1.7 ms sim; 20 ms margin ----
    initial begin
        #20_000_000;
        $display("EES_SUMMARY checks=%0d errors=WATCHDOG_TIMEOUT", checks);
        $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

endmodule
