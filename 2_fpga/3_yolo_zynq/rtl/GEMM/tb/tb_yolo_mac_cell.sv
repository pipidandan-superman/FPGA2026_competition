/************************************************************************
 * File Name       : tb_yolo_mac_cell.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_mac_cell
 * Description     : Level-2 joint gate TB: real DSP48E1 PE feeding the
 *                   real dual INT32 accumulator through the E3
 *                   presentation (PE manual section 1: this pair IS
 *                   the MAC). Unique fault attribution: step 1 and
 *                   step 2 are separately gated, so any failure here
 *                   is a COMPOSITION/ALIGNMENT failure -- sideband
 *                   riding, E3 sampling, done timing D+4, back-to-back
 *                   tiles, in-flight reset kills.
 *
 *   Oracle principle (GEMM manual section 14, independent end to end):
 *     products come from the TB's own signed multiply (never the DSP,
 *     never the packed formula), accumulation from the TB's own INT64
 *     adds. A pass requires acc === sext64(INT64 oracle) bit-for-bit.
 *     M0 additionally cross-checks the TB multiply against the run01
 *     golden_pe.hex values once per beat (ties the level-2 chain back
 *     to the software oracle without relying on it).
 *
 *   Latency scoreboard (extends the step-1 3-stage mirror by the
 *   accumulator sampling edge):
 *     issue cycle D (tagged) -> products+sideband presented D+3
 *     -> acc samples at the E3 edge -> acc/done visible during D+4.
 *     Every done pulse must carry cyc - tag == 4 (hard lat_err).
 *
 *   Check discipline (every armed negedge, single blocking process):
 *     - active lanes: acc_o === sext64(dut_eacc)
 *     - masked lanes: acc_o === snapshot taken at the tile's E3
 *       first_k edge (structural mask never touches state)
 *     - acc_done_o === exp4_done exactly, every cycle
 *     - conservation: done === started - aborted (K=1 tile: start
 *       and done set at the same E3 edge, nothing stays active)
 *
 *   Drive discipline (inherited, enforced):
 *     EVERY negedge drives inputs (gapn); $random modulo computed on
 *     the UNSIGNED concat in expression context ({expr} % N, never via
 *     a signed integer variable); beat() X-tripwire makes vacuous 4-
 *     state passes loud; clr only after the pipeline has drained
 *     (>= 4 idle beats -- the array contract this level must obey).
 *
 *   Phases:
 *     M0 GOLDEN_CONT    76 golden vectors, one K=76 tile (operands
 *                       from run01 golden_pe.hex; mask forced 11 --
 *                       the MAC mask contract is tile-constant)
 *     M1 K_SWEEP        K=1/27/32/576/2304 random int8
 *     M2 BACKTOBACK     6 tiles, zero gap (next first_k the beat
 *                       right after the previous last_k)
 *     M3 RESUME         K=2304 as [576,1152,576] and K=64 as
 *                       [1,1,27,1,34] with idle gaps between blocks
 *     M4 MASK           masks 01/10/11, back-to-back re-activation,
 *                       K=1 with a masked lane
 *     M5 STALL          25% idle beats, raw last_k with valid=0
 *     M6 RESET_MID      rst mid-K=1000 (in-flight products die, no
 *                       done); rst on the last issue beat (reset
 *                       priority kills it in flight); fresh tiles
 *     M7 CLEAR_RESTART  drained clr mid-tile -> zeros -> fresh
 *                       tiles; clr while idle right after a done;
 *                       K=1 immediately after clr
 *     M8 K1_CORNER      int8 corner products, first_k=last_k
 *     M9 EXTREME_SUM    -128*-128 K=2304 -> +37,748,736 literal
 *                       (manual section 8 bound, now through the real
 *                       DSP path); 127*-128 -> -37,453,824 (int8
 *                       domain negative extreme); alternating signs
 *     M10 RANDOM_TILES  200 tiles, random K/mask/gaps/idles/corners,
 *                       half back-to-back restarts
 *
 *   EES markers: EES_SUMMARY checks=<n> errors=<n> lat_err=<n>
 *                EES_VIVADO_RESULT PASS|FAIL
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release (level-2 joint).
 ************************************************************************/

`timescale 1ns / 1ps

module tb_yolo_mac_cell;

    // ---- clock: 100 MHz ----
    reg clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    // ---- DUT wiring ----
    reg                rst_i;
    reg                clr_i;
    reg                in_valid_i;
    reg  signed [7:0]  w_i, x0_i, x1_i;
    reg  [1:0]         lane_mask_i;
    reg                first_k_i, last_k_i;
    wire signed [31:0] acc0_o, acc1_o;
    wire               acc_done_o;

    yolo_mac_cell dut (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .clr_i       (clr_i),
        .in_valid_i  (in_valid_i),
        .w_i         (w_i),
        .x0_i        (x0_i),
        .x1_i        (x1_i),
        .lane_mask_i (lane_mask_i),
        .first_k_i   (first_k_i),
        .last_k_i    (last_k_i),
        .acc0_o      (acc0_o),
        .acc1_o      (acc1_o),
        .acc_done_o  (acc_done_o)
    );

    // ---- bookkeeping ----
    integer checks = 0;      // negedge invariants executed
    integer errors = 0;
    integer tiles_started = 0, tiles_done = 0, tiles_aborted = 0;
    reg     active_tile = 1'b0;
    string  phase = "init";
    reg     chk_en = 1'b0;
    integer lat_err = 0;
    integer m9_pin_pend = 0;  // M9 +37,748,736 literal pin

    // ---- independent INT64 oracle + tile orientation ----
    reg signed [63:0] dut_eacc0 = 64'sd0, dut_eacc1 = 64'sd0;
    reg [1:0]  cur_mask = 2'b11;
    reg [31:0] snap0 = 32'd0, snap1 = 32'd0;

    // ---- TB independent products (set by stimulus at negedge,
    //      sampled by the mirror at E0) ----
    reg signed [16:0] issue_p0_w, issue_p1_w;

    // ---- expected mirror: 3 product stages + the E3 sampling edge --
    // stages 1..3 replicate the PE sideband pipeline; stage 4 is the
    // accumulator's sampling edge, where the INT64 oracle commits.
    reg signed [16:0] exp_p0_1, exp_p0_2, exp_p0_3;
    reg signed [16:0] exp_p1_1, exp_p1_2, exp_p1_3;
    reg        exp_v1, exp_v2, exp_v3;
    reg  [1:0] exp_m1, exp_m2, exp_m3;
    reg        exp_fk1, exp_fk2, exp_fk3;
    reg        exp_lk1, exp_lk2, exp_lk3;
    reg        exp4_done, exp4_start;
    reg [63:0] exp_c1, exp_c2, exp_c3, exp_c4;   // issue-cycle tags
    reg [63:0] cyc = 0;                          // posedge counter

    always @(posedge clk_i) begin
        if (rst_i) begin
            // reset priority kills EVERYTHING in flight (PE valids,
            // tags, accumulator) -- one edge, whole chain
            exp_v1 <= 1'b0; exp_v2 <= 1'b0; exp_v3 <= 1'b0;
            exp_m1 <= 2'b00; exp_m2 <= 2'b00; exp_m3 <= 2'b00;
            exp_fk1 <= 1'b0; exp_fk2 <= 1'b0; exp_fk3 <= 1'b0;
            exp_lk1 <= 1'b0; exp_lk2 <= 1'b0; exp_lk3 <= 1'b0;
            exp4_done <= 1'b0; exp4_start <= 1'b0;
            dut_eacc0 <= 64'sd0; dut_eacc1 <= 64'sd0;
            cur_mask <= 2'b11;
        end else begin
            // E0: the triple on the wires is sampled
            exp_v1   <= in_valid_i;
            exp_p0_1 <= issue_p0_w;
            exp_p1_1 <= issue_p1_w;
            exp_m1   <= lane_mask_i;
            exp_fk1  <= first_k_i;
            exp_lk1  <= last_k_i;
            exp_c1   <= cyc;
            // E1 / E2
            exp_v2   <= exp_v1;  exp_p0_2 <= exp_p0_1;  exp_p1_2 <= exp_p1_1;
            exp_m2   <= exp_m1;  exp_fk2  <= exp_fk1;   exp_lk2  <= exp_lk1;
            exp_c2   <= exp_c1;
            exp_v3   <= exp_v2;  exp_p0_3 <= exp_p0_2;  exp_p1_3 <= exp_p1_2;
            exp_m3   <= exp_m2;  exp_fk3  <= exp_fk2;   exp_lk3  <= exp_lk2;
            exp_c3   <= exp_c2;
            // E3: the accumulator samples the presentation
            if (clr_i) begin
                // array contract: clr only with the pipeline drained
                dut_eacc0 <= 64'sd0;
                dut_eacc1 <= 64'sd0;
                exp4_done <= 1'b0;
                exp4_start <= 1'b0;
                cur_mask  <= 2'b11;
                if (exp_v3 || exp_v2 || exp_v1) begin
                    errors = errors + 1;
                    $display("EES_MAC_ERR phase=%s clr with pipeline in flight (array contract)",
                             phase);
                end
            end else begin
                exp4_done  <= exp_v3 & exp_lk3;
                exp4_start <= exp_v3 & exp_fk3;
                if (exp_v3) begin
                    if (exp_m3[0])
                        dut_eacc0 <= exp_fk3 ? {{47{exp_p0_3[16]}}, exp_p0_3}
                                             : dut_eacc0 + {{47{exp_p0_3[16]}}, exp_p0_3};
                    if (exp_m3[1])
                        dut_eacc1 <= exp_fk3 ? {{47{exp_p1_3[16]}}, exp_p1_3}
                                             : dut_eacc1 + {{47{exp_p1_3[16]}}, exp_p1_3};
                end
                if (exp_v3 & exp_fk3) begin
                    cur_mask <= exp_m3;
                    if (!exp_m3[0]) snap0 <= acc0_o;  // pre-edge port value
                    if (!exp_m3[1]) snap1 <= acc1_o;
                end
                exp_c4 <= exp_c3;
            end
            cyc <= cyc + 1;
        end
    end

    // ---- checker: one process, blocking, every armed negedge ----
    always @(negedge clk_i) begin
        if (chk_en) begin
            checks = checks + 1;
            if (rst_i || clr_i) begin
                // the posedge just before this negedge cleared state
                if (exp4_done) begin
                    tiles_done = tiles_done + 1;
                    active_tile = 1'b0;
                end else if (active_tile) begin
                    tiles_aborted = tiles_aborted + 1;
                    active_tile = 1'b0;
                end
                if (({{32{acc0_o[31]}}, acc0_o} !== dut_eacc0) ||
                    ({{32{acc1_o[31]}}, acc1_o} !== dut_eacc1)) begin
                    errors = errors + 1;
                    $display("EES_MAC_ERR phase=%s cleared-state acc0=%0d acc1=%0d exp=%0d/%0d",
                             phase, acc0_o, acc1_o, dut_eacc0, dut_eacc1);
                end
            end else begin
                // value invariants every cycle (active lanes vs INT64)
                if (cur_mask[0] && ({{32{acc0_o[31]}}, acc0_o} !== dut_eacc0)) begin
                    errors = errors + 1;
                    $display("EES_MAC_ERR phase=%s cyc=%0d lane0 acc=%0d exp64=%0d",
                             phase, cyc, acc0_o, dut_eacc0);
                end
                if (cur_mask[1] && ({{32{acc1_o[31]}}, acc1_o} !== dut_eacc1)) begin
                    errors = errors + 1;
                    $display("EES_MAC_ERR phase=%s cyc=%0d lane1 acc=%0d exp64=%0d",
                             phase, cyc, acc1_o, dut_eacc1);
                end
                // masked lanes: frozen since this tile's E3 first_k
                if (!cur_mask[0] && (acc0_o !== snap0)) begin
                    errors = errors + 1;
                    $display("EES_MAC_ERR phase=%s masked lane0 moved: %0d -> %0d",
                             phase, snap0, acc0_o);
                end
                if (!cur_mask[1] && (acc1_o !== snap1)) begin
                    errors = errors + 1;
                    $display("EES_MAC_ERR phase=%s masked lane1 moved: %0d -> %0d",
                             phase, snap1, acc1_o);
                end
                // done pulse exactness
                if (acc_done_o !== exp4_done) begin
                    errors = errors + 1;
                    $display("EES_MAC_ERR phase=%s cyc=%0d done=%b exp=%b",
                             phase, cyc, acc_done_o, exp4_done);
                end
                // latency contract: issue D -> acc/done visible D+4
                if (exp4_done && ((cyc - exp_c4) != 64'd4)) begin
                    errors = errors + 1;
                    lat_err = lat_err + 1;
                    $display("EES_MAC_ERR phase=%s cyc=%0d latency issue_cyc=%0d delta=%0d want 4",
                             phase, cyc, exp_c4, cyc - exp_c4);
                end
                if (exp4_done) begin
                    tiles_done = tiles_done + 1;
                    if (m9_pin_pend == 1) begin
                        m9_pin_pend = 0;
                        if (acc0_o !== 32'sd37748736) begin
                            errors = errors + 1;
                            $display("EES_MAC_ERR M9 manual-bound pin acc0=%0d want 37748736",
                                     acc0_o);
                        end else
                            $display("EES_MAC_INFO M9 manual s8 bound pinned (real DSP path): %0d",
                                     acc0_o);
                    end
                end
                if (exp4_start)
                    tiles_started = tiles_started + 1;
                // a K=1 tile (fk=lk same beat) completes at the same
                // E3 edge -- nothing stays active afterwards
                if (exp4_start && !exp4_done)
                    active_tile = 1'b1;
                else if (exp4_done)
                    active_tile = 1'b0;
            end
        end
    end

    // ---- stimulus: one int8 triple beat at negedge ----
    task automatic beat8(input [7:0] wv, input [7:0] a0v, input [7:0] a1v,
                        input [1:0] msk, input val,
                        input fk, input lk);
        reg signed [7:0]  ws, xs0, xs1;
        begin
            // X-tripwire: vacuous 4-state passes must be loud
            if ((^wv === 1'bx) || (^a0v === 1'bx) || (^a1v === 1'bx)) begin
                errors = errors + 1;
                $display("EES_MAC_ERR phase=%s X operand in stimulus w=%b x0=%b x1=%b",
                         phase, wv, a0v, a1v);
            end
            ws  = $signed(wv);
            xs0 = $signed(a0v);
            xs1 = $signed(a1v);
            issue_p0_w = ws * xs0;      // TB independent multiply
            issue_p1_w = ws * xs1;
            w_i         <= wv;
            x0_i        <= a0v;
            x1_i        <= a1v;
            lane_mask_i <= msk;
            in_valid_i  <= val;
            first_k_i   <= fk;
            last_k_i    <= lk;
        end
    endtask

    // idle beat: garbage operands, valid=0 (DSP keeps running)
    task automatic idle_beat8(input [7:0] wv, input [7:0] a0v, input [7:0] a1v);
        begin
            beat8(wv, a0v, a1v, 2'b11, 1'b0, 1'b0, 1'b0);
        end
    endtask

    // n gap cycles, EVERY negedge driven
    task automatic gapn(input integer n);
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) begin
                @(negedge clk_i);
                idle_beat8(8'h00, 8'h5A, 8'hA5);
            end
        end
    endtask

    // tile clear -- array contract: pipeline drained first (caller
    // does gapn(>=4)); acc side only, PE pipeline unaffected
    task automatic do_clr;
        begin
            clr_i      <= 1'b1;
            in_valid_i <= 1'b0;
            first_k_i  <= 1'b0;
            last_k_i   <= 1'b0;
            @(negedge clk_i);
            clr_i <= 1'b0;
        end
    endtask

    // mid-stream reset: kills PE valids + tag pipeline + accumulator
    task automatic do_rst(input integer ncyc);
        integer c;
        begin
            rst_i      <= 1'b1;
            in_valid_i <= 1'b0;
            first_k_i  <= 1'b0;
            last_k_i   <= 1'b0;
            for (c = 0; c < ncyc; c = c + 1)
                @(negedge clk_i);
            rst_i <= 1'b0;
        end
    endtask

    // ---- int8 operand pools ----
    reg [7:0] corners8 [0:7];
    initial begin
        corners8[0] = -8'sd128; corners8[1] = -8'sd1;
        corners8[2] =  8'sd0;   corners8[3] =  8'sd1;
        corners8[4] =  8'sd127; corners8[5] = -8'sd127;
        corners8[6] =  8'sd64;  corners8[7] = -8'sd64;
    end

    integer rs1 = 32'd20260920, rs2 = 32'd770220, rs3 = 32'd13571113;
    integer r32;

    function [7:0] draw8(input integer dummy);
        integer v;
        begin
            r32 = $random(rs1);
            v = r32 % 256;               // signed draw ok: bits taken
            draw8 = v[7:0];
        end
    endfunction

    // ---- golden file (76 directed vectors, run01) ----
    localparam NGOLD = 76;
    reg [7:0]  g_w  [0:NGOLD-1];
    reg [7:0]  g_x0 [0:NGOLD-1];
    reg [7:0]  g_x1 [0:NGOLD-1];
    reg [1:0]  g_m  [0:NGOLD-1];
    reg [15:0] g_p0 [0:NGOLD-1];
    reg [15:0] g_p1 [0:NGOLD-1];

    // sign-extend a 16-bit golden field to the 17-bit compare width
    function [16:0] sext16(input [15:0] v);
        sext16 = {v[15], v};
    endfunction

    // consume one line of the golden file (the comment header)
    function integer skip_line(input integer fd);
        reg [1023:0] line;
        begin
            skip_line = $fgets(line, fd);
        end
    endfunction

    // ---- phase tally probe ----
    task automatic tally;
        begin
            $display("EES_MAC_TALLY phase=%s started=%0d done=%0d aborted=%0d",
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
    integer fd, rc;
    reg [7:0]  wv, a0v, a1v;
    reg [1:0]  mv;
    reg [15:0] e0, e1;
    string   golden_path;

    initial begin
        Ks[0]=1; Ks[1]=27; Ks[2]=32; Ks[3]=576; Ks[4]=2304;
        splitA[0]=576; splitA[1]=1152; splitA[2]=576;
        splitB[0]=1; splitB[1]=1; splitB[2]=27; splitB[3]=1; splitB[4]=34;

        if (!$value$plusargs("GOLDEN=%s", golden_path))
            $fatal(1, "EES_MAC_FATAL +GOLDEN=<golden_pe.hex path> required");
        fd = $fopen(golden_path, "r");
        if (fd == 0)
            $fatal(1, "EES_MAC_FATAL cannot open %s", golden_path);
        void'(skip_line(fd));               // '# w x0 x1 mask p0 p1 ...'
        for (n = 0; n < NGOLD; n = n + 1) begin
            rc = $fscanf(fd, "%h %h %h %h %h %h", wv, a0v, a1v, mv, e0, e1);
            if (rc != 6)
                $fatal(1, "EES_MAC_FATAL golden parse stop at line %0d rc=%0d",
                       n + 2, rc);
            g_w[n] = wv; g_x0[n] = a0v; g_x1[n] = a1v;
            g_m[n] = mv; g_p0[n] = e0; g_p1[n] = e1;
        end
        $fclose(fd);
        $display("EES_MAC_INFO golden loaded: %0d vectors", NGOLD);

        rst_i       = 1'b1;
        clr_i       = 1'b0;
        in_valid_i  = 1'b0;
        w_i         = 8'sd0;
        x0_i        = 8'sd0;
        x1_i        = 8'sd0;
        lane_mask_i = 2'b11;
        first_k_i   = 1'b0;
        last_k_i    = 1'b0;

        repeat (10) @(negedge clk_i);
        rst_i <= 1'b0;
        gapn(2);
        chk_en <= 1'b1;
        @(negedge clk_i);

        // ============ M0: golden continuous tile ============
        tally;
        phase = "M0_GOLDEN_CONT";
        for (i = 0; i < NGOLD; i = i + 1) begin
            @(negedge clk_i);
            beat8(g_w[i], g_x0[i], g_x1[i], 2'b11, 1'b1,
                  (i == 0), (i == NGOLD-1));
            // one-shot cross-check: TB multiply == run01 golden product
            if (issue_p0_w !== sext16(g_p0[i])) begin
                errors = errors + 1;
                $display("EES_MAC_ERR M0 golden p0 mismatch i=%0d tb=%0d gold=%0d",
                         i, issue_p0_w, $signed(g_p0[i]));
            end
            if (issue_p1_w !== sext16(g_p1[i])) begin
                errors = errors + 1;
                $display("EES_MAC_ERR M0 golden p1 mismatch i=%0d tb=%0d gold=%0d",
                         i, issue_p1_w, $signed(g_p1[i]));
            end
        end
        gapn(4);

        // ============ M1: K sweep, contiguous tiles ============
        tally;
        phase = "M1_K_SWEEP";
        for (k = 0; k < 5; k = k + 1) begin
            kk = Ks[k];
            for (i = 0; i < kk; i = i + 1) begin
                @(negedge clk_i);
                beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                      (i == 0), (i == kk-1));
            end
            gapn(3);
        end

        // ============ M2: back-to-back tiles, zero gap ============
        tally;
        phase = "M2_BACKTOBACK";
        for (n = 0; n < 6; n = n + 1) begin
            kk = Ks[1 + (n % 3)];            // 27/32/576 mix
            for (i = 0; i < kk; i = i + 1) begin
                @(negedge clk_i);
                beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                      (i == 0), (i == kk-1));
            end
            // NO gap: next first_k lands the beat after last_k
        end
        gapn(3);

        // ============ M3: K-block resume ============
        tally;
        phase = "M3_RESUME_2304";
        n = 0;
        for (k = 0; k < 3; k = k + 1) begin
            kk = splitA[k];
            for (i = 0; i < kk; i = i + 1) begin
                @(negedge clk_i);
                beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                      (n == 0), (n == 2303));
                n = n + 1;
            end
            if (k < 2)
                gapn(5 + 8*k);
        end
        gapn(2);

        phase = "M3_RESUME_64_IRREG";
        n = 0;
        for (k = 0; k < 5; k = k + 1) begin
            kk = splitB[k];
            for (i = 0; i < kk; i = i + 1) begin
                @(negedge clk_i);
                beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                      (n == 0), (n == 63));
                n = n + 1;
            end
            if (k < 4) begin
                gap = {$random(rs2)} % 3 + 1;
                gapn(gap);
            end
        end
        gapn(2);

        // ============ M4: masks + lane re-activation ============
        tally;
        phase = "M4_MASK";
        for (k = 0; k < 3; k = k + 1) begin
            msk = (k == 0) ? 2'b01 : (k == 1) ? 2'b10 : 2'b11;
            for (i = 0; i < 27; i = i + 1) begin
                @(negedge clk_i);
                beat8(draw8(0), draw8(0), draw8(0), msk, 1'b1,
                      (i == 0), (i == 26));
            end
            gapn(2);
        end
        for (k = 0; k < 3; k = k + 1) begin
            msk = (k == 0) ? 2'b01 : (k == 1) ? 2'b10 : 2'b11;
            for (i = 0; i < 9; i = i + 1) begin
                @(negedge clk_i);
                beat8(draw8(0), draw8(0), draw8(0), msk, 1'b1,
                      (i == 0), (i == 8));
            end
            // NO gap: stale lane re-initialized by next first_k
        end
        gapn(1);
        @(negedge clk_i);
        beat8(draw8(0), draw8(0), draw8(0), 2'b01, 1'b1, 1'b1, 1'b1);
        gapn(2);

        // ============ M5: stalls + raw last_k probe ============
        tally;
        phase = "M5_STALL";
        n = 0;
        for (i = 0; i < 576; i = i + 1) begin
            r32 = {$random(rs3)};
            if ((r32 % 4) == 0) begin        // ~25% idle, random operands
                @(negedge clk_i);
                idle_beat8(draw8(0), draw8(0), draw8(0));
            end
            if (n == 300) begin              // raw last_k, valid=0: no done
                @(negedge clk_i);
                beat8(8'h55, 8'h66, 8'h77, 2'b11, 1'b0, 1'b0, 1'b1);
            end
            @(negedge clk_i);
            beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                  (n == 0), (n == 575));
            n = n + 1;
        end
        gapn(3);

        // ============ M6: mid-stream resets ============
        tally;
        phase = "M6_RESET_MID";
        for (i = 0; i < 1000; i = i + 1) begin
            @(negedge clk_i);
            beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                  (i == 0), 1'b0);           // lost mid-tile: no done
        end
        gapn(1); do_rst(2);
        gapn(2);
        for (i = 0; i < 27; i = i + 1) begin
            @(negedge clk_i);
            beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                  (i == 0), (i == 26));
        end
        gapn(2);
        // rst asserted on the LAST issue beat's edge: reset priority
        // kills the last product (and the 2 beats in flight behind
        // it) before any reaches the accumulator -- tile aborts
        for (i = 0; i < 32; i = i + 1) begin
            @(negedge clk_i);
            beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                  (i == 0), (i == 31));
            if (i == 31) begin
                rst_i      <= 1'b1;         // same negedge as last beat
                in_valid_i <= 1'b0;
                first_k_i  <= 1'b0;
                last_k_i   <= 1'b0;
            end
        end
        @(negedge clk_i);
        rst_i <= 1'b0;
        gapn(2);
        @(negedge clk_i);
        beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1, 1'b1, 1'b1);
        gapn(2);

        // ============ M7: clear restart (drained) ============
        tally;
        phase = "M7_CLEAR_RESTART";
        for (i = 0; i < 50; i = i + 1) begin
            @(negedge clk_i);
            beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                  (i == 0), 1'b0);           // aborted mid-tile
        end
        gapn(4); do_clr;                     // drain 3 + margin, then clr
        gapn(3);
        for (i = 0; i < 27; i = i + 1) begin
            @(negedge clk_i);
            beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1,
                  (i == 0), (i == 26));
        end
        gapn(4); do_clr;                     // clr while idle, after done
        @(negedge clk_i);
        beat8(draw8(0), draw8(0), draw8(0), 2'b11, 1'b1, 1'b1, 1'b1);
        gapn(2);

        // ============ M8: K=1 int8 corners ============
        tally;
        phase = "M8_K1_CORNER";
        for (k = 0; k < 8; k = k + 1) begin
            @(negedge clk_i);
            beat8(corners8[k], corners8[7-k], corners8[(k+3)%8],
                  2'b11, 1'b1, 1'b1, 1'b1);
            gapn(1);
        end
        gapn(4);                             // drain the last K=1 dones:
                                             // pin flag must not catch them

        // ============ M9: extreme sums (manual s8 domain pins) ============
        tally;
        phase = "M9_EXTREME_SUM";
        m9_pin_pend = 1;
        for (i = 0; i < 2304; i = i + 1) begin
            @(negedge clk_i);
            beat8(-8'sd128, -8'sd128, -8'sd128, 2'b11, 1'b1,
                  (i == 0), (i == 2303));    // 16384*2304 = +37,748,736
        end
        gapn(4); do_clr;
        for (i = 0; i < 2304; i = i + 1) begin
            @(negedge clk_i);
            beat8(8'sd127, -8'sd128, -8'sd128, 2'b11, 1'b1,
                  (i == 0), (i == 2303));    // -16256*2304 = -37,453,824
        end
        gapn(4); do_clr;
        for (i = 0; i < 2304; i = i + 1) begin
            @(negedge clk_i);
            beat8((i[0] ? 8'sd127 : -8'sd128),
                  (i[0] ? -8'sd128 : 8'sd127),
                  (i[0] ? 8'sd127 : -8'sd128), 2'b11, 1'b1,
                  (i == 0), (i == 2303));    // alternating-sign cancellation
        end
        gapn(2);

        // ============ M10: random tiles ============
        tally;
        phase = "M10_RANDOM_TILES";
        for (n = 0; n < 200; n = n + 1) begin
            kk = Ks[{$random(rs1)} % 5];     // unsigned modulo ON the concat
            r32 = $random(rs2);              // signed ok: only bits used
            msk = r32[1:0];
            if (msk == 2'b00) msk = 2'b11;
            if ((n & 1) == 0) begin
                gap = 0;                     // back-to-back restart
            end else begin
                gap = {$random(rs3)} % 6;
            end
            if (n > 0 && gap > 0)
                gapn(gap);
            for (i = 0; i < kk; i = i + 1) begin
                r32 = {$random(rs2)};
                if ((r32 % 5) == 0) begin    // ~20% intra-tile idle
                    @(negedge clk_i);
                    idle_beat8(draw8(0), draw8(0), draw8(0));
                end
                @(negedge clk_i);
                if ((i & 15) == 0) begin     // corner injection
                    beat8(corners8[{$random(rs3)} % 8],
                          corners8[{$random(rs3)} % 8],
                          corners8[{$random(rs3)} % 8],
                          msk, 1'b1, (i == 0), (i == kk-1));
                end else begin
                    beat8(draw8(0), draw8(0), draw8(0), msk, 1'b1,
                          (i == 0), (i == kk-1));
                end
            end
        end
        gapn(6);

        // ============ summary ============
        tally;
        phase = "SUMMARY";
        if (tiles_done !== tiles_started - tiles_aborted) begin
            errors = errors + 1;
            $display("EES_MAC_ERR conservation started=%0d done=%0d aborted=%0d",
                     tiles_started, tiles_done, tiles_aborted);
        end
        $display("EES_MAC_INFO tiles started=%0d done=%0d aborted=%0d",
                 tiles_started, tiles_done, tiles_aborted);
        $display("EES_SUMMARY checks=%0d errors=%0d lat_err=%0d",
                 checks, errors, lat_err);
        if (errors == 0)
            $display("EES_VIVADO_RESULT PASS");
        else
            $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

    // ---- watchdog: ~150k beats = ~1.5 ms sim; 20 ms margin ----
    initial begin
        #20_000_000;
        $display("EES_SUMMARY checks=%0d errors=WATCHDOG_TIMEOUT", checks);
        $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

endmodule
