/************************************************************************
 * File Name       : tb_yolo_gemm_array.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_gemm_array
 * Description     : M10 gate testbench for yolo_gemm_array (SIM 8x8).
 *                   6-layer plan S1/R1/S2/S3/R2/S4 replayed from
 *                   layers.hex (28 tokens/layer: geometry + DDR bases +
 *                   golden bases + expsel). One DDR byte image
 *                   (ddr.hex, 64-bit LE words) backs the AXI read BFM
 *                   (random ar/r stalls, LFSR), the X-plane comb port,
 *                   the per-layer LUT preload and the golden memories.
 *
 *                   Golden hierarchy (baseline section 5): synthetic
 *                   layers compare against 4 static yolo_conv_core
 *                   instances (S1/S2/S3/S4 params; dedicated mirror W +
 *                   param arrays gw/gb/gm/gs{L}.hex, X served from the
 *                   same image planes); real layers R1/R2 compare
 *                   against yexp1/yexp2.hex (rom_data = G2 run04
 *                   deployment export; python chain reproduced the
 *                   run04 npz bit-exact before stimulus freeze).
 *
 *                   Y check: DUT y_we/y_addr/y_wdata scattered into a
 *                   per-layer span (sentinel detects double writes);
 *                   compare after all_done + drain + golden done.
 *                   Gate token: TB_GEMM_ARRAY_PASS / _FAIL.
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/m10 +WDT_MS=900000 \
 *                          -do "run -all; quit -f" work.tb_yolo_gemm_array
 * Dependencies    : rtl/yolo_gemm_array.v (+ M1-M9), rtl/yolo_conv_core.v,
 *                   sim/m10_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M10)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_gemm_array;

    // ---- DUT geometry (matches yolo_gemm_array defaults) ----
    localparam OC_EDGE   = 8;
    localparam N_EDGE    = 8;
    localparam OC_AW     = 11;
    localparam N_AW      = 16;
    localparam K_AW      = 12;
    localparam ADDR_W    = 32;
    localparam NL_MAX    = 8;
    localparam FLDS      = 28;      // tokens per layer row
    localparam IMG_WORDS = 66000;   // >= n_ddrwords.hex (65621)
    localparam YSPAN     = 410000;  // >= max oc*n (R1 409600)
    localparam SENT      = 8'hA5;

    // ---- clock / reset ----
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // ---- descriptor drive ----
    reg                  dsc_valid = 1'b0;
    wire                 dsc_ready;
    reg [OC_AW-1:0]      dsc_oc = 0;
    reg [N_AW-1:0]       dsc_n = 0;
    reg [K_AW-1:0]       dsc_k = 0;
    reg                  dsc_last = 1'b0;
    reg [15:0]           dsc_ih = 0, dsc_iw = 0, dsc_ow = 0, dsc_ic = 0;
    reg [7:0]            dsc_kh = 0, dsc_kw = 0, dsc_sh = 0, dsc_sw = 0;
    reg [7:0]            dsc_ph = 0, dsc_pw = 0;
    reg                  dsc_first = 1'b0, dsc_act = 1'b0;
    reg [ADDR_W-1:0]     dsc_wbase = 0, dsc_xbase = 0, dsc_bbase = 0;
    reg [ADDR_W-1:0]     dsc_mbase = 0, dsc_sbase = 0;

    // ---- AXI read BFM ----
    wire [ADDR_W-1:0]    araddr;
    wire [7:0]           arlen;
    wire [2:0]           arsize;
    wire [1:0]           arburst;
    wire                 arvalid;
    wire                 rready;
    wire                 arready;
    reg [63:0]           rdata;
    reg                  rvalid;
    reg                  rlast;

    // ---- X plane / LUT preload / Y ----
    wire [ADDR_W-1:0]    x_addr;
    reg  [7:0]           x_rdata;
    reg                  lut_we = 1'b0;
    reg  [7:0]           lut_waddr = 0, lut_wdata = 0;
    wire                 y_we;
    wire [ADDR_W-1:0]    y_addr;
    wire [7:0]           y_wdata;
    wire                 layer_done, all_done, busy;

    // ---- stimulus memories ----
    reg [63:0]           img [0:IMG_WORDS-1];
    reg [31:0]           lay [0:NL_MAX*FLDS-1];
    reg [31:0]           memtmp [0:0];
    reg [7:0]            yexp1 [0:409599];
    reg [7:0]            yexp2 [0:25599];
    integer              n_layers, n_words;
    integer              gi, L, i;

    // golden service memories (loaded at t0, static)
    reg [7:0]            gw0 [0:188];    // L0 S1: 7*27
    reg [31:0]           gb0 [0:6];
    reg [31:0]           gm0 [0:6];
    reg [7:0]            gs0 [0:6];
    reg [7:0]            gw2 [0:9215];   // L2 S2: 16*576
    reg [31:0]           gb2 [0:15];
    reg [31:0]           gm2 [0:15];
    reg [7:0]            gs2 [0:15];
    reg [7:0]            gw3 [0:575];    // L3 S3: 9*64
    reg [31:0]           gb3 [0:8];
    reg [31:0]           gm3 [0:8];
    reg [7:0]            gs3 [0:8];
    reg [7:0]            gw5 [0:18431];  // L5 S4: 8*2304
    reg [31:0]           gb5 [0:7];
    reg [31:0]           gm5 [0:7];
    reg [7:0]            gs5 [0:7];
    reg [7:0]            lut0 [0:255];   // per-golden LUT snapshots
    reg [7:0]            lut2 [0:255];
    reg [7:0]            lut3 [0:255];
    reg [7:0]            lut5 [0:255];

    // Y capture (DUT + golden scatter, sentinel = single-write check)
    reg [7:0]            yd [0:NL_MAX*YSPAN-1];
    reg [7:0]            yg [0:NL_MAX*YSPAN-1];
    integer              cur_layer = 0;
    integer              n_ywr = 0, n_dbl = 0, n_ybad = 0;

    // ---- image byte access helper ----
    function [7:0] imgbyte;
        input [31:0] a;
        reg [63:0] tw;
        begin
            tw = img[a[31:3]];
            imgbyte = tw[{a[2:0], 3'b000} +: 8];
        end
    endfunction

    // ---- DUT ----
    yolo_gemm_array #(
        .OC_EDGE (OC_EDGE),
        .N_EDGE  (N_EDGE),
        .OC_AW   (OC_AW),
        .N_AW    (N_AW),
        .K_AW    (K_AW)
    ) dut (
        .clk_i        (clk),
        .rst_n        (rst_n),
        .dsc_valid_i  (dsc_valid),
        .dsc_ready_o  (dsc_ready),
        .dsc_oc_i     (dsc_oc),
        .dsc_n_i      (dsc_n),
        .dsc_k_i      (dsc_k),
        .dsc_last_i   (dsc_last),
        .dsc_ih_i     (dsc_ih),
        .dsc_iw_i     (dsc_iw),
        .dsc_ow_i     (dsc_ow),
        .dsc_ic_i     (dsc_ic),
        .dsc_kh_i     (dsc_kh),
        .dsc_kw_i     (dsc_kw),
        .dsc_sh_i     (dsc_sh),
        .dsc_sw_i     (dsc_sw),
        .dsc_ph_i     (dsc_ph),
        .dsc_pw_i     (dsc_pw),
        .dsc_first_i  (dsc_first),
        .dsc_act_i    (dsc_act),
        .dsc_wbase_i  (dsc_wbase),
        .dsc_xbase_i  (dsc_xbase),
        .dsc_bbase_i  (dsc_bbase),
        .dsc_mbase_i  (dsc_mbase),
        .dsc_sbase_i  (dsc_sbase),
        .araddr_o     (araddr),
        .arlen_o      (arlen),
        .arsize_o     (arsize),
        .arburst_o    (arburst),
        .arvalid_o    (arvalid),
        .arready_i    (arready),
        .rdata_i      (rdata),
        .rlast_i      (rlast),
        .rvalid_i     (rvalid),
        .rready_o     (rready),
        .x_addr_o     (x_addr),
        .x_rdata_i    (x_rdata),
        .lut_we_i     (lut_we),
        .lut_waddr_i  (lut_waddr),
        .lut_wdata_i  (lut_wdata),
        .y_we_o       (y_we),
        .y_addr_o     (y_addr),
        .y_wdata_o    (y_wdata),
        .layer_done_o (layer_done),
        .all_done_o   (all_done),
        .busy_o       (busy)
    );

    // X plane comb serve (byte lane from the image word)
    always @(*) x_rdata = imgbyte(x_addr);

    // ---- AXI read BFM: one outstanding burst, random ar/r stalls ----
    reg [16:0] lfsr = 17'h1ACBD;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= 17'h1ACBD;
        else        lfsr <= {lfsr[15:0], lfsr[16] ^ lfsr[13]};
    end
    wire stall_ar = (lfsr[3:0] == 4'h0);

    localparam R_IDLE = 2'd0, R_DLY = 2'd1, R_BEAT = 2'd2, R_GAP = 2'd3;
    reg [1:0]  rstate = R_IDLE;
    reg [31:0] raddr_q = 0;
    reg [7:0]  rleft = 0;
    reg [1:0]  rdly = 0;

    assign arready = arvalid && (rstate == R_IDLE) && !stall_ar;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate <= R_IDLE;
            rvalid <= 1'b0;
            rlast  <= 1'b0;
            rleft  <= 8'd0;
            raddr_q<= 32'd0;
            rdly   <= 2'd0;
        end else begin
            case (rstate)
                R_IDLE: if (arvalid && arready) begin
                    raddr_q <= araddr;
                    rleft   <= arlen + 8'd1;
                    rdly    <= lfsr[1:0];
                    rstate  <= R_DLY;
                end
                R_DLY: begin
                    if (rdly == 2'd0) begin
                        rstate <= R_BEAT;
                        rvalid <= 1'b1;
                        rlast  <= (rleft == 8'd1);
                    end else begin
                        rdly <= rdly - 2'd1;
                    end
                end
                R_BEAT: if (rvalid && rready) begin
                    if (rleft == 8'd1) begin
                        rvalid <= 1'b0;
                        rlast  <= 1'b0;
                        rstate <= R_IDLE;
                    end else begin
                        rleft   <= rleft - 8'd1;
                        raddr_q <= raddr_q + 32'd8;
                        rlast   <= (rleft == 8'd2);
                        if (lfsr[2:0] == 3'b000) begin
                            rvalid <= 1'b0;
                            rstate <= R_GAP;
                        end
                    end
                end
                R_GAP: begin
                    rvalid <= 1'b1;
                    rstate <= R_BEAT;
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

    // rdata served combinationally from the image (bursts word-aligned)
    always @(*) rdata = img[raddr_q[31:3]];

    // ---- DUT Y scatter ----
    always @(posedge clk) begin
        if (y_we) begin
            n_ywr = n_ywr + 1;
            if (yd[cur_layer*YSPAN + y_addr] === SENT) begin
                yd[cur_layer*YSPAN + y_addr] <= y_wdata;
            end else begin
                n_dbl = n_dbl + 1;
                if (n_dbl == 1)
                    $display("[tb] ERROR double DUT write L=%0d addr=%0d",
                             cur_layer, y_addr);
            end
        end
    end

    // =================================================================
    // golden M0 instances (synthetic layers; comb-served from image)
    // =================================================================
    reg  g0_start = 1'b0, g2_start = 1'b0, g3_start = 1'b0, g5_start = 1'b0;
    wire g0_busy, g0_done, g2_busy, g2_done, g3_busy, g3_done;
    wire g5_busy, g5_done;
    wire [7:0]  g0_xa;                    // X_AW/W_AW per instance (PCDPC
    wire [12:0] g2_xa, g3_xa, g5_xa;      // fix: widths must match ports,
    wire [7:0]  g0_wa;                    // else addr MSBs are truncated)
    wire [9:0]  g3_wa;
    wire [13:0] g2_wa;
    wire [14:0] g5_wa;
    wire [3:0]  g0_ba, g0_ma, g0_sa, g3_ba, g3_ma, g3_sa;
    wire [3:0]  g5_ba, g5_ma, g5_sa;
    wire [4:0]  g2_ba, g2_ma, g2_sa;
    wire [7:0]  g0_la, g2_la, g3_la, g5_la;
    wire g0_ywe, g2_ywe, g3_ywe, g5_ywe;
    wire [8:0]  g0_ya;
    wire [8:0]  g2_ya;
    wire [11:0] g3_ya;
    wire [7:0]  g5_ya;
    wire signed [7:0] g0_yw, g2_yw, g3_yw, g5_yw;
    reg [31:0] xb0, xb2, xb3, xb5;                 // X plane bases
    // serves are WIRES driven by continuous assigns (M0-proven pattern,
    // tb_yolo_conv_core.v:103-108): always @(*) reg serves froze in
    // 10.1c for rarely-changing array indices (dbg4: bd/md/sd stuck at
    // the t=0 X evaluation while per-beat xa/wa serves stayed live)
    wire signed [7:0]  g0_xd, g0_wd, g2_wd, g3_wd, g5_wd;
    wire signed [7:0]  g2_xd, g3_xd, g5_xd;
    wire signed [31:0] g0_bd, g0_md, g2_bd, g2_md, g3_bd, g3_md;
    wire signed [31:0] g5_bd, g5_md;
    wire [7:0]  g0_sd, g2_sd, g3_sd, g5_sd;
    wire signed [7:0] g0_ld, g2_ld, g3_ld, g5_ld;
        integer g0_dn = 0, g2_dn = 0, g3_dn = 0, g5_dn = 0;

    assign g0_xd = imgbyte(xb0 + {24'd0, g0_xa});
    assign g0_wd = $signed(gw0[g0_wa]);
    assign g0_bd = $signed(gb0[g0_ba]);
    assign g0_md = $signed(gm0[g0_ma]);
    assign g0_sd = gs0[g0_sa];
    assign g0_ld = $signed(lut0[g0_la]);
    assign g2_xd = imgbyte(xb2 + {19'd0, g2_xa});
    assign g2_wd = $signed(gw2[g2_wa]);
    assign g2_bd = $signed(gb2[g2_ba]);
    assign g2_md = $signed(gm2[g2_ma]);
    assign g2_sd = gs2[g2_sa];
    assign g2_ld = $signed(lut2[g2_la]);
    assign g3_xd = imgbyte(xb3 + {19'd0, g3_xa});
    assign g3_wd = $signed(gw3[g3_wa]);
    assign g3_bd = $signed(gb3[g3_ba]);
    assign g3_md = $signed(gm3[g3_ma]);
    assign g3_sd = gs3[g3_sa];
    assign g3_ld = $signed(lut3[g3_la]);
    assign g5_xd = imgbyte(xb5 + {19'd0, g5_xa});
    assign g5_wd = $signed(gw5[g5_wa]);
    assign g5_bd = $signed(gb5[g5_ba]);
    assign g5_md = $signed(gm5[g5_ma]);
    assign g5_sd = gs5[g5_sa];
    assign g5_ld = $signed(lut5[g5_la]);

    yolo_conv_core #(.IC(3), .OC(7), .KH(3), .KW(3), .IH(7), .IW(7),
                     .SH(1), .SW(1), .PH(1), .PW(1), .PAD_VAL(8'h00),
                     .HAS_ACT(1), .X_AW(8), .W_AW(8), .Y_AW(9), .P_AW(4))
        u_g0 (.clk_i(clk), .rst_n(rst_n), .start_i(g0_start),
              .busy_o(g0_busy), .done_o(g0_done),
              .x_addr_o(g0_xa), .x_rdata_i(g0_xd),
              .w_addr_o(g0_wa), .w_rdata_i(g0_wd),
              .bias_addr_o(g0_ba), .bias_rdata_i(g0_bd),
              .m_addr_o(g0_ma), .m_rdata_i(g0_md),
              .shift_addr_o(g0_sa), .shift_rdata_i(g0_sd),
              .lut_addr_o(g0_la), .lut_rdata_i(g0_ld),
              .y_we_o(g0_ywe), .y_addr_o(g0_ya), .y_wdata_o(g0_yw));

    yolo_conv_core #(.IC(64), .OC(16), .KH(3), .KW(3), .IH(10), .IW(10),
                     .SH(2), .SW(2), .PH(1), .PW(1), .PAD_VAL(8'h00),
                     .HAS_ACT(1), .X_AW(13), .W_AW(14), .Y_AW(9), .P_AW(5))
        u_g2 (.clk_i(clk), .rst_n(rst_n), .start_i(g2_start),
              .busy_o(g2_busy), .done_o(g2_done),
              .x_addr_o(g2_xa), .x_rdata_i(g2_xd),
              .w_addr_o(g2_wa), .w_rdata_i(g2_wd),
              .bias_addr_o(g2_ba), .bias_rdata_i(g2_bd),
              .m_addr_o(g2_ma), .m_rdata_i(g2_md),
              .shift_addr_o(g2_sa), .shift_rdata_i(g2_sd),
              .lut_addr_o(g2_la), .lut_rdata_i(g2_ld),
              .y_we_o(g2_ywe), .y_addr_o(g2_ya), .y_wdata_o(g2_yw));

    yolo_conv_core #(.IC(16), .OC(9), .KH(2), .KW(2), .IH(17), .IW(17),
                     .SH(1), .SW(1), .PH(0), .PW(0), .PAD_VAL(8'h00),
                     .HAS_ACT(0), .X_AW(13), .W_AW(10), .Y_AW(12), .P_AW(4))
        u_g3 (.clk_i(clk), .rst_n(rst_n), .start_i(g3_start),
              .busy_o(g3_busy), .done_o(g3_done),
              .x_addr_o(g3_xa), .x_rdata_i(g3_xd),
              .w_addr_o(g3_wa), .w_rdata_i(g3_wd),
              .bias_addr_o(g3_ba), .bias_rdata_i(g3_bd),
              .m_addr_o(g3_ma), .m_rdata_i(g3_md),
              .shift_addr_o(g3_sa), .shift_rdata_i(g3_sd),
              .lut_addr_o(g3_la), .lut_rdata_i(g3_ld),
              .y_we_o(g3_ywe), .y_addr_o(g3_ya), .y_wdata_o(g3_yw));

    yolo_conv_core #(.IC(256), .OC(8), .KH(3), .KW(3), .IH(5), .IW(5),
                     .SH(1), .SW(1), .PH(1), .PW(1), .PAD_VAL(8'h80),
                     .HAS_ACT(1), .X_AW(13), .W_AW(15), .Y_AW(8), .P_AW(4))
        u_g5 (.clk_i(clk), .rst_n(rst_n), .start_i(g5_start),
              .busy_o(g5_busy), .done_o(g5_done),
              .x_addr_o(g5_xa), .x_rdata_i(g5_xd),
              .w_addr_o(g5_wa), .w_rdata_i(g5_wd),
              .bias_addr_o(g5_ba), .bias_rdata_i(g5_bd),
              .m_addr_o(g5_ma), .m_rdata_i(g5_md),
              .shift_addr_o(g5_sa), .shift_rdata_i(g5_sd),
              .lut_addr_o(g5_la), .lut_rdata_i(g5_ld),
              .y_we_o(g5_ywe), .y_addr_o(g5_ya), .y_wdata_o(g5_yw));

    // golden Y scatter + done capture (per-instance counters: a shared
    // counter incremented from four always blocks would race on
    // read-modify-write and lose updates)
    integer g0_wr = 0, g2_wr = 0, g3_wr = 0, g5_wr = 0;
    integer g0_db = 0, g2_db = 0, g3_db = 0, g5_db = 0;
    always @(posedge clk) begin
        if (g0_ywe) begin
            g0_wr = g0_wr + 1;
            if (yg[0*YSPAN + g0_ya] === SENT) yg[0*YSPAN + g0_ya] <= g0_yw;
            else g0_db = g0_db + 1;
        end
        if (g0_done) g0_dn = g0_dn + 1;
    end
    always @(posedge clk) begin
        if (g2_ywe) begin
            g2_wr = g2_wr + 1;
            if (yg[2*YSPAN + g2_ya] === SENT) yg[2*YSPAN + g2_ya] <= g2_yw;
            else g2_db = g2_db + 1;
        end
        if (g2_done) g2_dn = g2_dn + 1;
    end
    always @(posedge clk) begin
        if (g3_ywe) begin
            g3_wr = g3_wr + 1;
            if (yg[3*YSPAN + g3_ya] === SENT) yg[3*YSPAN + g3_ya] <= g3_yw;
            else g3_db = g3_db + 1;
        end
        if (g3_done) g3_dn = g3_dn + 1;
    end
    always @(posedge clk) begin
        if (g5_ywe) begin
            g5_wr = g5_wr + 1;
            if (yg[5*YSPAN + g5_ya] === SENT) yg[5*YSPAN + g5_ya] <= g5_yw;
            else g5_db = g5_db + 1;
        end
        if (g5_done) g5_dn = g5_dn + 1;
    end

    // =================================================================
    // main sequence
    // =================================================================
    reg [1023:0] stim = "../stim/m10";
    integer      wdt_ms = 900000;
    integer      n_ldone = 0;
    integer      n_adone = 0;
    integer      total_out = 0;
    integer      n_cmp = 0, n_err = 0, first_err_L = 0;
    integer      first_err_i = 0;
    reg [7:0]    ev, gv;
    reg          got_done;

    // status pulse counters (sampled every cycle: all_done may pulse
    // outside the layer_done sampling points of the main sequence)
    always @(posedge clk) begin
        if (layer_done) n_ldone = n_ldone + 1;
        if (all_done)   n_adone = n_adone + 1;
    end

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin end

        $readmemh({stim, "/n_layers.hex"},  memtmp); n_layers = memtmp[0];
        $readmemh({stim, "/n_ddrwords.hex"},memtmp); n_words  = memtmp[0];
        if (n_words > IMG_WORDS) begin
            $display("TB_GEMM_ARRAY_FAIL (image %0d > %0d)", n_words,
                     IMG_WORDS);
            $finish;
        end
        $readmemh({stim, "/ddr.hex"},   img);
        $readmemh({stim, "/layers.hex"}, lay);
        $readmemh({stim, "/yexp1.hex"}, yexp1);
        $readmemh({stim, "/yexp2.hex"}, yexp2);
        $readmemh({stim, "/gw0.hex"}, gw0);
        $readmemh({stim, "/gb0.hex"}, gb0);
        $readmemh({stim, "/gm0.hex"}, gm0);
        $readmemh({stim, "/gs0.hex"}, gs0);
        $readmemh({stim, "/gw2.hex"}, gw2);
        $readmemh({stim, "/gb2.hex"}, gb2);
        $readmemh({stim, "/gm2.hex"}, gm2);
        $readmemh({stim, "/gs2.hex"}, gs2);
        $readmemh({stim, "/gw3.hex"}, gw3);
        $readmemh({stim, "/gb3.hex"}, gb3);
        $readmemh({stim, "/gm3.hex"}, gm3);
        $readmemh({stim, "/gs3.hex"}, gs3);
        $readmemh({stim, "/gw5.hex"}, gw5);
        $readmemh({stim, "/gb5.hex"}, gb5);
        $readmemh({stim, "/gm5.hex"}, gm5);
        $readmemh({stim, "/gs5.hex"}, gs5);
        // golden LUT snapshots + X bases from the layer table
        for (i = 0; i < 256; i = i + 1) begin
            lut0[i] = imgbyte(lay[0*FLDS+22] + i);
            lut2[i] = imgbyte(lay[2*FLDS+22] + i);
            lut3[i] = imgbyte(lay[3*FLDS+22] + i);
            lut5[i] = imgbyte(lay[5*FLDS+22] + i);
        end
        xb0 = lay[0*FLDS+18];
        xb2 = lay[2*FLDS+18];
        xb3 = lay[3*FLDS+18];
        xb5 = lay[5*FLDS+18];
        // sentinel init
        for (gi = 0; gi < NL_MAX*YSPAN; gi = gi + 1) begin
            yd[gi] = SENT;
            yg[gi] = SENT;
        end
        for (L = 0; L < n_layers; L = L + 1)
            total_out = total_out + lay[L*FLDS+1] * lay[L*FLDS+2];
        $display("[tb] m10 stim=%0s layers=%0d img_words=%0d total_out=%0d",
                 stim, n_layers, n_words, total_out);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        for (L = 0; L < n_layers; L = L + 1) begin
            // inter-layer gap (idle cycles)
            for (i = 0; i < lay[L*FLDS+0]; i = i + 1) @(negedge clk);
            // LUT preload from the image region of this layer
            for (i = 0; i < 256; i = i + 1) begin
                @(negedge clk);
                lut_we    = 1'b1;
                lut_waddr = i[7:0];
                lut_wdata = imgbyte(lay[L*FLDS+22] + i);
            end
            @(negedge clk);
            lut_we = 1'b0;
            // descriptor drive until accept
            @(negedge clk);
            dsc_oc    = lay[L*FLDS+1][OC_AW-1:0];
            dsc_n     = lay[L*FLDS+2][N_AW-1:0];
            dsc_k     = lay[L*FLDS+3][K_AW-1:0];
            dsc_last  = lay[L*FLDS+16][0];
            dsc_ih    = lay[L*FLDS+4][15:0];
            dsc_iw    = lay[L*FLDS+5][15:0];
            dsc_ow    = lay[L*FLDS+6][15:0];
            dsc_ic    = lay[L*FLDS+7][15:0];
            dsc_kh    = lay[L*FLDS+8][7:0];
            dsc_kw    = lay[L*FLDS+9][7:0];
            dsc_sh    = lay[L*FLDS+10][7:0];
            dsc_sw    = lay[L*FLDS+11][7:0];
            dsc_ph    = lay[L*FLDS+12][7:0];
            dsc_pw    = lay[L*FLDS+13][7:0];
            dsc_first = lay[L*FLDS+14][0];
            dsc_act   = lay[L*FLDS+15][0];
            dsc_wbase = lay[L*FLDS+17];
            dsc_xbase = lay[L*FLDS+18];
            dsc_bbase = lay[L*FLDS+19];
            dsc_mbase = lay[L*FLDS+20];
            dsc_sbase = lay[L*FLDS+21];
            dsc_valid = 1'b1;
            // ready sampled at negedges (stable within the cycle: it is a
            // function of registers only, and all TB drives happen at
            // negedges) -- the first posedge after loop exit is the one
            // and only accept edge
            while (dsc_ready !== 1'b1) @(negedge clk);
            @(posedge clk);            // accept edge
            @(negedge clk);
            dsc_valid = 1'b0;
            // golden start (synthetic layers only)
            case (L)
                0: g0_start = 1'b1;
                2: g2_start = 1'b1;
                3: g3_start = 1'b1;
                5: g5_start = 1'b1;
                default: ;
            endcase
            @(negedge clk);
            g0_start = 1'b0;
            g2_start = 1'b0;
            g3_start = 1'b0;
            g5_start = 1'b0;
            // wait layer_done pulse (sampled post-edge)
            got_done = 1'b0;
            while (!got_done) begin
                @(posedge clk);
                #1;
                got_done = layer_done;
            end
            $display("[tb] layer %0d done @t=%0t (oc=%0d n=%0d k=%0d)",
                     L, $time, lay[L*FLDS+1], lay[L*FLDS+2], lay[L*FLDS+3]);
            // drain: last y write trails the last rq beat by 3 cycles;
            // retag the scatter span only after the drain window
            repeat (8) @(negedge clk);
            cur_layer = L + 1;
        end

        // final wait: all golden cores finished + tail drain
        while (g0_dn == 0 || g2_dn == 0 || g3_dn == 0 || g5_dn == 0)
            @(posedge clk);
        repeat (16) @(negedge clk);

        // ---- compare ----
        for (L = 0; L < n_layers; L = L + 1) begin
            for (i = 0; i < lay[L*FLDS+1]*lay[L*FLDS+2]; i = i + 1) begin
                ev = yd[L*YSPAN + i];
                n_cmp = n_cmp + 1;
                if (ev === SENT) begin
                    // 0xA5 is a legal output value: a DUT write of 0xA5 is
                    // indistinguishable from "never written". Invariants
                    // (checked in PASS): dut_wr==total_out && dbl==0 imply
                    // every cell written exactly once, and gold_wr==oc*n &&
                    // gdbl==0 imply the golden covered every cell -- so
                    // gold-side 0xA5 means the DUT value matches. Flag only
                    // when the reference value differs.
                    if (lay[L*FLDS+23] == 0)
                        gv = yg[L*YSPAN + i];
                    else if (lay[L*FLDS+23] == 1)
                        gv = yexp1[i];
                    else
                        gv = yexp2[i];
                    if (gv !== 8'hA5) begin
                        n_err = n_err + 1;
                        n_ybad = n_ybad + 1;
                    end
                    if (n_err == 1) begin
                        first_err_L = L;
                        first_err_i = i;
                    end
                end else if (lay[L*FLDS+23] == 0) begin
                    gv = yg[L*YSPAN + i];
                    if (gv !== ev) begin
                        n_err = n_err + 1;
                        if (n_err == 1) begin
                            first_err_L = L;
                            first_err_i = i;
                            $display("[tb] first diff L=%0d i=%0d dut=%0d gold=%0d",
                                     L, i, ev, gv);
                        end
                    end
                end else if (lay[L*FLDS+23] == 1) begin
                    if (yexp1[i] !== ev) begin
                        n_err = n_err + 1;
                        if (n_err == 1)
                            $display("[tb] first diff L=%0d i=%0d dut=%0d exp=%0d",
                                     L, i, ev, yexp1[i]);
                    end
                end else begin
                    if (yexp2[i] !== ev) begin
                        n_err = n_err + 1;
                        if (n_err == 1)
                            $display("[tb] first diff L=%0d i=%0d dut=%0d exp=%0d",
                                     L, i, ev, yexp2[i]);
                    end
                end
            end
        end

        if (n_err == 0 && n_dbl == 0 && n_ybad == 0
            && (g0_db + g2_db + g3_db + g5_db) == 0
            && n_ywr == total_out
            && (g0_wr + g2_wr + g3_wr + g5_wr) == 343 + 400 + 2304 + 200
            && n_ldone == n_layers && n_adone == 1) begin
            $display("TB_GEMM_ARRAY_PASS layers=%0d compared=%0d dut_wr=%0d gold_wr=%0d ldone=%0d adone=%0d",
                     n_layers, n_cmp, n_ywr,
                     g0_wr + g2_wr + g3_wr + g5_wr, n_ldone, n_adone);
        end else begin
            $display("TB_GEMM_ARRAY_FAIL err=%0d dbl=%0d gdbl=%0d unwritten=%0d dut_wr=%0d(exp %0d) gold_wr=%0d ldone=%0d adone=%0d",
                     n_err, n_dbl, g0_db + g2_db + g3_db + g5_db, n_ybad,
                     n_ywr, total_out, g0_wr + g2_wr + g3_wr + g5_wr,
                     n_ldone, n_adone);
        end
        $finish;
    end

    // heartbeat + watchdog
    always #10_000_000
        $display("[tb] heartbeat t=%0t cur_layer=%0d ywr=%0d", $time,
                 cur_layer, n_ywr);
    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_GEMM_ARRAY_FAIL (timeout) t=%0t cur_layer=%0d ywr=%0d",
                 $time, cur_layer, n_ywr);
        $finish;
    end

endmodule
