/************************************************************************
 * File Name       : tb_yolo_conv_core.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_conv_core
 * Description     : M0 gate testbench for yolo_conv_core (parameterized
 *                   general conv core). Loads one stimulus directory
 *                   (hex files identical in layout to conv0_goldenNN),
 *                   runs one full pass, and compares every output byte
 *                   against y_exp. Shape/pad/act come from -g parameter
 *                   overrides at vsim load time (defaults = conv0 shape,
 *                   so the real golden00 stimulus runs without overrides
 *                   as regression anchor).
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt -gIC=64 -gOC=8 -gKH=3 -gIH=40 \
 *                          +STIM=../stim/genB_k576_s1p1_rand \
 *                          +CASE=genB +WDT_MS=300 \
 *                          -do "run -all; quit -f" work.tb_yolo_conv_core
 *                   Gate token: TB_CONVGEN_PASS / TB_CONVGEN_FAIL.
 * Dependencies    : rtl/yolo_conv_core.v, sim/synstim_gen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M0)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_conv_core;

    parameter IC      = 3;
    parameter OC      = 16;
    parameter KH      = 3;
    parameter KW      = 3;
    parameter IH      = 320;
    parameter IW      = 320;
    parameter SH      = 2;
    parameter SW      = 2;
    parameter PH      = 1;
    parameter PW      = 1;
    parameter [7:0]   PAD_VAL = 8'h80;
    parameter HAS_ACT = 1;

    function [31:0] clog2;
        input [31:0] value;
        integer v;
        integer r;
        begin
            v = value - 1;
            r = 0;
            while (v > 0) begin
                v = v >> 1;
                r = r + 1;
            end
            if (r == 0) begin
                r = 1;
            end
            clog2 = r;
        end
    endfunction

    localparam KP   = IC * KH * KW;
    localparam OH   = (IH + 2 * PH - KH) / SH + 1;
    localparam OW   = (IW + 2 * PW - KW) / SW + 1;
    localparam NX   = IC * IH * IW;
    localparam NW   = OC * KP;
    localparam NP   = OC;
    localparam NL   = 256;
    localparam NY   = OC * OH * OW;
    localparam X_AW = clog2(NX);
    localparam W_AW = clog2(NW);
    localparam Y_AW = clog2(NY);
    localparam P_AW = clog2(NP);

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    wire busy;
    wire done;
    wire y_we;
    wire [X_AW-1:0] x_addr;
    wire [W_AW-1:0] w_addr;
    wire [P_AW-1:0] bias_addr;
    wire [P_AW-1:0] m_addr;
    wire [P_AW-1:0] shift_addr;
    wire [7:0] lut_addr;
    wire [Y_AW-1:0] y_addr;
    wire signed [7:0] x_rdata;
    wire signed [7:0] w_rdata;
    wire signed [31:0] bias_rdata;
    wire signed [31:0] m_rdata;
    wire [7:0] shift_rdata;
    wire signed [7:0] lut_rdata;
    wire signed [7:0] y_wdata;

    reg signed [7:0]  mem_x [0:NX-1];
    reg signed [7:0]  mem_w [0:NW-1];
    reg signed [31:0] mem_bias [0:NP-1];
    reg signed [31:0] mem_m [0:NP-1];
    reg [7:0]         mem_shift [0:NP-1];
    reg signed [7:0]  mem_lut [0:NL-1];
    reg signed [7:0]  mem_y [0:NY-1];
    reg signed [7:0]  mem_yexp [0:NY-1];

    assign x_rdata     = mem_x[x_addr];
    assign w_rdata     = mem_w[w_addr];
    assign bias_rdata  = mem_bias[bias_addr];
    assign m_rdata     = mem_m[m_addr];
    assign shift_rdata = mem_shift[shift_addr];
    assign lut_rdata   = mem_lut[lut_addr];

    always @(posedge clk) begin
        if (y_we) begin
            mem_y[y_addr] <= y_wdata;
        end
    end

    yolo_conv_core #(
        .IC(IC),
        .OC(OC),
        .KH(KH),
        .KW(KW),
        .IH(IH),
        .IW(IW),
        .SH(SH),
        .SW(SW),
        .PH(PH),
        .PW(PW),
        .PAD_VAL(PAD_VAL),
        .HAS_ACT(HAS_ACT),
        .X_AW(X_AW),
        .W_AW(W_AW),
        .Y_AW(Y_AW),
        .P_AW(P_AW)
    ) dut (
        .clk_i(clk),
        .rst_n(rst_n),
        .start_i(start),
        .busy_o(busy),
        .done_o(done),
        .x_addr_o(x_addr),
        .x_rdata_i(x_rdata),
        .w_addr_o(w_addr),
        .w_rdata_i(w_rdata),
        .bias_addr_o(bias_addr),
        .bias_rdata_i(bias_rdata),
        .m_addr_o(m_addr),
        .m_rdata_i(m_rdata),
        .shift_addr_o(shift_addr),
        .shift_rdata_i(shift_rdata),
        .lut_addr_o(lut_addr),
        .lut_rdata_i(lut_rdata),
        .y_we_o(y_we),
        .y_addr_o(y_addr),
        .y_wdata_o(y_wdata)
    );

    always #5 clk = ~clk;

    reg [1023:0] stim = "../stim/conv0_golden00";
    reg [255:0]  casename = "case0";
    integer      wdt_ms = 1000;
    integer      n_wr = 0;
    integer      n_err = 0;
    integer      first_i = 0;
    reg signed [7:0] first_got;
    reg signed [7:0] first_exp;
    reg cmp_pending = 1'b0;
    integer i;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("CASE=%s", casename)) begin
            // plusarg present, casename updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        $display("[tb] case=%0s IC=%0d OC=%0d KH=%0d KW=%0d IH=%0d IW=%0d SH=%0d SW=%0d PH=%0d PW=%0d PAD=%0d ACT=%0d KP=%0d OH=%0d OW=%0d NY=%0d",
                 casename, IC, OC, KH, KW, IH, IW, SH, SW, PH, PW, PAD_VAL,
                 HAS_ACT, KP, OH, OW, NY);
        $display("[tb] stim=%0s wdt_ms=%0d", stim, wdt_ms);

        $readmemh({stim, "/x_i8.hex"},         mem_x);
        $readmemh({stim, "/w_i8.hex"},         mem_w);
        $readmemh({stim, "/bias_eff_i32.hex"}, mem_bias);
        $readmemh({stim, "/m_i32.hex"},        mem_m);
        $readmemh({stim, "/shift_u8.hex"},     mem_shift);
        $readmemh({stim, "/lut_i8.hex"},       mem_lut);
        $readmemh({stim, "/y_exp_i8.hex"},     mem_yexp);
        for (i = 0; i < NY; i = i + 1) begin
            mem_y[i] = 8'h00;
        end

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_CONVGEN_FAIL (timeout) case=%0s n_wr=%0d/%0d",
                 casename, n_wr, NY);
        $finish;
    end

    always @(posedge clk) begin
        if (y_we) begin
            n_wr = n_wr + 1;
            if (n_wr == NY) begin
                cmp_pending <= 1'b1;
            end
        end
        if (cmp_pending) begin
            cmp_pending <= 1'b0;
            n_err = 0;
            for (i = 0; i < NY; i = i + 1) begin
                if (mem_y[i] !== mem_yexp[i]) begin
                    n_err = n_err + 1;
                    if (n_err == 1) begin
                        first_i   = i;
                        first_got = mem_y[i];
                        first_exp = mem_yexp[i];
                        $display("[tb] first mismatch @oc=%0d oy=%0d ox=%0d (lin=%0d) got=%0d exp=%0d",
                                 i / (OH * OW), (i % (OH * OW)) / OW,
                                 i % OW, i, mem_y[i], mem_yexp[i]);
                    end
                end
            end
            if (n_err == 0) begin
                $display("TB_CONVGEN_PASS case=%0s compared=%0d/%0d",
                         casename, n_wr, NY);
            end else begin
                $display("TB_CONVGEN_FAIL case=%0s compared=%0d/%0d errors=%0d first_lin=%0d got=%0d exp=%0d",
                         casename, n_wr, NY, n_err, first_i, first_got,
                         first_exp);
            end
            $finish;
        end
    end

endmodule
