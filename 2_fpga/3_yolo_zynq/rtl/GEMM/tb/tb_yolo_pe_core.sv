/************************************************************************
 * File Name       : tb_yolo_pe_core.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_pe_core
 * Description     : Gate TB for the single-PE wrapper (PE manual
 *                   section 10 gate table, single-PE rows).
 *
 *   Checker principle (independent of the DUT formula):
 *     Expected products come from TWO sources, never from the packed
 *     formula: (a) golden_pe.hex written by the run01 software oracle
 *     (directed phases); (b) plain Verilog signed multiply w*x inside
 *     this TB (corner/random/exhaustive phases).
 *
 *   Latency scoreboard (manual section 4 sampling-event language):
 *     A 3-stage expected mirror rides the same edges E0/E1/E2 as the
 *     DUT sideband. Every cycle, out_valid_o must equal exp_v3_r ->
 *     a transaction issued in cycle D is presented exactly in D+3,
 *     no earlier, no later. Idle cycles check out_valid_o == 0.
 *     Each published transaction additionally checks its cycle tag
 *     (cyc - issue_cycle == 3), p0/p1 values and mask transport.
 *
 *   Phases (gate mode):
 *     P1 GOLDEN_CONT   76 directed golden vectors, back-to-back
 *     P2 GOLDEN_GAPPED same vectors, 0..3 idle beats between
 *     P3 CORNER_MESH   10 corner values per axis, 1000 continuous
 *     P4 MASK_SWEEP    all 4 lane masks, continuous and idle beats
 *     P5 RAND_STREAM   200k issues, ~30% idle beats, random masks,
 *                      corner injection every 16th beat
 *     P6 RESET_MIDFILL reset with 2 transactions in flight (one in
 *                      M, one in A/B) -- neither may ever publish
 *     P7 RESET_DRAIN   reset while the only transaction is in M
 *                      (drain interrupted before P)
 *     P8 STALE_GAP     5-cycle idle with frozen inputs mid-stream
 *     Conservation: published == survived-issued (no dup/loss);
 *     killed-by-reset transactions are excluded on BOTH counters.
 *
 *   FULL mode (+FULL_EXH=1): replaces P5 with the full 256^3 w/x0/x1
 *   exhaustive stream (16,777,216 continuous transactions).
 *
 *   Timing conventions:
 *     - inputs driven at negedge (stable well before E0);
 *     - outputs checked at negedge (products are P-register outputs,
 *       stable through the whole presentation cycle);
 *     - checking gated by chk_en (set at first stimulus) and !rst_i;
 *       the reset phases are arranged so no presentation cycle can
 *       fall inside the reset-gated window (conservation stays
 *       exact);
 *     - the unisim DSP48E1 model gates its muxes for the first
 *       100 ns -- reset holds through ~145 ns and the first stimulus
 *       lands at ~245 ns, outside the warm-up window.
 *
 *   EES markers: EES_SUMMARY checks=<published transactions compared>
 *                errors=<failed assertions>
 *                EES_VIVADO_RESULT PASS|FAIL
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release.
 ************************************************************************/

`timescale 1ns / 1ps

module tb_yolo_pe_core;

    // ---- clock: 100 MHz ----
    reg clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    // ---- DUT wiring ----
    reg                rst_i;
    reg                in_valid_i;
    reg  signed [7:0]  w_i, x0_i, x1_i;
    reg  [1:0]         lane_mask_i;
    wire               out_valid_o;
    wire signed [16:0] p0_o, p1_o;
    wire [1:0]         lane_mask_o;

    yolo_pe_core dut (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .in_valid_i  (in_valid_i),
        .w_i         (w_i),
        .x0_i        (x0_i),
        .x1_i        (x1_i),
        .lane_mask_i (lane_mask_i),
        .out_valid_o (out_valid_o),
        .p0_o        (p0_o),
        .p1_o        (p1_o),
        .lane_mask_o (lane_mask_o)
    );

    // ---- bookkeeping ----
    integer checks = 0;      // published transactions fully compared
    integer errors = 0;
    integer iss_cnt = 0;     // issued (posedge-sampled, post-reset only)
    integer pub_exp = 0;     // survived issues (reach mirror stage 3)
    integer pub_cnt = 0;     // actually published and checked
    integer lat_err  = 0;    // cycle-tag violations
    string  phase    = "init";
    reg     chk_en   = 1'b0; // checker armed at first stimulus

    reg full_exh = 1'b0;     // +FULL_EXH=1 -> 256^3 exhaustive stream

    // ---- golden file arrays (76 directed vectors) ----
    localparam NGOLD = 76;
    reg [7:0]  g_w  [0:NGOLD-1];
    reg [7:0]  g_x0 [0:NGOLD-1];
    reg [7:0]  g_x1 [0:NGOLD-1];
    reg [1:0]  g_m  [0:NGOLD-1];
    reg [15:0] g_p0 [0:NGOLD-1];
    reg [15:0] g_p1 [0:NGOLD-1];
    integer    ngold = 0;

    // ---- 3-stage expected mirror (the latency scoreboard) ----
    // issue_*_w are set by the stimulus at negedge for the triple on
    // the wires; the mirror samples them at E0 and shifts them across
    // the same three edges the DUT sideband crosses, so exp_v3_r /
    // exp_p0_3_r / exp_p1_3_r / exp_m3_r must be presented by the DUT
    // during the very same cycle.
    reg signed [16:0] issue_p0_w, issue_p1_w;
    reg signed [16:0] exp_p0_1, exp_p0_2, exp_p0_3;
    reg signed [16:0] exp_p1_1, exp_p1_2, exp_p1_3;
    reg        exp_v1, exp_v2, exp_v3;
    reg  [1:0] exp_m1, exp_m2, exp_m3;
    reg [63:0] exp_c1, exp_c2, exp_c3;   // issue-cycle tags
    reg [63:0] cyc = 0;                  // posedge counter

    always @(posedge clk_i) begin
        if (rst_i) begin
            exp_v1 <= 1'b0; exp_v2 <= 1'b0; exp_v3 <= 1'b0;
            exp_m1 <= 2'b00; exp_m2 <= 2'b00; exp_m3 <= 2'b00;
            exp_c1 <= 64'd0; exp_c2 <= 64'd0; exp_c3 <= 64'd0;
        end else begin
            // E0: the triple on the wires is sampled
            exp_v1   <= in_valid_i;
            exp_p0_1 <= issue_p0_w;
            exp_p1_1 <= issue_p1_w;
            exp_m1   <= lane_mask_i;
            exp_c1   <= cyc;
            if (in_valid_i) iss_cnt <= iss_cnt + 1;
            // E1
            exp_v2   <= exp_v1; exp_p0_2 <= exp_p0_1;
            exp_p1_2 <= exp_p1_1; exp_m2 <= exp_m1; exp_c2 <= exp_c1;
            // E2: presented during the NEXT cycle (D+3 from issue)
            exp_v3   <= exp_v2; exp_p0_3 <= exp_p0_2;
            exp_p1_3 <= exp_p1_2; exp_m3 <= exp_m2; exp_c3 <= exp_c2;
            if (exp_v2) pub_exp <= pub_exp + 1;
            cyc <= cyc + 1;
        end
    end

    // ---- checker: every armed cycle outside reset ----
    always @(negedge clk_i) begin
        if (chk_en && !rst_i) begin
            if (exp_v3 !== out_valid_o) begin
                errors = errors + 1;
                $display("EES_PE_ERR phase=%s cyc=%0d valid_mismatch exp=%b got=%b (latency contract D->D+3)",
                         phase, cyc, exp_v3, out_valid_o);
            end
            if (out_valid_o) begin
                checks = checks + 1;
                pub_cnt = pub_cnt + 1;
                if (p0_o !== exp_p0_3) begin
                    errors = errors + 1;
                    $display("EES_PE_ERR phase=%s cyc=%0d tag_cycle=%0d p0 exp=%0d got=%0d",
                             phase, cyc, exp_c3, exp_p0_3, p0_o);
                end
                if (p1_o !== exp_p1_3) begin
                    errors = errors + 1;
                    $display("EES_PE_ERR phase=%s cyc=%0d tag_cycle=%0d p1 exp=%0d got=%0d",
                             phase, cyc, exp_c3, exp_p1_3, p1_o);
                end
                if (lane_mask_o !== exp_m3) begin
                    errors = errors + 1;
                    $display("EES_PE_ERR phase=%s cyc=%0d tag_cycle=%0d mask exp=%b got=%b",
                             phase, cyc, exp_c3, exp_m3, lane_mask_o);
                end
                if ((cyc - exp_c3) != 64'd3) begin
                    errors = errors + 1; lat_err = lat_err + 1;
                    $display("EES_PE_ERR phase=%s cyc=%0d latency_tag exp_cycle=%0d delta=%0d",
                             phase, cyc, exp_c3, cyc - exp_c3);
                end
            end
        end
    end

    // ---- stimulus helper: drive one beat (call right after negedge).
    //      Expected products are either the golden-file values or the
    //      TB's own independent signed multiply -- never the packed
    //      formula. ----
    task automatic stim(input [7:0] wv, input [7:0] a0v, input [7:0] a1v,
                        input [1:0] msk, input val,
                        input bit use_gold,
                        input signed [16:0] g0, input signed [16:0] g1);
        reg signed [7:0]  ws, xs0, xs1;
        reg signed [16:0] e0, e1;
        begin
            ws  = $signed(wv);
            xs0 = $signed(a0v);
            xs1 = $signed(a1v);
            e0  = use_gold ? g0 : (ws * xs0);   // 17-bit context: exact
            e1  = use_gold ? g1 : (ws * xs1);
            w_i         <= wv;
            x0_i        <= a0v;
            x1_i        <= a1v;
            lane_mask_i <= msk;
            in_valid_i  <= val;
            issue_p0_w  <= e0;
            issue_p1_w  <= e1;
        end
    endtask

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

    // corner pool shared by P3/P5 (includes -128, -127, -1, 0, 1,
    // +127 and mid-range magnitudes)
    reg [7:0] corners [0:9];
    initial begin
        corners[0]=8'h00; corners[1]=8'h01; corners[2]=8'h02;
        corners[3]=8'h3F; corners[4]=8'h7E; corners[5]=8'h7F;
        corners[6]=8'h80; corners[7]=8'h81; corners[8]=8'hFE;
        corners[9]=8'hFF;
    end

    // deterministic random streams (Verilog $random with seed regs)
    integer rs1 = 32'd20260918;
    integer rs2 = 32'd770218;
    integer rs3 = 32'd13571113;

    // ---- golden file load ----
    reg [1023:0] golden_path = "unset";
    initial begin
        if (!$value$plusargs("GOLDEN=%s", golden_path))
            $fatal(1, "EES_PE_FATAL +GOLDEN=<golden_pe.hex path> required");
        load_golden;
    end

    task load_golden;
        integer fd, rc, i;
        reg [7:0] wv, a0v, a1v;
        reg [1:0] mv;
        reg [15:0] e0, e1;
        begin
            fd = $fopen(golden_path, "r");
            if (fd == 0)
                $fatal(1, "EES_PE_FATAL cannot open golden %0s", golden_path);
            void'(skip_line(fd));          // '# w x0 x1 mask p0 p1 ...'
            i = 0;
            while (i < NGOLD) begin
                rc = $fscanf(fd, "%h %h %h %h %h %h",
                             wv, a0v, a1v, mv, e0, e1);
                if (rc != 6) begin
                    $fatal(1, "EES_PE_FATAL golden parse stop at line %0d rc=%0d (expected %0d vectors)",
                           i + 2, rc, NGOLD);
                end
                g_w[i] = wv; g_x0[i] = a0v; g_x1[i] = a1v;
                g_m[i] = mv; g_p0[i] = e0; g_p1[i] = e1;
                i = i + 1;
            end
            ngold = i;
            $fclose(fd);
            $display("EES_PE_INFO golden loaded: %0d vectors from %0s",
                     ngold, golden_path);
        end
    endtask

    // ---- main stimulus ----
    integer i, j, k, n;
    integer idle, r32;
    reg [7:0] wv, a0v, a1v;
    reg [1:0] msk;
    reg [7:0] marker_w = 8'h5A, marker_x0 = 8'h3C, marker_x1 = 8'hA5;

    initial begin
        if ($test$plusargs("FULL_EXH")) full_exh = 1'b1;
        $display("EES_PE_INFO mode=%0s", full_exh ? "FULL_EXH" : "GATE");

        rst_i       = 1'b1;
        in_valid_i  = 1'b0;
        w_i         = 8'sd0;
        x0_i        = 8'sd0;
        x1_i        = 8'sd0;
        lane_mask_i = 2'b11;
        issue_p0_w  = 17'sd0;
        issue_p1_w  = 17'sd0;

        // reset through the unisim 100 ns warm-up window (~145 ns)
        repeat (15) @(negedge clk_i);
        rst_i <= 1'b0;
        repeat (10) @(negedge clk_i);     // first stimulus ~245 ns

        // ================= P1: golden, continuous =================
        phase = "P1_GOLDEN_CONT";
        chk_en = 1'b1;
        for (i = 0; i < ngold; i = i + 1) begin
            @(negedge clk_i);
            stim(g_w[i], g_x0[i], g_x1[i], g_m[i], 1'b1, 1'b1,
                 sext16(g_p0[i]), sext16(g_p1[i]));
        end
        @(negedge clk_i); in_valid_i <= 1'b0;
        repeat (6) @(negedge clk_i);

        // ================= P2: golden, gapped ====================
        phase = "P2_GOLDEN_GAPPED";
        for (i = 0; i < ngold; i = i + 1) begin
            @(negedge clk_i);
            stim(g_w[i], g_x0[i], g_x1[i], g_m[i], 1'b1, 1'b1,
                 sext16(g_p0[i]), sext16(g_p1[i]));
            idle = {$random(rs2)} % 4;       // 0..3 idle beats
            for (j = 0; j < idle; j = j + 1) begin
                @(negedge clk_i);            // data frozen, valid low
                in_valid_i <= 1'b0;
            end
        end
        @(negedge clk_i); in_valid_i <= 1'b0;
        repeat (6) @(negedge clk_i);

        // ================= P3: corner mesh, continuous ============
        phase = "P3_CORNER_MESH";
        for (i = 0; i < 10; i = i + 1)
            for (j = 0; j < 10; j = j + 1)
                for (k = 0; k < 10; k = k + 1) begin
                    @(negedge clk_i);
                    stim(corners[i], corners[j], corners[k],
                         2'b11, 1'b1, 1'b0, 17'sd0, 17'sd0);
                end
        @(negedge clk_i); in_valid_i <= 1'b0;
        repeat (6) @(negedge clk_i);

        // ================= P4: mask sweep =========================
        phase = "P4_MASK_SWEEP";
        for (i = 0; i < 4; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                @(negedge clk_i);
                stim(corners[j+1], corners[j+2], corners[j],
                     i[1:0], 1'b1, 1'b0, 17'sd0, 17'sd0);
                @(negedge clk_i);            // idle beat, mask rides
                stim(corners[9-j], corners[j+1], corners[j+2],
                     i[1:0], 1'b0, 1'b0, 17'sd0, 17'sd0);
            end
        repeat (6) @(negedge clk_i);

        // ================= P5 / FULL: big streams =================
        if (full_exh) begin
            // 256^3 exhaustive: every (w,x0,x1) triple once,
            // continuous stream, independent-multiply expectation
            phase = "FULL_256CUBE";
            for (i = 0; i < 256; i = i + 1) begin
                if ((i % 16) == 0)
                    $display("EES_PE_PROG w_idx=%0d/256 cyc=%0d checks=%0d",
                             i, cyc, checks);
                for (j = 0; j < 256; j = j + 1)
                    for (k = 0; k < 256; k = k + 1) begin
                        @(negedge clk_i);
                        stim(i[7:0], j[7:0], k[7:0], 2'b11, 1'b1,
                             1'b0, 17'sd0, 17'sd0);
                    end
            end
            @(negedge clk_i); in_valid_i <= 1'b0;
            repeat (8) @(negedge clk_i);
        end else begin
            // P5: random stream with gaps and random masks
            phase = "P5_RAND_STREAM";
            for (n = 0; n < 200000; n = n + 1) begin
                @(negedge clk_i);
                r32 = $random(rs1);
                if ((n & 15) == 0) begin     // corner injection
                    wv  = corners[{$random(rs3)} % 10];
                    a0v = corners[{$random(rs3)} % 10];
                    a1v = corners[{$random(rs3)} % 10];
                end else begin
                    wv  = r32[7:0];
                    a0v = r32[15:8];
                    a1v = r32[23:16];
                end
                msk = r32[25:24];
                // ~30% idle beats (fixed running pipeline keeps
                // computing; the valid bit filters them)
                stim(wv, a0v, a1v, msk, (({$random(rs2)} % 10) < 7),
                     1'b0, 17'sd0, 17'sd0);
            end
            @(negedge clk_i); in_valid_i <= 1'b0;
            repeat (6) @(negedge clk_i);
        end

        // ================= P6: reset mid-fill =====================
        // A issued in cycle0 (E0@p1), B issued in cycle1 (E0@p2);
        // reset lands at p3 with A in M and B in A/B -- the clear
        // priority kills both before either can reach stage 3, so
        // NEITHER may ever be published. Phase boundaries are chosen
        // so no presentation cycle falls inside the gated window.
        phase = "P6_RESET_MIDFILL";
        @(negedge clk_i);
        stim(8'h11, 8'h22, 8'h33, 2'b11, 1'b1, 1'b0, 17'sd0, 17'sd0);
        @(negedge clk_i);
        stim(8'h44, 8'h55, 8'h66, 2'b11, 1'b1, 1'b0, 17'sd0, 17'sd0);
        @(negedge clk_i);
        rst_i <= 1'b1; in_valid_i <= 1'b0;
        repeat (2) @(negedge clk_i);
        rst_i <= 1'b0;
        repeat (4) @(negedge clk_i);
        // marker: the first and ONLY thing published after reset
        @(negedge clk_i);
        stim(marker_w, marker_x0, marker_x1, 2'b11, 1'b1, 1'b0,
             17'sd0, 17'sd0);
        @(negedge clk_i); in_valid_i <= 1'b0;
        repeat (6) @(negedge clk_i);

        // ================= P7: reset during drain ================
        // single transaction issued in cycle0 (E0@p1, M@p2); reset
        // sampled at p3 kills it between M and P -- its drain was
        // interrupted, nothing may publish.
        phase = "P7_RESET_DRAIN";
        @(negedge clk_i);
        stim(8'hC3, 8'h3C, 8'h5A, 2'b01, 1'b1, 1'b0, 17'sd0, 17'sd0);
        @(negedge clk_i); in_valid_i <= 1'b0;
        @(negedge clk_i);
        rst_i <= 1'b1;
        repeat (2) @(negedge clk_i);
        rst_i <= 1'b0;
        repeat (4) @(negedge clk_i);
        @(negedge clk_i);
        stim(marker_w, marker_x0, marker_x1, 2'b10, 1'b1, 1'b0,
             17'sd0, 17'sd0);
        @(negedge clk_i); in_valid_i <= 1'b0;
        repeat (6) @(negedge clk_i);

        // ================= P8: stale-input idle gap ==============
        phase = "P8_STALE_GAP";
        @(negedge clk_i);
        stim(8'h69, 8'h96, 8'h4B, 2'b11, 1'b1, 1'b0, 17'sd0, 17'sd0);
        repeat (5) @(negedge clk_i); in_valid_i <= 1'b0; // frozen data
        @(negedge clk_i);
        stim(8'h96, 8'h4B, 8'h69, 2'b11, 1'b1, 1'b0, 17'sd0, 17'sd0);
        @(negedge clk_i); in_valid_i <= 1'b0;
        repeat (8) @(negedge clk_i);

        // ================= summary ===============================
        phase = "SUMMARY";
        if (pub_cnt !== pub_exp) begin
            errors = errors + 1;
            $display("EES_PE_ERR conservation pub_cnt=%0d pub_exp=%0d iss_cnt=%0d",
                     pub_cnt, pub_exp, iss_cnt);
        end
        if (checks != pub_cnt) begin
            errors = errors + 1;
            $display("EES_PE_ERR checks=%0d pub_cnt=%0d", checks, pub_cnt);
        end
        $display("EES_PE_INFO mode=%0s issued=%0d published=%0d checks=%0d lat_err=%0d",
                 full_exh ? "FULL_EXH" : "GATE", iss_cnt, pub_cnt,
                 checks, lat_err);
        $display("EES_SUMMARY checks=%0d errors=%0d", checks, errors);
        if (errors == 0)
            $display("EES_VIVADO_RESULT PASS");
        else
            $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

    // ---- watchdog: gate mode finishes in <3 ms sim; FULL streams
    //      16,777,216 beats at 10 ns = ~168 ms, margin to 600 ms ----
    initial begin
        if ($test$plusargs("FULL_EXH"))
            #600_000_000;
        else
            #50_000_000;
        $display("EES_SUMMARY checks=%0d errors=WATCHDOG_TIMEOUT", checks);
        $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

endmodule
