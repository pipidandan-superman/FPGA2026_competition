/************************************************************************
 * File Name       : tb_yolo_requant.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_requant
 * Description     : M5 gate testbench for yolo_requant. Replays the
 *                   full requant stimulus (tie constructions, sat rails,
 *                   parameter corners, real-golden regression vectors,
 *                   full-domain random + hold cycles), compares y_pre_o
 *                   against the intarith golden via a pipeline
 *                   scoreboard (V1.1: expected byte queued at the en
 *                   beat, checked at the matching vld_o beat -- order-
 *                   based, latency-agnostic), and checks
 *                   vld_o == en delayed by the pipeline depth.
 *                   V1.2f DUT latency is 6 cycles (prod2_r stage).
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/requant +WDT_MS=400 \
 *                          -do "run -all; quit -f" work.tb_yolo_requant
 *                   Gate token: TB_REQUANT_PASS / TB_REQUANT_FAIL.
 * Dependencies    : rtl/yolo_requant.v, sim/requant_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M5)
 *   - V1.1 (2026-09-16) by LSL : scoreboard compare for the V1.1
 *     5-cycle pipeline (golden vector files unchanged).
 *   - V1.2 (2026-09-17) by LSL : PIPE 5->6 for requant V1.2f (prod2_r
 *     fabric re-register, B0 v24 OOC); scoreboard is order-based so the
 *     golden files are unchanged -- only the en_d shadow chain depth
 *     follows the new latency.
 *   - V1.3 (2026-09-17) by LSL : PIPE 6->7 for requant V1.2g (sum_x_r/
 *     m_x_r operand re-registration, B0 v25 OOC); same order-based
 *     argument, golden files unchanged.
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_requant;

    localparam ACC_W    = 32;
    localparam NCYC_MAX = 32768;    // 向量数上界（实际由 n_cycles.hex 给出）
    localparam PIPE     = 7;        // V1.2g 流水深度（en 拍 -> vld 拍间隔 6 拍）

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg en = 1'b0;
    reg signed [ACC_W-1:0] acc;
    reg signed [ACC_W-1:0] bias;
    reg signed [31:0]      m;
    reg [7:0]              shift;
    wire signed [7:0]      y_pre;
    wire                   vld;

    reg [0:0]         mem_en [0:NCYC_MAX-1];
    reg [31:0]        mem_acc [0:NCYC_MAX-1];
    reg [31:0]        mem_bias [0:NCYC_MAX-1];
    reg [31:0]        mem_m [0:NCYC_MAX-1];
    reg [7:0]         mem_shift [0:NCYC_MAX-1];
    reg [7:0]         mem_yp [0:NCYC_MAX-1];
    integer           n_cyc = 0;
    reg [31:0]        mem_n [0:0];   // $readmemh 载体（向量数字数）

    // scoreboard: expected bytes queued at en beats, popped at vld beats
    reg [7:0]         exp_q [0:NCYC_MAX+PIPE-1];
    integer           qh = 0;
    integer           qt = 0;
    integer           n_exp = 0;     // total queued
    integer           n_cmp = 0;     // total popped/compared

    // vld shadow: en delayed PIPE cycles (posedge-sampled chain);
    // initialised so the pre-reset cycles compare 0 against vld_o=0
    reg [PIPE-1:0]    en_d = {PIPE{1'b0}};

    integer c;
    integer n_err = 0;
    integer n_vld_err = 0;
    integer first_cyc = 0;

    yolo_requant #(
        .ACC_W(ACC_W)
    ) dut (
        .clk_i(clk),
        .rst_n(rst_n),
        .en_i(en),
        .acc_i(acc),
        .bias_i(bias),
        .m_i(m),
        .shift_i(shift),
        .y_pre_o(y_pre),
        .vld_o(vld)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        en_d <= {en_d[PIPE-2:0], en};
    end

    // one scoreboard step: push (if en), pop+compare (if vld), vld check
    task score_step;
        begin
            if (vld) begin
                if (y_pre !== exp_q[qh]) begin
                    n_err = n_err + 1;
                    if (n_err == 1) begin
                        first_cyc = c;
                        $display("[tb] mismatch #%0d y=%0d exp=%0d",
                                 n_err, y_pre, exp_q[qh]);
                    end
                end
                qh = qh + 1;
                n_cmp = n_cmp + 1;
            end
            if (vld !== en_d[PIPE-1]) begin
                n_vld_err = n_vld_err + 1;
            end
        end
    endtask

    reg [1023:0] stim = "../stim/requant";
    integer      wdt_ms = 400;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        $readmemh({stim, "/n_cycles.hex"}, mem_n);
        n_cyc = mem_n[0];
        $display("[tb] requant stim=%0s vectors=%0d pipe=%0d", stim, n_cyc, PIPE);
        $readmemh({stim, "/en.hex"},        mem_en);
        $readmemh({stim, "/acc_i32.hex"},   mem_acc);
        $readmemh({stim, "/bias_i32.hex"},  mem_bias);
        $readmemh({stim, "/m_i32.hex"},     mem_m);
        $readmemh({stim, "/shift_u8.hex"},  mem_shift);
        $readmemh({stim, "/ypre_exp_i8.hex"}, mem_yp);
        // 复位两个周期，此后逐拍驱动（negedge 打入，posedge 采分）
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        for (c = 0; c < n_cyc; c = c + 1) begin
            en    = mem_en[c];
            acc   = mem_acc[c];
            bias  = mem_bias[c];
            m     = mem_m[c];
            shift = mem_shift[c];
            if (en) begin
                exp_q[qt] = mem_yp[c];
                qt = qt + 1;
                n_exp = n_exp + 1;
            end
            @(posedge clk);
            #1;
            score_step;
            @(negedge clk);
        end
        // 排空：末向量出管后再收尾
        for (c = 0; c < PIPE + 1; c = c + 1) begin
            en = 1'b0;
            @(posedge clk);
            #1;
            score_step;
            @(negedge clk);
        end
        if (n_err == 0 && n_vld_err == 0 && n_cmp == n_exp) begin
            $display("TB_REQUANT_PASS compared=%0d vectors (y_pre+vld, pipe=%0d)",
                     n_cmp, PIPE);
        end else begin
            $display("TB_REQUANT_FAIL compared=%0d of %0d errors=%0d vld_errors=%0d first_cyc=%0d",
                     n_cmp, n_exp, n_err, n_vld_err, first_cyc);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_REQUANT_FAIL (timeout)");
        $finish;
    end

endmodule
