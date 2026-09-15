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
 *                   against the intarith golden every vector and checks
 *                   vld_o == en (registered).
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/requant +WDT_MS=400 \
 *                          -do "run -all; quit -f" work.tb_yolo_requant
 *                   Gate token: TB_REQUANT_PASS / TB_REQUANT_FAIL.
 * Dependencies    : rtl/yolo_requant.v, sim/requant_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M5)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_requant;

    localparam ACC_W    = 32;
    localparam NCYC_MAX = 32768;    // 向量数上界（实际由 n_cycles.hex 给出）

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
        $display("[tb] requant stim=%0s vectors=%0d", stim, n_cyc);
        $readmemh({stim, "/en.hex"},        mem_en);
        $readmemh({stim, "/acc_i32.hex"},   mem_acc);
        $readmemh({stim, "/bias_i32.hex"},  mem_bias);
        $readmemh({stim, "/m_i32.hex"},     mem_m);
        $readmemh({stim, "/shift_u8.hex"},  mem_shift);
        $readmemh({stim, "/ypre_exp_i8.hex"}, mem_yp);
        // 复位两个周期，此后逐拍驱动（negedge 打入，posedge 采样比对）
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        for (c = 0; c < n_cyc; c = c + 1) begin
            en    = mem_en[c];
            acc   = mem_acc[c];
            bias  = mem_bias[c];
            m     = mem_m[c];
            shift = mem_shift[c];
            @(posedge clk);
            #1;
            if (y_pre !== mem_yp[c]) begin
                n_err = n_err + 1;
                if (n_err == 1) begin
                    first_cyc = c;
                    $display("[tb] first mismatch @cyc=%0d acc=%0d bias=%0d m=%0d shift=%0d got=%0d exp=%0d",
                             c, acc, bias, m, shift, y_pre, mem_yp[c]);
                end
            end
            if (vld !== en) begin
                n_vld_err = n_vld_err + 1;
            end
            @(negedge clk);
        end
        if (n_err == 0 && n_vld_err == 0) begin
            $display("TB_REQUANT_PASS compared=%0d vectors (y_pre+vld)", n_cyc);
        end else begin
            $display("TB_REQUANT_FAIL compared=%0d errors=%0d vld_errors=%0d first_cyc=%0d",
                     n_cyc, n_err, n_vld_err, first_cyc);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_REQUANT_FAIL (timeout)");
        $finish;
    end

endmodule
