/************************************************************************
 * File Name       : tb_yolo_silu_lut.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_silu_lut
 * Description     : M6 gate testbench for yolo_silu_lut. Replays the
 *                   unified op stream: table loads through the write
 *                   port (256 entries x real/synthetic tables), then a
 *                   full 256-index walk per table (y_pre -128..127)
 *                   with interleaved act-bypass and hold vectors;
 *                   compares y_o against the golden every read op and
 *                   checks vld_o == en.
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/lutmod +WDT_MS=200 \
 *                          -do "run -all; quit -f" work.tb_yolo_silu_lut
 *                   Gate token: TB_LUT_PASS / TB_LUT_FAIL.
 * Dependencies    : rtl/yolo_silu_lut.v, sim/lut_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M6)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_silu_lut;

    localparam DW       = 8;
    localparam AW       = 8;
    localparam NCYC_MAX = 8192;      // 操作数上界（实际由 n_cycles.hex 给出）

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg we = 1'b0;
    reg [AW-1:0] waddr = {AW{1'b0}};
    reg [DW-1:0] wdata = {DW{1'b0}};
    reg en = 1'b0;
    reg act = 1'b0;
    reg signed [DW-1:0] y_pre = 8'sd0;
    wire [DW-1:0] y;
    wire vld;

    reg [0:0]    mem_op [0:NCYC_MAX-1];
    reg [7:0]    mem_wa [0:NCYC_MAX-1];
    reg [7:0]    mem_wd [0:NCYC_MAX-1];
    reg [0:0]    mem_en [0:NCYC_MAX-1];
    reg [0:0]    mem_act [0:NCYC_MAX-1];
    reg [7:0]    mem_yp [0:NCYC_MAX-1];
    reg [7:0]    mem_y [0:NCYC_MAX-1];
    integer      n_cyc = 0;
    reg [31:0]   mem_n [0:0];       // $readmemh 载体（操作数字数）

    integer c;
    integer n_err = 0;
    integer n_cmp = 0;
    integer n_vld_err = 0;
    integer first_cyc = 0;

    yolo_silu_lut #(
        .DW(DW),
        .AW(AW)
    ) dut (
        .clk_i(clk),
        .rst_n(rst_n),
        .we_i(we),
        .waddr_i(waddr),
        .wdata_i(wdata),
        .en_i(en),
        .act_i(act),
        .y_pre_i(y_pre),
        .y_o(y),
        .vld_o(vld)
    );

    always #5 clk = ~clk;

    reg [1023:0] stim = "../stim/lutmod";
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
        $display("[tb] lutmod stim=%0s ops=%0d", stim, n_cyc);
        $readmemh({stim, "/op.hex"},         mem_op);
        $readmemh({stim, "/waddr_u8.hex"},   mem_wa);
        $readmemh({stim, "/wdata_i8.hex"},   mem_wd);
        $readmemh({stim, "/en.hex"},         mem_en);
        $readmemh({stim, "/act.hex"},        mem_act);
        $readmemh({stim, "/ypre_i8.hex"},    mem_yp);
        $readmemh({stim, "/y_exp_i8.hex"},   mem_y);
        // 复位两个周期，此后逐拍驱动（negedge 打入，posedge 采样比对）
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        for (c = 0; c < n_cyc; c = c + 1) begin
            if (mem_op[c] == 1'b0) begin
                // 写操作：驱动写口，读口静止
                we    = 1'b1;
                en    = 1'b0;
                act   = 1'b0;
                waddr = mem_wa[c];
                wdata = mem_wd[c];
            end else begin
                // 读操作：比对 y_o 黄金与 vld
                we    = 1'b0;
                en    = mem_en[c];
                act   = mem_act[c];
                y_pre = mem_yp[c];
                @(posedge clk);
                #1;
                n_cmp = n_cmp + 1;
                if (y !== mem_y[c]) begin
                    n_err = n_err + 1;
                    if (n_err == 1) begin
                        first_cyc = c;
                        $display("[tb] first mismatch @cyc=%0d ypre=%0d act=%0d got=%0d exp=%0d",
                                 c, y_pre, act, y, mem_y[c]);
                    end
                end
                if (vld !== en) begin
                    n_vld_err = n_vld_err + 1;
                end
                @(negedge clk);
            end
            if (mem_op[c] == 1'b0) begin
                @(posedge clk);
                #1;
                @(negedge clk);
            end
        end
        if (n_err == 0 && n_vld_err == 0) begin
            $display("TB_LUT_PASS compared=%0d reads (y+vld)", n_cmp);
        end else begin
            $display("TB_LUT_FAIL compared=%0d errors=%0d vld_errors=%0d first_cyc=%0d",
                     n_cmp, n_err, n_vld_err, first_cyc);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_LUT_FAIL (timeout)");
        $finish;
    end

endmodule
