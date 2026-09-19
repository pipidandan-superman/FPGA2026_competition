/************************************************************************
 * File Name       : tb_yolo_fullnet.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_fullnet
 * Description     : M11 gate testbench: full-network end-to-end on the
 *                   SIM-8x8 GEMM array, 1 frame (golden_00 = run04
 *                   regression_128frames[0], images89).
 *
 *                   The TB plays the PS role. One DDR mirror image
 *                   (ddr.hex, 64-bit LE words, 1.665M words = 13.3MB)
 *                   holds every buffer region (104), every layer's
 *                   KPAD-padded W rows + bias/M/shift blocks and every
 *                   layer's golden expected bytes (CHW). A compiled
 *                   micro-op program (prog.hex, M10 28-token conv rows
 *                   + PS byte ops) drives:
 *                     CONV   -> descriptor on yolo_gemm_array; X served
 *                               combinationally from the mirror; Y comes
 *                               back over the DUT's true AXI4 write
 *                               master (V1.2) -- a write slave BFM (random
 *                               aw/w stalls, random B delay, protocol
 *                               guards) scatters every strobed W byte
 *                               INTO the mirror at its physical address
 *                               (word RMW; dsc_ybase driven from the
 *                               program word, so the landing address ==
 *                               the y_base+y_addr of the V1.0 gate);
 *                               per-layer compare vs the golden region
 *                               (0xA5 ambiguity rule + write-bijection
 *                               counts)
 *                     COPY/RSCL/ADD/MAXP5/UPS2 -> PS integer semantics
 *                               on mirror bytes, bit-exact to
 *                               pynq/intarith.py (rne_shift/sat_i8/
 *                               sat_i32/maxpool5/upsample_nearest2)
 *                     HEADS  -> dump the 6 head buffers (regs[0..2] +
 *                               clss[0..2], int8) to a file; the gate
 *                               closes post-run: sha256(dump) ==
 *                               run04 raw_head_sha256 (9ce70525...)
 *
 *                   Gate token: TB_FULLNET_PASS (full 63 convs) /
 *                   TB_FULLNET_SMOKE (+MAXCONV<N bring-up) / _FAIL.
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vlog -work work_arr ..\..\rtl\yolo_gemm_array.v (+M1-M9 rtl)
 *                          ..\tb_yolo_fullnet.v
 *                     vsim -c -novopt +STIM=../stim/m11 +WDT_MS=3600000 \
 *                          -do "run -all; quit -f" work_arr.tb_yolo_fullnet
 * Dependencies    : rtl/yolo_gemm_array.v (V1.2a, + M1-M9 chain), sim/
 *                   m11_vecgen.py outputs (stim/m11/*)
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M11)
 *   - V1.1 (2026-09-16) by LSL : DUT V1.2a 接口承接——y_we/y_addr/y_wdata
 *                 观测口换 AXI4 写从 BFM（aw/w 随机停停 + B 随机延迟，
 *                 协议哨兵：对齐/size/burst/wlast/超拍/单在途；散写按
 *                 物理地址 RMW 进 img 镜像，wrmap 键 = 物理地址 −
 *                 cur_ybase）；新增 dsc_ybase 驱动 = prog[pc+1+24]（与
 *                 V1.0 的 cur_ybase 同源同值，落点逐位一致）。layer_done
 *                 已被 DUT 排空门控（V1.2a 含在途清零），层尾等待语义
 *                 不变。prog.hex/镜像布局零改动。
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_fullnet;

    // ---- DUT geometry (matches yolo_gemm_array defaults) ----
    localparam OC_EDGE   = 8;
    localparam N_EDGE    = 8;
    localparam OC_AW     = 11;
    localparam N_AW      = 16;
    localparam K_AW      = 12;
    localparam ADDR_W    = 32;
    localparam FLDS      = 28;        // tokens per conv row (M10 format)
    localparam IMG_WORDS = 1670000;   // >= n_ddrwords.hex (1665001)
    localparam PROG_MAX  = 4096;      // >= n_prog.hex (2178)
    localparam LUT_MAX   = 16128;     // 63 x 256
    localparam WRMAX     = 409600;    // >= max oc*n (model.0 16x25600)
    localparam SENT      = 8'hA5;

    // opcodes (m11_vecgen.py contract)
    localparam [31:0] OP_END    = 32'd0;
    localparam [31:0] OP_CONV   = 32'd1;
    localparam [31:0] OP_COPY   = 32'd2;
    localparam [31:0] OP_RSCL   = 32'd3;
    localparam [31:0] OP_ADD    = 32'd4;
    localparam [31:0] OP_MAXP5  = 32'd5;
    localparam [31:0] OP_UPS2   = 32'd6;
    localparam [31:0] OP_HEADS  = 32'd7;

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

    // ---- X plane / LUT preload ----
    wire [ADDR_W-1:0]    x_addr;
    reg  [7:0]           x_rdata;
    reg                  lut_we = 1'b0;
    reg  [7:0]           lut_waddr = 0, lut_wdata = 0;
    reg  [ADDR_W-1:0]    dsc_ybase = 0;
    wire                 layer_done, all_done, busy;

    // ---- Y AXI4 write master (DUT V1.2a) ----
    wire [ADDR_W-1:0]    awaddr;
    wire [7:0]           awlen;
    wire [2:0]           awsize;
    wire [1:0]           awburst;
    wire                 awvalid;
    wire                 awready;
    wire [63:0]          wdata;
    wire [7:0]           wstrb;
    wire                 wlast;
    wire                 wvalid;
    wire                 wready;
    wire                 bvalid;
    wire [1:0]           bresp;
    wire                 bready;

    // ---- stimulus memories ----
    reg [63:0]           img  [0:IMG_WORDS-1];   // DDR mirror
    reg [31:0]           prog [0:PROG_MAX-1];    // micro-op program
    reg [7:0]            lutall [0:LUT_MAX-1];   // 63 x 256B LUT slices
    reg [31:0]           memtmp [0:0];
    integer              n_words, n_prog;

    // ---- per-conv write map (sentinel-free bijection check) ----
    reg                  wrmap [0:WRMAX-1];

    // ---- stats ----
    integer              n_ywr = 0, n_dbl = 0, n_ybad = 0, n_yerr = 0;
    integer              n_ldone = 0, n_adone = 0;
    integer              n_cmp = 0, n_err = 0;
    integer              first_err_c = 0, first_err_i = 0;

    // ---- image byte access helper (M10 proven) ----
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
        .dsc_ybase_i  (dsc_ybase),
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
        // ---- Y write master (DUT V1.2a) ----
        .awaddr_o     (awaddr),
        .awlen_o      (awlen),
        .awsize_o     (awsize),
        .awburst_o    (awburst),
        .awvalid_o    (awvalid),
        .awready_i    (awready),
        .wdata_o      (wdata),
        .wstrb_o      (wstrb),
        .wlast_o      (wlast),
        .wvalid_o     (wvalid),
        .wready_i     (wready),
        .bvalid_i     (bvalid),
        .bresp_i      (bresp),
        .bready_o     (bready),
        .x_addr_o     (x_addr),
        .x_rdata_i    (x_rdata),
        .lut_we_i     (lut_we),
        .lut_waddr_i  (lut_waddr),
        .lut_wdata_i  (lut_wdata),
        .layer_done_o (layer_done),
        .all_done_o   (all_done),
        .busy_o       (busy)
    );

    // X plane comb serve (byte lane from the mirror word; M10-proven
    // always@(*) pattern with imgbyte, tb_yolo_gemm_array.v:198)
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

    // rdata served combinationally from the mirror (word-aligned bursts)
    always @(*) rdata = img[raddr_q[31:3]];

    // ---- DUT Y write slave BFM + scatter INTO the mirror ----
    // (M11: physical chaining -- the written bytes ARE the data plane the
    // next op consumes. DUT V1.2a emits Y as per-row write commands; the
    // BFM accepts bursts with random aw/w stalls and random B delay,
    // guard the protocol (alignment, size/burst, wlast position, beat
    // overrun, single outstanding) and RMWs every strobed beat into the
    // mirror as ONE merged word (each beat = one aligned 8-byte word;
    // per-lane writes to the same word would lose all but the last
    // lane). wrmap key = physical - cur_ybase gives the single-write
    // bijection check without poisoning the mirror with sentinels; a
    // conv's Y writes all land before its drain-gated layer_done, so
    // cur_ybase is live.)
    integer       cur_ybase = 0;
    wire          yaw_stall_w = (lfsr[7:4]  == 4'h0);
    wire          yw_stall_w  = (lfsr[11:8] == 4'h0);
    wire [1:0]    ybgap_w     = lfsr[13:12];

    reg              yaw_busy = 1'b0;   // AW accepted, W incomplete
    reg [ADDR_W-1:0] yaw_addr = 0;
    reg [7:0]        yaw_len  = 8'd0;   // latched awlen
    reg [7:0]        yaw_beat = 8'd0;   // beats fired in this burst
    assign awready = ~yaw_busy && ~yaw_stall_w;
    assign wready  = yaw_busy && ~yw_stall_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            yaw_busy <= 1'b0;
            yaw_len  <= 8'd0;
            yaw_beat <= 8'd0;
        end else if (awvalid && awready) begin
            yaw_busy <= 1'b1;
            yaw_addr <= awaddr;
            yaw_len  <= awlen;
            yaw_beat <= 8'd0;
        end else if (wvalid && wready) begin
            if (wlast) yaw_busy <= 1'b0;
            yaw_beat  <= yaw_beat + 8'd1;
        end
    end

    // B response engine: one per burst, random delay, in order
    reg [3:0] yb_pend = 4'd0;
    reg [1:0] yb_wait = 2'd0;
    wire      ywlast_fire = yaw_busy && wvalid && wready && wlast;
    assign bvalid = (yb_pend != 4'd0) && (yb_wait == 2'd0);
    assign bresp  = 2'b00;                  // OKAY only

    integer ytmp_p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            yb_pend <= 4'd0;
            yb_wait <= 2'd0;
        end else begin
            ytmp_p = yb_pend;
            if (yb_wait != 2'd0) yb_wait <= yb_wait - 2'd1;
            if (ywlast_fire) begin
                ytmp_p = ytmp_p + 1;
                if (ytmp_p == 1) yb_wait <= ybgap_w;
            end
            if (bvalid && bready) begin
                ytmp_p = ytmp_p - 1;
                if (ytmp_p != 0) yb_wait <= ybgap_w;
            end
            yb_pend <= ytmp_p;
        end
    end

    // W monitor + RMW scatter (protocol guards; strobed -> mirror)
    integer  jw;
    integer  yb_key;
    reg [ADDR_W-1:0] yb_wa;
    reg [63:0]       yb_word;
    always @(posedge clk) begin
        if (rst_n) begin
            if (awvalid && awready) begin
                // yaw_busy reads its pre-edge value (NBA above) =
                // single-outstanding check
                if (awaddr[2:0] !== 3'b000) begin
                    n_yerr = n_yerr + 1;
                    $display("[tb] ERR Y AW not aligned: %h", awaddr);
                end
                if (awsize !== 3'd3 || awburst !== 2'd1) begin
                    n_yerr = n_yerr + 1;
                    $display("[tb] ERR Y AW size/burst %0d/%0d",
                             awsize, awburst);
                end
                if (yaw_busy) begin
                    n_yerr = n_yerr + 1;
                    $display("[tb] ERR Y AW while burst in flight");
                end
            end
            if (wvalid && wready) begin
                if (wlast !== (yaw_beat == yaw_len)) begin
                    n_yerr = n_yerr + 1;
                    $display("[tb] ERR Y wlast@beat %0d of %0d",
                             yaw_beat + 8'd1, yaw_len + 8'd1);
                end
                if (yaw_beat > yaw_len) begin
                    n_yerr = n_yerr + 1;
                    $display("[tb] ERR Y W overrun: beat %0d of %0d",
                             yaw_beat + 8'd1, yaw_len + 8'd1);
                end
                // one W beat covers exactly ONE 8-byte aligned word
                // (awaddr is aligned and beats step whole words): merge
                // every strobed lane into a SINGLE word NBA -- per-lane
                // NBAs to the same word keep only the last lane (run03
                // smoke bug: 7/8 bytes lost per full word, acc_err
                // 357407/409600 on conv 0)
                yb_wa   = yaw_addr + {24'd0, yaw_beat, 3'b000};
                yb_word = img[yb_wa[31:3]];
                for (jw = 0; jw < 8; jw = jw + 1) begin
                    if (wstrb[jw]) begin
                        yb_word[8*jw +: 8] = wdata[8*jw +: 8];
                        yb_key = yb_wa + jw - cur_ybase;
                        n_ywr = n_ywr + 1;
                        if (wrmap[yb_key] === 1'b0) begin
                            wrmap[yb_key] <= 1'b1;
                        end else begin
                            n_dbl = n_dbl + 1;
                            if (n_dbl == 1)
                                $display("[tb] ERROR double DUT write addr=%0d",
                                         yb_wa + jw);
                        end
                    end
                end
                img[yb_wa[31:3]] <= yb_word;
            end
        end
    end

    // status pulse counters
    always @(posedge clk) begin
        if (layer_done) n_ldone = n_ldone + 1;
        if (all_done)   n_adone = n_adone + 1;
    end

    // =================================================================
    // PS-role integer helpers (bit-exact to pynq/intarith.py)
    // =================================================================
    // rne_shift: divide int64 by 2^s, round-to-nearest-even (ties away
    // from zero only when the quotient is odd). s==0 identity, s<0 left.
    function signed [63:0] rne64;
        input signed [63:0] n;
        input integer       s;
        reg signed [63:0] q, rem, twice, full;
        begin
            if (s == 0) begin
                rne64 = n;
            end else if (s < 0) begin
                rne64 = n <<< (-s);
            end else begin
                q     = n >>> s;
                rem   = n - (q <<< s);
                twice = rem <<< 1;
                full  = 64'sd1 <<< s;
                if (twice > full)
                    q = q + 64'sd1;
                else if (twice < -full)
                    q = q - 64'sd1;
                else if (((twice == full) || (twice == -full))
                         && (q[0] == 1'b1))
                    q = q + (twice > 0 ? 64'sd1 : -64'sd1);
                rne64 = q;
            end
        end
    endfunction

    function signed [63:0] sat32x;
        input signed [63:0] x;
        begin
            if (x > 64'sd2147483647)          sat32x = 64'sd2147483647;
            else if (x < -(64'sd1 <<< 31))    sat32x = -(64'sd1 <<< 31);
            else                              sat32x = x;
        end
    endfunction

    function signed [7:0] sat8x;
        input signed [63:0] x;
        begin
            if (x > 64'sd127)                 sat8x = 8'sd127;
            else if (x < -64'sd128)           sat8x = -8'sd128;
            else                              sat8x = x[7:0];
        end
    endfunction

    // mirror byte write (blocking RMW; PS ops run procedurally while the
    // DUT is idle -- no clocked writer is active)
    task mput;
        input [31:0] a;
        input [7:0]  d;
        reg [5:0]    sh;
        begin
            sh = {a[2:0], 3'b000};
            img[a[31:3]] = (img[a[31:3]] & ~(64'hFF << sh))
                           | ({56'd0, d} << sh);
        end
    endtask

    // sign-extended byte at mirror address
    function signed [63:0] sbyte64;
        input [31:0] a;
        reg [7:0] b;
        begin
            b = imgbyte(a);
            sbyte64 = {{56{b[7]}}, b};
        end
    endfunction

    task t_copy;   // OP_COPY: dst[0..ln) = src[0..ln)
        input integer dst, src, ln;
        integer i;
        begin
            for (i = 0; i < ln; i = i + 1)
                mput(dst + i, imgbyte(src + i));
        end
    endtask

    task t_rscl;   // OP_RSCL: sat_i8(rne(v * M, s)); M==0&&s==0 -> zeros
        input integer dst, src, ln;
        input [31:0]  mu;
        input integer s;
        reg signed [63:0] m;
        integer i;
        begin
            m = {{32{mu[31]}}, mu};
            for (i = 0; i < ln; i = i + 1) begin
                if (m == 0 && s == 0)
                    mput(dst + i, 8'h00);
                else
                    mput(dst + i, sat8x(rne64(sbyte64(src + i) * m, s)));
            end
        end
    endtask

    task t_add;    // OP_ADD: sat_i8(sat_i32(rne(a*Ma,sa)+rne(b*Mb,sb)))
        input integer dst, asrc, bsrc, ln;
        input [31:0]  mau;
        input integer sa;
        input [31:0]  mbu;
        input integer sb;
        reg signed [63:0] ma, mb;
        integer i;
        begin
            ma = {{32{mau[31]}}, mau};
            mb = {{32{mbu[31]}}, mbu};
            for (i = 0; i < ln; i = i + 1)
                mput(dst + i,
                     sat8x(sat32x(rne64(sbyte64(asrc + i) * ma, sa)
                                  + rne64(sbyte64(bsrc + i) * mb, sb))));
        end
    endtask

    task t_maxp5;  // OP_MAXP5: 5x5 s1 p(-128) maxpool, out HxW = in HxW
        input integer dst, src, c, h, w;
        integer ci, oh, ow, ki, kj, ih, iw;
        reg signed [7:0] best, v;
        begin
            for (ci = 0; ci < c; ci = ci + 1)
                for (oh = 0; oh < h; oh = oh + 1)
                    for (ow = 0; ow < w; ow = ow + 1) begin
                        best = -8'sd128;
                        for (ki = 0; ki < 5; ki = ki + 1)
                            for (kj = 0; kj < 5; kj = kj + 1) begin
                                ih = oh + ki - 2;
                                iw = ow + kj - 2;
                                if (ih >= 0 && ih < h && iw >= 0 && iw < w)
                                    v = $signed(imgbyte(
                                        src + (ci*h + ih)*w + iw));
                                else
                                    v = -8'sd128;
                                if (v > best) best = v;
                            end
                        mput(dst + (ci*h + oh)*w + ow, best);
                    end
        end
    endtask

    task t_ups2;   // OP_UPS2: 2x nearest upsample (H,W -> 2H,2W)
        input integer dst, src, c, h, w;
        integer ci, i, j, di, dj;
        reg [7:0] v;
        begin
            for (ci = 0; ci < c; ci = ci + 1)
                for (i = 0; i < h; i = i + 1)
                    for (j = 0; j < w; j = j + 1) begin
                        v = imgbyte(src + (ci*h + i)*w + j);
                        for (di = 0; di < 2; di = di + 1)
                            for (dj = 0; dj < 2; dj = dj + 1)
                                mput(dst + (ci*(2*h) + 2*i + di)*(2*w)
                                         + 2*j + dj, v);
                    end
        end
    endtask

    // =================================================================
    // main sequence
    // =================================================================
    reg [1023:0] stim = "../stim/m11";
    reg [1023:0] dumpf = "head_dump.bin";
    integer      wdt_ms = 3600000;
    time         wdt_del = 0;
    integer      maxconv = 63;
    integer      pc, opword;
    integer      convs_run = 0, ps_ops = 0, head_bytes = 0;
    integer      total_out = 0, tot, yb, gb, i, fd, nt, k, b0, ln;
    reg          got_done, done_early;
    reg [7:0]    ev, gv;

    initial begin
        if ($value$plusargs("STIM=%s", stim))    begin end
        if ($value$plusargs("WDT_MS=%d", wdt_ms))begin end
        if ($value$plusargs("MAXCONV=%d", maxconv)) begin end
        if ($value$plusargs("DUMPF=%s", dumpf))  begin end

        $readmemh({stim, "/n_ddrwords.hex"}, memtmp); n_words = memtmp[0];
        $readmemh({stim, "/n_prog.hex"},     memtmp); n_prog  = memtmp[0];
        if (n_words > IMG_WORDS) begin
            $display("TB_FULLNET_FAIL (image %0d > %0d)", n_words,
                     IMG_WORDS);
            $finish;
        end
        if (n_prog > PROG_MAX) begin
            $display("TB_FULLNET_FAIL (prog %0d > %0d)", n_prog, PROG_MAX);
            $finish;
        end
        $readmemh({stim, "/ddr.hex"},     img);
        $readmemh({stim, "/prog.hex"},    prog);
        $readmemh({stim, "/lut_all.hex"}, lutall);
        $display("[tb] m11 stim=%0s img_words=%0d prog_words=%0d maxconv=%0d",
                 stim, n_words, n_prog, maxconv);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // ---- micro-op program execution ----
        pc = 0;
        done_early = 1'b0;
        while (!done_early && prog[pc] !== OP_END) begin
            opword = prog[pc];
            if (opword == OP_CONV) begin
                if (convs_run >= maxconv) begin
                    done_early = 1'b1;
                end else begin
                    @(negedge clk);
                    // clear this layer's write map
                    tot = prog[pc+1+1] * prog[pc+1+2];  // oc * n
                    for (i = 0; i < tot; i = i + 1) wrmap[i] = 1'b0;
                    // inter-layer gap (token0; 0 in this program)
                    for (i = 0; i < prog[pc+1+0]; i = i + 1)
                        @(negedge clk);
                    // LUT preload from lutall[lut_idx*256 + i]
                    for (i = 0; i < 256; i = i + 1) begin
                        @(negedge clk);
                        lut_we    = 1'b1;
                        lut_waddr = i[7:0];
                        lut_wdata = lutall[prog[pc+1+22]*256 + i];
                    end
                    @(negedge clk);
                    lut_we = 1'b0;
                    // descriptor drive until accept (M10 handshake)
                    @(negedge clk);
                    dsc_oc    = prog[pc+1+1][OC_AW-1:0];
                    dsc_n     = prog[pc+1+2][N_AW-1:0];
                    dsc_k     = prog[pc+1+3][K_AW-1:0];
                    dsc_last  = (convs_run == maxconv - 1);
                    dsc_ih    = prog[pc+1+4][15:0];
                    dsc_iw    = prog[pc+1+5][15:0];
                    dsc_ow    = prog[pc+1+6][15:0];
                    dsc_ic    = prog[pc+1+7][15:0];
                    dsc_kh    = prog[pc+1+8][7:0];
                    dsc_kw    = prog[pc+1+9][7:0];
                    dsc_sh    = prog[pc+1+10][7:0];
                    dsc_sw    = prog[pc+1+11][7:0];
                    dsc_ph    = prog[pc+1+12][7:0];
                    dsc_pw    = prog[pc+1+13][7:0];
                    dsc_first = prog[pc+1+14][0];
                    dsc_act   = prog[pc+1+15][0];
                    dsc_wbase = prog[pc+1+17];
                    dsc_xbase = prog[pc+1+18];
                    dsc_bbase = prog[pc+1+19];
                    dsc_mbase = prog[pc+1+20];
                    dsc_sbase = prog[pc+1+21];
                    cur_ybase = prog[pc+1+24];
                    dsc_ybase = cur_ybase;  // DUT V1.2a: same program word
                                            // as the TB-side base -- the
                                            // landing addresses equal the
                                            // V1.0 y_base + y_addr exactly
                    dsc_valid = 1'b1;
                    while (dsc_ready !== 1'b1) @(negedge clk);
                    @(posedge clk);            // accept edge
                    @(negedge clk);
                    dsc_valid = 1'b0;
                    // wait layer_done pulse (sampled post-edge)
                    got_done = 1'b0;
                    while (!got_done) begin
                        @(posedge clk);
                        #1;
                        got_done = layer_done;
                    end
                    // layer_done is drain-gated in DUT V1.2a (segmenter
                    // idle + zero in-flight + last B collected), so every
                    // Y byte has landed in the mirror at the pulse; keep
                    // a short tail anyway before the per-conv compare
                    repeat (8) @(negedge clk);
                    // per-conv compare: mirror[y_base+i] vs golden region
                    yb = prog[pc+1+24];
                    gb = prog[pc+1+25];
                    for (i = 0; i < tot; i = i + 1) begin
                        n_cmp = n_cmp + 1;
                        if (wrmap[i] === 1'b0) begin
                            // 0xA5 is a legal output value (M10 lesson):
                            // unwritten cell is an error only when the
                            // reference byte differs from 0xA5
                            if (imgbyte(gb + i) !== SENT) begin
                                n_err = n_err + 1;
                                n_ybad = n_ybad + 1;
                            end
                        end else begin
                            ev = imgbyte(yb + i);
                            gv = imgbyte(gb + i);
                            if (ev !== gv) begin
                                n_err = n_err + 1;
                                if (n_err == 1) begin
                                    first_err_c = convs_run;
                                    first_err_i = i;
                                    $display("[tb] first diff conv=%0d i=%0d dut=%0d gold=%0d",
                                             convs_run, i, ev, gv);
                                end
                            end
                        end
                    end
                    total_out = total_out + tot;
                    $display("[tb] conv %0d/%0d task=%0d done @t=%0t oc=%0d n=%0d k=%0d acc_err=%0d",
                             convs_run, maxconv, prog[pc+1+26], $time,
                             prog[pc+1+1], prog[pc+1+2], prog[pc+1+3],
                             n_err);
                    convs_run = convs_run + 1;
                    pc = pc + 1 + FLDS;
                end
            end else if (opword == OP_COPY) begin
                @(negedge clk);
                t_copy(prog[pc+1], prog[pc+2], prog[pc+3]);
                ps_ops = ps_ops + 1;
                pc = pc + 4;
            end else if (opword == OP_RSCL) begin
                @(negedge clk);
                t_rscl(prog[pc+1], prog[pc+2], prog[pc+3],
                       prog[pc+4], prog[pc+5]);
                ps_ops = ps_ops + 1;
                pc = pc + 6;
            end else if (opword == OP_ADD) begin
                @(negedge clk);
                t_add(prog[pc+1], prog[pc+2], prog[pc+3], prog[pc+4],
                      prog[pc+5], prog[pc+6], prog[pc+7], prog[pc+8]);
                ps_ops = ps_ops + 1;
                pc = pc + 9;
            end else if (opword == OP_MAXP5) begin
                @(negedge clk);
                t_maxp5(prog[pc+1], prog[pc+2], prog[pc+3],
                        prog[pc+4], prog[pc+5]);
                ps_ops = ps_ops + 1;
                pc = pc + 6;
            end else if (opword == OP_UPS2) begin
                @(negedge clk);
                t_ups2(prog[pc+1], prog[pc+2], prog[pc+3],
                       prog[pc+4], prog[pc+5]);
                ps_ops = ps_ops + 1;
                pc = pc + 6;
            end else if (opword == OP_HEADS) begin
                @(negedge clk);
                nt = prog[pc+1];
                fd = $fopen(dumpf, "wb");
                head_bytes = 0;
                for (k = 0; k < nt; k = k + 1) begin
                    b0 = prog[pc+2+2*k];
                    ln = prog[pc+3+2*k];
                    for (i = 0; i < ln; i = i + 1) begin
                        $fwrite(fd, "%c", imgbyte(b0 + i));
                        head_bytes = head_bytes + 1;
                    end
                end
                $fclose(fd);
                $display("[tb] heads dumped %0d bytes -> %0s",
                         head_bytes, dumpf);
                pc = pc + 2 + 2*nt;
            end else begin
                $display("TB_FULLNET_FAIL (bad opcode %0d @pc=%0d)",
                         opword, pc);
                $finish;
            end
        end

        repeat (16) @(negedge clk);

        // ---- verdict ----
        if (n_err == 0 && n_dbl == 0 && n_ybad == 0 && n_yerr == 0
            && n_ywr == total_out
            && n_ldone == convs_run && n_adone == 1
            && convs_run == maxconv
            && (maxconv < 63 || (ps_ops == 65 && head_bytes == 149100))) begin
            if (maxconv == 63)
                $display("TB_FULLNET_PASS convs=%0d psops=%0d compared=%0d dut_wr=%0d head_bytes=%0d ldone=%0d adone=%0d",
                         convs_run, ps_ops, n_cmp, n_ywr, head_bytes,
                         n_ldone, n_adone);
            else
                $display("TB_FULLNET_SMOKE convs=%0d psops=%0d compared=%0d dut_wr=%0d head_bytes=%0d ldone=%0d adone=%0d",
                         convs_run, ps_ops, n_cmp, n_ywr, head_bytes,
                         n_ldone, n_adone);
        end else begin
            $display("TB_FULLNET_FAIL err=%0d dbl=%0d unwritten=%0d yaxi=%0d dut_wr=%0d(exp %0d) convs=%0d(exp %0d) psops=%0d head_bytes=%0d ldone=%0d adone=%0d first=(c%0d,i%0d)",
                     n_err, n_dbl, n_ybad, n_yerr, n_ywr, total_out,
                     convs_run, maxconv, ps_ops, head_bytes, n_ldone, n_adone,
                     first_err_c, first_err_i);
        end
        $finish;
    end

    // heartbeat + watchdog (WDT delay in 64-bit time: wdt_ms*1e6
    // overflows 32-bit integer arithmetic -- run01 died at 817,405,952 ns
    // = 3.6e12 mod 2^32; M10's 9e8 never tripped it)
    always #10_000_000
        $display("[tb] heartbeat t=%0t conv=%0d ywr=%0d ps=%0d err=%0d",
                 $time, convs_run, n_ywr, ps_ops, n_err);
    initial begin
        wdt_del = wdt_ms;
        wdt_del = wdt_del * 1000000;
        #wdt_del;
        $display("TB_FULLNET_FAIL (timeout) t=%0t conv=%0d ywr=%0d ps=%0d",
                 $time, convs_run, n_ywr, ps_ops);
        $finish;
    end

endmodule
