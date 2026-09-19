/************************************************************************
 * File Name       : tb_yolo_ctrl.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_ctrl
 * Description     : M8 gate testbench for yolo_ctrl. Replays the layer
 *                   descriptor timeline (drive: valid/oc/n/k/last +
 *                   V1.1 tile_rdy) and compares 15 outputs EVERY cycle
 *                   against the instruction-level reference model
 *                   (register shadow): dsc_ready/busy/acc_clr/beat_en/
 *                   k_cnt/rq_en/rq_idx/wr_bank/rd_bank/oc_tile/n_tile/
 *                   n_tail/oc_tail/layer_done/all_done.
 *                   Outputs are combinational on registered state ->
 *                   sample posedge+#1 (negedge drive convention). The
 *                   per-cycle tile_rdy value is replayed from
 *                   drv_rdy.hex (the golden decides the wait pattern).
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/ctrl +WDT_MS=60000 \
 *                          -do "run -all; quit -f" work.tb_yolo_ctrl
 *                   Gate token: TB_CTRL_PASS / TB_CTRL_FAIL.
 * Dependencies    : rtl/yolo_ctrl.v, sim/ctrl_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M8)
 *   - V1.1 (2026-09-15) by LSL : tile_rdy_i drive from drv_rdy.hex
 *     (ctrl V1.1 gate rerun, run02)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_ctrl;

    localparam OC_EDGE  = 16;
    localparam N_EDGE   = 16;
    localparam OC_AW    = 11;
    localparam N_AW     = 16;
    localparam K_AW     = 12;
    localparam TILE_AW  = 12;
    localparam NCYC_MAX = 1048576;   // 周期数上界（实际由 n_cycles.hex 给出）

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg dsc_valid = 1'b0;
    wire dsc_ready;
    reg [OC_AW-1:0] dsc_oc = {OC_AW{1'b0}};
    reg [N_AW-1:0]  dsc_n = {N_AW{1'b0}};
    reg [K_AW-1:0]  dsc_k = {K_AW{1'b0}};
    reg dsc_last = 1'b0;
    reg tile_rdy = 1'b1;
    wire acc_clr;
    wire beat_en;
    wire [K_AW-1:0] k_cnt;
    wire rq_en;
    wire [TILE_AW-1:0] rq_idx;
    wire wr_bank;
    wire rd_bank;
    wire [TILE_AW-1:0] oc_tile;
    wire [TILE_AW-1:0] n_tile;
    wire [TILE_AW-1:0] n_tail;
    wire [TILE_AW-1:0] oc_tail;
    wire layer_done;
    wire all_done;
    wire busy;

    reg [0:0]  mem_dv [0:NCYC_MAX-1];
    reg [15:0] mem_doc [0:NCYC_MAX-1];
    reg [15:0] mem_dn [0:NCYC_MAX-1];
    reg [15:0] mem_dk [0:NCYC_MAX-1];
    reg [0:0]  mem_dl [0:NCYC_MAX-1];
    reg [0:0]  mem_rty [0:NCYC_MAX-1];
    reg [0:0]  mem_erd [0:NCYC_MAX-1];
    reg [0:0]  mem_ebs [0:NCYC_MAX-1];
    reg [0:0]  mem_eac [0:NCYC_MAX-1];
    reg [0:0]  mem_ebe [0:NCYC_MAX-1];
    reg [15:0] mem_ek [0:NCYC_MAX-1];
    reg [0:0]  mem_erq [0:NCYC_MAX-1];
    reg [15:0] mem_erqi [0:NCYC_MAX-1];
    reg [0:0]  mem_ewb [0:NCYC_MAX-1];
    reg [0:0]  mem_erb [0:NCYC_MAX-1];
    reg [15:0] mem_eoct [0:NCYC_MAX-1];
    reg [15:0] mem_ent [0:NCYC_MAX-1];
    reg [15:0] mem_enta [0:NCYC_MAX-1];
    reg [15:0] mem_eocta [0:NCYC_MAX-1];
    reg [0:0]  mem_eld [0:NCYC_MAX-1];
    reg [0:0]  mem_ead [0:NCYC_MAX-1];
    integer    n_cyc = 0;
    reg [31:0] mem_n [0:0];          // $readmemh 载体（周期数）

    integer c;
    integer n_err = 0;
    integer n_chk = 0;
    integer first_cyc = 0;
    integer n_ldone = 0;
    integer n_alldone = 0;

    yolo_ctrl #(
        .OC_EDGE(OC_EDGE),
        .N_EDGE(N_EDGE),
        .OC_AW(OC_AW),
        .N_AW(N_AW),
        .K_AW(K_AW),
        .TILE_AW(TILE_AW)
    ) dut (
        .clk_i(clk),
        .rst_n(rst_n),
        .dsc_valid_i(dsc_valid),
        .dsc_ready_o(dsc_ready),
        .dsc_oc_i(dsc_oc),
        .dsc_n_i(dsc_n),
        .dsc_k_i(dsc_k),
        .dsc_last_i(dsc_last),
        .tile_rdy_i(tile_rdy),
        .rq_rdy_i(1'b1),            // V1.2: tied high == V1.1 cycle-exact (regression)
        .acc_clr_o(acc_clr),
        .beat_en_o(beat_en),
        .k_cnt_o(k_cnt),
        .rq_en_o(rq_en),
        .rq_idx_o(rq_idx),
        .wr_bank_o(wr_bank),
        .rd_bank_o(rd_bank),
        .oc_tile_o(oc_tile),
        .n_tile_o(n_tile),
        .n_tail_o(n_tail),
        .oc_tail_o(oc_tail),
        .layer_done_o(layer_done),
        .all_done_o(all_done),
        .busy_o(busy)
    );

    always #5 clk = ~clk;

    reg [1023:0] stim = "../stim/ctrl";
    integer      wdt_ms = 60000;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        $readmemh({stim, "/n_cycles.hex"}, mem_n);
        n_cyc = mem_n[0];
        $display("[tb] ctrl stim=%0s cycles=%0d", stim, n_cyc);
        $readmemh({stim, "/drv_valid.hex"}, mem_dv);
        $readmemh({stim, "/drv_oc.hex"},    mem_doc);
        $readmemh({stim, "/drv_n.hex"},     mem_dn);
        $readmemh({stim, "/drv_k.hex"},     mem_dk);
        $readmemh({stim, "/drv_last.hex"},  mem_dl);
        $readmemh({stim, "/drv_rdy.hex"},   mem_rty);
        $readmemh({stim, "/e_ready.hex"},   mem_erd);
        $readmemh({stim, "/e_busy.hex"},    mem_ebs);
        $readmemh({stim, "/e_accclr.hex"},  mem_eac);
        $readmemh({stim, "/e_beaten.hex"},  mem_ebe);
        $readmemh({stim, "/e_k.hex"},       mem_ek);
        $readmemh({stim, "/e_rqen.hex"},    mem_erq);
        $readmemh({stim, "/e_rqidx.hex"},   mem_erqi);
        $readmemh({stim, "/e_wrbank.hex"},  mem_ewb);
        $readmemh({stim, "/e_rdbank.hex"},  mem_erb);
        $readmemh({stim, "/e_octile.hex"},  mem_eoct);
        $readmemh({stim, "/e_ntile.hex"},   mem_ent);
        $readmemh({stim, "/e_ntail.hex"},   mem_enta);
        $readmemh({stim, "/e_octail.hex"},  mem_eocta);
        $readmemh({stim, "/e_ldone.hex"},   mem_eld);
        $readmemh({stim, "/e_alldone.hex"}, mem_ead);
        // 复位两个周期后逐拍执行（negedge 驱动，posedge+#1 比对）
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        for (c = 0; c < n_cyc; c = c + 1) begin
            dsc_valid = mem_dv[c];
            dsc_oc    = mem_doc[c][OC_AW-1:0];
            dsc_n     = mem_dn[c][N_AW-1:0];
            dsc_k     = mem_dk[c][K_AW-1:0];
            dsc_last  = mem_dl[c];
            tile_rdy  = mem_rty[c];
            @(posedge clk);
            #1;
            n_chk = n_chk + 1;
            if (layer_done) begin
                n_ldone = n_ldone + 1;
            end
            if (all_done) begin
                n_alldone = n_alldone + 1;
            end
            if (dsc_ready !== mem_erd[c] || busy !== mem_ebs[c]
                || acc_clr !== mem_eac[c] || beat_en !== mem_ebe[c]
                || k_cnt !== mem_ek[c][K_AW-1:0]
                || rq_en !== mem_erq[c]
                || rq_idx !== mem_erqi[c][TILE_AW-1:0]
                || wr_bank !== mem_ewb[c] || rd_bank !== mem_erb[c]
                || oc_tile !== mem_eoct[c][TILE_AW-1:0]
                || n_tile !== mem_ent[c][TILE_AW-1:0]
                || n_tail !== mem_enta[c][TILE_AW-1:0]
                || oc_tail !== mem_eocta[c][TILE_AW-1:0]
                || layer_done !== mem_eld[c]
                || all_done !== mem_ead[c]) begin
                n_err = n_err + 1;
                if (n_err == 1) begin
                    first_cyc = c;
                    $display("[tb] first mismatch @cyc=%0d rdy=%0d(exp %0d) busy=%0d(exp %0d) clr=%0d(exp %0d) ben=%0d(exp %0d) k=%0d(exp %0d) rqe=%0d(exp %0d) rqi=%0d(exp %0d) banks=%0d/%0d(exp %0d/%0d) tiles=%0d/%0d(exp %0d/%0d) tails=%0d/%0d(exp %0d/%0d) ld=%0d(exp %0d) ad=%0d(exp %0d)",
                             c, dsc_ready, mem_erd[c], busy, mem_ebs[c],
                             acc_clr, mem_eac[c], beat_en, mem_ebe[c],
                             k_cnt, mem_ek[c], rq_en, mem_erq[c],
                             rq_idx, mem_erqi[c], wr_bank, mem_ewb[c],
                             rd_bank, mem_erb[c], oc_tile, mem_eoct[c],
                             n_tile, mem_ent[c], n_tail, mem_enta[c],
                             oc_tail, mem_eocta[c], layer_done, mem_eld[c],
                             all_done, mem_ead[c]);
                end
            end
            @(negedge clk);
        end
        if (n_err == 0) begin
            $display("TB_CTRL_PASS compared=%0d cycles (15 outputs/cycle) ldone=%0d alldone=%0d",
                     n_chk, n_ldone, n_alldone);
        end else begin
            $display("TB_CTRL_FAIL errors=%0d first_cyc=%0d", n_err, first_cyc);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_CTRL_FAIL (timeout)");
        $finish;
    end

endmodule
