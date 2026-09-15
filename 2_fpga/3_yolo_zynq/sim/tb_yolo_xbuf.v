/************************************************************************
 * File Name       : tb_yolo_xbuf.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_xbuf
 * Description     : M4 gate testbench for yolo_xbuf. Replays the op
 *                   stream (data writes, broadcast reads, same-cycle
 *                   write+read on opposite banks, idle holds) and
 *                   compares the pair (dout_o, dout_vld_o) against the
 *                   BFM golden EVERY cycle (hold semantics included via
 *                   the golden output shadow).
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/xbuf +WDT_MS=1000 \
 *                          -do "run -all; quit -f" work.tb_yolo_xbuf
 *                   Gate token: TB_XBUF_PASS / TB_XBUF_FAIL.
 * Dependencies    : rtl/yolo_xbuf.v, sim/xbuf_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M4)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_xbuf;

    localparam N_COLS   = 16;
    localparam K_MAX    = 2304;
    localparam AW       = 12;
    localparam COL_AW   = 5;
    localparam NOPS_MAX = 262144;    // 操作数上界（实际由 n_ops.hex 给出）

    localparam OP_IDLE  = 2'd0;
    localparam OP_WD    = 2'd1;
    localparam OP_RD    = 2'd2;
    localparam OP_WRRD  = 2'd3;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg we = 1'b0;
    reg wr_bank = 1'b0;
    reg [COL_AW-1:0] wcol = {COL_AW{1'b0}};
    reg [AW-1:0] waddr = {AW{1'b0}};
    reg [7:0] wdata = 8'd0;
    reg rd_bank = 1'b0;
    reg ren = 1'b0;
    reg [AW-1:0] raddr = {AW{1'b0}};
    wire [N_COLS*8-1:0] dout;
    wire dout_vld;

    reg [1:0]   mem_op [0:NOPS_MAX-1];
    reg [0:0]   mem_bank [0:NOPS_MAX-1];
    reg [7:0]   mem_col [0:NOPS_MAX-1];
    reg [15:0]  mem_k [0:NOPS_MAX-1];
    reg [7:0]   mem_wd [0:NOPS_MAX-1];
    reg [0:0]   mem_rb [0:NOPS_MAX-1];
    reg [15:0]  mem_rk [0:NOPS_MAX-1];
    reg [127:0] mem_ed [0:NOPS_MAX-1];
    reg [0:0]   mem_ev [0:NOPS_MAX-1];
    integer     n_ops = 0;
    reg [31:0]  mem_n [0:0];         // $readmemh 载体（操作数字数）

    integer c;
    integer n_err = 0;
    integer n_chk = 0;
    integer first_cyc = 0;

    yolo_xbuf #(
        .N_COLS(N_COLS),
        .K_MAX(K_MAX),
        .AW(AW),
        .COL_AW(COL_AW)
    ) dut (
        .clk_i(clk),
        .rst_n(rst_n),
        .we_i(we),
        .wr_bank_i(wr_bank),
        .wcol_i(wcol),
        .waddr_i(waddr),
        .wdata_i(wdata),
        .rd_bank_i(rd_bank),
        .ren_i(ren),
        .raddr_i(raddr),
        .dout_o(dout),
        .dout_vld_o(dout_vld)
    );

    always #5 clk = ~clk;

    reg [1023:0] stim = "../stim/xbuf";
    integer      wdt_ms = 1000;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        $readmemh({stim, "/n_ops.hex"}, mem_n);
        n_ops = mem_n[0];
        $display("[tb] xbuf stim=%0s ops=%0d", stim, n_ops);
        $readmemh({stim, "/op.hex"},          mem_op);
        $readmemh({stim, "/bank.hex"},        mem_bank);
        $readmemh({stim, "/col_u8.hex"},      mem_col);
        $readmemh({stim, "/kaddr_u16.hex"},   mem_k);
        $readmemh({stim, "/wdata_u8.hex"},    mem_wd);
        $readmemh({stim, "/rbank.hex"},       mem_rb);
        $readmemh({stim, "/rkaddr_u16.hex"},  mem_rk);
        $readmemh({stim, "/edout_i128.hex"},  mem_ed);
        $readmemh({stim, "/evld.hex"},        mem_ev);
        // 复位两个周期后逐拍执行（negedge 驱动，posedge+#1 比对）
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        for (c = 0; c < n_ops; c = c + 1) begin
            we      = 1'b0;
            ren     = 1'b0;
            wr_bank = mem_bank[c];
            wcol    = mem_col[c][COL_AW-1:0];
            waddr   = mem_k[c][AW-1:0];
            wdata   = mem_wd[c];
            raddr   = mem_rk[c][AW-1:0];
            rd_bank = mem_rb[c];
            if (mem_op[c] == OP_WD || mem_op[c] == OP_WRRD) begin
                we = 1'b1;
            end
            if (mem_op[c] == OP_RD || mem_op[c] == OP_WRRD) begin
                ren     = 1'b1;
                raddr   = (mem_op[c] == OP_RD) ? mem_k[c][AW-1:0]
                                              : mem_rk[c][AW-1:0];
                rd_bank = (mem_op[c] == OP_RD) ? mem_bank[c] : mem_rb[c];
            end
            @(posedge clk);
            #1;
            n_chk = n_chk + 1;
            if (dout !== mem_ed[c] || dout_vld !== mem_ev[c]) begin
                n_err = n_err + 1;
                if (n_err == 1) begin
                    first_cyc = c;
                    $display("[tb] first mismatch @op=%0d op_type=%0d dout=%0d(exp %0d) dv=%0d(exp %0d)",
                             c, mem_op[c], dout, mem_ed[c], dout_vld,
                             mem_ev[c]);
                end
            end
            @(negedge clk);
        end
        if (n_err == 0) begin
            $display("TB_XBUF_PASS compared=%0d ops (dout+vld)", n_chk);
        end else begin
            $display("TB_XBUF_FAIL errors=%0d first_op=%0d", n_err, first_cyc);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_XBUF_FAIL (timeout)");
        $finish;
    end

endmodule
