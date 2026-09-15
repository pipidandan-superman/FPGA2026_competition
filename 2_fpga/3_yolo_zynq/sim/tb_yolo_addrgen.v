/************************************************************************
 * File Name       : tb_yolo_addrgen.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_addrgen
 * Description     : M7 gate testbench for yolo_addrgen. Replays every
 *                   tile descriptor from the vecgen (14 cfg words per
 *                   tile), pulses start, and compares the one-beat-per-
 *                   cycle im2col address stream (x_addr / pad / pad_val
 *                   / k / n_local) against the golden stream beat by
 *                   beat; checks done_o pulses exactly at tile end and
 *                   vld_o drops afterwards.
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/addrgen +WDT_MS=400 \
 *                          -do "run -all; quit -f" work.tb_yolo_addrgen
 *                   Gate token: TB_ADDRGEN_PASS / TB_ADDRGEN_FAIL.
 * Dependencies    : rtl/yolo_addrgen.v, sim/addrgen_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M7)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_addrgen;

    localparam AW       = 32;
    localparam NTILE_MAX = 256;     // tile 数上界（实际由 n_tiles.hex 给出）
    localparam NBEAT_MAX = 131072;  // beat 总数上界
    localparam CFG_W    = 14;       // 每 tile 描述字数

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [15:0] ih = 16'd0;
    reg [15:0] iw = 16'd0;
    reg [15:0] ow = 16'd0;
    reg [15:0] ic = 16'd0;
    reg [7:0]  kh = 8'd0;
    reg [7:0]  kw = 8'd0;
    reg [7:0]  sh = 8'd0;
    reg [7:0]  sw = 8'd0;
    reg [7:0]  ph = 8'd0;
    reg [7:0]  pw = 8'd0;
    reg [15:0] k_len = 16'd0;
    reg [15:0] n_start = 16'd0;
    reg [15:0] n_len = 16'd0;
    reg        first = 1'b0;
    wire       busy;
    wire       done;
    wire       vld;
    wire [AW-1:0] x_addr;
    wire       pad;
    wire [7:0] pad_val;
    wire [15:0] k;
    wire [15:0] n_loc;

    reg [15:0] mem_cfg [0:NTILE_MAX*CFG_W-1];
    reg [31:0] mem_cnt [0:NTILE_MAX-1];
    reg [31:0] mem_n [0:0];                  // $readmemh 载体（tile 数字数）
    reg [31:0] mem_addr [0:NBEAT_MAX-1];
    reg [0:0]  mem_pad [0:NBEAT_MAX-1];
    reg [7:0]  mem_pv [0:NBEAT_MAX-1];
    reg [15:0] mem_k [0:NBEAT_MAX-1];
    reg [15:0] mem_nl [0:NBEAT_MAX-1];
    integer    n_tile = 0;

    integer t;
    integer b;
    integer beat_base;
    integer beat_cnt;
    integer n_err = 0;
    integer n_beats = 0;
    integer first_tile = 0;
    integer first_beat = 0;

    yolo_addrgen #(
        .AW(AW)
    ) dut (
        .clk_i(clk),
        .rst_n(rst_n),
        .start_i(start),
        .ih_i(ih),
        .iw_i(iw),
        .ow_i(ow),
        .ic_i(ic),
        .kh_i(kh),
        .kw_i(kw),
        .sh_i(sh),
        .sw_i(sw),
        .ph_i(ph),
        .pw_i(pw),
        .k_len_i(k_len),
        .n_start_i(n_start),
        .n_len_i(n_len),
        .first_i(first),
        .busy_o(busy),
        .done_o(done),
        .vld_o(vld),
        .x_addr_o(x_addr),
        .pad_o(pad),
        .pad_val_o(pad_val),
        .k_o(k),
        .n_o(n_loc)
    );

    always #5 clk = ~clk;

    reg [1023:0] stim = "../stim/addrgen";
    integer      wdt_ms = 400;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        $readmemh({stim, "/n_tiles.hex"}, mem_n);
        n_tile = mem_n[0];
        $display("[tb] addrgen stim=%0s tiles=%0d", stim, n_tile);
        $readmemh({stim, "/cfg_u16.hex"},   mem_cfg);
        $readmemh({stim, "/cnt_u32.hex"},   mem_cnt);
        $readmemh({stim, "/xaddr_u32.hex"}, mem_addr);
        $readmemh({stim, "/pad.hex"},       mem_pad);
        $readmemh({stim, "/padval_i8.hex"}, mem_pv);
        $readmemh({stim, "/k_u16.hex"},     mem_k);
        $readmemh({stim, "/nloc_u16.hex"},  mem_nl);
        // 复位两个周期后逐 tile 执行
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        beat_base = 0;
        for (t = 0; t < n_tile; t = t + 1) begin
            // 描述字装载（每 tile 14 字）
            ih      = mem_cfg[t*CFG_W + 0];
            iw      = mem_cfg[t*CFG_W + 1];
            ow      = mem_cfg[t*CFG_W + 2];
            ic      = mem_cfg[t*CFG_W + 3];
            kh      = mem_cfg[t*CFG_W + 4][7:0];
            kw      = mem_cfg[t*CFG_W + 5][7:0];
            sh      = mem_cfg[t*CFG_W + 6][7:0];
            sw      = mem_cfg[t*CFG_W + 7][7:0];
            ph      = mem_cfg[t*CFG_W + 8][7:0];
            pw      = mem_cfg[t*CFG_W + 9][7:0];
            k_len   = mem_cfg[t*CFG_W + 10];
            n_start = mem_cfg[t*CFG_W + 11];
            n_len   = mem_cfg[t*CFG_W + 12];
            first   = mem_cfg[t*CFG_W + 13][0];
            beat_cnt = mem_cnt[t];
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            // 捕获 posedge 已过，当前拍即 beat 0（组合输出随计数器）
            for (b = 0; b < beat_cnt; b = b + 1) begin
                #1;
                if (vld !== 1'b1) begin
                    n_err = n_err + 1;
                    if (n_err == 1) begin
                        first_tile = t;
                        first_beat = b;
                        $display("[tb] vld low @tile=%0d beat=%0d", t, b);
                    end
                end else if (x_addr !== mem_addr[beat_base + b]
                             || pad !== mem_pad[beat_base + b]
                             || pad_val !== mem_pv[beat_base + b]
                             || k !== mem_k[beat_base + b]
                             || n_loc !== mem_nl[beat_base + b]) begin
                    n_err = n_err + 1;
                    if (n_err == 1) begin
                        first_tile = t;
                        first_beat = b;
                        $display("[tb] first mismatch @tile=%0d beat=%0d addr=%0d(exp %0d) pad=%0d(exp %0d) pv=%0d(exp %0d) k=%0d(exp %0d) n=%0d(exp %0d)",
                                 t, b, x_addr, mem_addr[beat_base + b],
                                 pad, mem_pad[beat_base + b],
                                 pad_val, mem_pv[beat_base + b],
                                 k, mem_k[beat_base + b],
                                 n_loc, mem_nl[beat_base + b]);
                    end
                end
                @(negedge clk);
            end
            // done 脉冲恰在末 beat 之后一拍，且 vld 回落
            #1;
            if (done !== 1'b1 || vld !== 1'b0) begin
                n_err = n_err + 1;
                if (n_err == 1) begin
                    first_tile = t;
                    $display("[tb] done/vld wrong @tile=%0d done=%0d vld=%0d",
                             t, done, vld);
                end
            end
            @(negedge clk);
            beat_base = beat_base + beat_cnt;
            n_beats = n_beats + beat_cnt;
        end
        if (n_err == 0) begin
            $display("TB_ADDRGEN_PASS compared=%0d beats across %0d tiles",
                     n_beats, n_tile);
        end else begin
            $display("TB_ADDRGEN_FAIL errors=%0d first_tile=%0d first_beat=%0d",
                     n_err, first_tile, first_beat);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_ADDRGEN_FAIL (timeout)");
        $finish;
    end

endmodule
