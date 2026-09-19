/************************************************************************
 * File Name       : tb_yolo_acc.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_acc
 * Description     : M2 gate testbench for yolo_acc (per-lane int32
 *                   accumulator bank). Drives the full acc stimulus
 *                   (clear/hold/K-resume/wrap/random mix), compares
 *                   every lane of q_o against the Python golden model
 *                   on EVERY cycle.
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/acc +WDT_MS=200 \
 *                          -do "run -all; quit -f" work.tb_yolo_acc
 *                   Gate token: TB_ACC_PASS / TB_ACC_FAIL.
 * Dependencies    : rtl/yolo_acc.v, sim/acc_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M2)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_acc;

    localparam N_LANES = 8;
    localparam DATA_W  = 32;
    localparam NCYC_MAX = 8192;     // 激励拍数上界（实际拍数由 n_cycles.hex 给出）

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clr = 1'b0;
    reg en = 1'b0;
    reg [N_LANES*DATA_W-1:0] d;
    wire [N_LANES*DATA_W-1:0] q;

    reg [0:0]         mem_clr [0:NCYC_MAX-1];
    reg [0:0]         mem_en [0:NCYC_MAX-1];
    reg signed [31:0] mem_d [0:N_LANES*NCYC_MAX-1];
    reg signed [31:0] mem_q [0:N_LANES*NCYC_MAX-1];
    integer           n_cyc = 0;
    reg [31:0]        mem_n [0:0];   // $readmemh 载体（拍数字数）

    integer c;
    integer l;
    integer n_err = 0;
    integer first_cyc = 0;
    integer first_lane = 0;
    integer k;

    yolo_acc #(
        .N_LANES(N_LANES),
        .DATA_W(DATA_W)
    ) dut (
        .clk_i(clk),
        .rst_n(rst_n),
        .clr_i(clr),
        .en_i(en),
        .d_i(d),
        .q_o(q)
    );

    always #5 clk = ~clk;

    reg [1023:0] stim = "../stim/acc";
    reg [7:0]    lane_ch;
    integer      wdt_ms = 200;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        $readmemh({stim, "/n_cycles.hex"}, mem_n);
        n_cyc = mem_n[0];
        $display("[tb] acc stim=%0s cycles=%0d lanes=%0d",
                 stim, n_cyc, N_LANES);
        $readmemh({stim, "/clr.hex"}, mem_clr);
        $readmemh({stim, "/en.hex"},   mem_en);
        for (l = 0; l < N_LANES; l = l + 1) begin
            lane_ch = "0" + l;              // ASCII 通道号 '0'..'7'
            $readmemh({stim, "/d", lane_ch, "_i32.hex"}, mem_d,
                      l * NCYC_MAX);
            $readmemh({stim, "/q", lane_ch, "_exp_i32.hex"}, mem_q,
                      l * NCYC_MAX);
        end
        // 复位两个周期，此后逐拍驱动（negedge 打入，posedge 采样比对）
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        for (c = 0; c < n_cyc; c = c + 1) begin
            clr = mem_clr[c];
            en  = mem_en[c];
            for (l = 0; l < N_LANES; l = l + 1) begin
                d[l*DATA_W +: DATA_W] = mem_d[l*NCYC_MAX + c];
            end
            @(posedge clk);
            #1;
            for (l = 0; l < N_LANES; l = l + 1) begin
                if (q[l*DATA_W +: DATA_W] !== mem_q[l*NCYC_MAX + c]) begin
                    n_err = n_err + 1;
                    if (n_err == 1) begin
                        first_cyc = c;
                        first_lane = l;
                        $display("[tb] first mismatch @cyc=%0d lane=%0d got=%0d exp=%0d",
                                 c, l, q[l*DATA_W +: DATA_W],
                                 mem_q[l*NCYC_MAX + c]);
                    end
                end
            end
            @(negedge clk);
        end
        k = n_cyc * N_LANES;
        if (n_err == 0) begin
            $display("TB_ACC_PASS compared=%0d/%0d (cycles x lanes)",
                     k, k);
        end else begin
            $display("TB_ACC_FAIL compared=%0d/%0d errors=%0d first_cyc=%0d first_lane=%0d",
                     k, k, n_err, first_cyc, first_lane);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_ACC_FAIL (timeout)");
        $finish;
    end

endmodule
