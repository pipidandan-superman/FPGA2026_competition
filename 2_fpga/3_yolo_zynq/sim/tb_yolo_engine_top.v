/************************************************************************
 * File Name       : tb_yolo_engine_top.v
 * Developer       : LSL
 * Date            : 2026-09-16
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_engine_top
 * Description     : M12 A1 CSR/engine gate testbench (SIM 8x8 build of
 *                   yolo_engine_top). Stimulus and the golden chain are
 *                   the M10 gate set VERBATIM (stim/m10: 6-layer plan
 *                   S1/R1/S2/S3/R2/S4, layers.hex 28 tokens/layer, one
 *                   DDR byte image backing the AXI read BFM / X comb
 *                   port / LUT preload / golden memories, 4 static
 *                   yolo_conv_core goldens + run04 real-layer exports).
 *
 *                   What changes vs the M10 TB: the PS role moves onto
 *                   the real control path -- an AXI4-Lite master BFM
 *                   (task-driven, negedge drives / negedge polls on
 *                   register-function readys) programs the CSR exactly
 *                   the way v1 software will:
 *                     - LUT preload via the 0x400 window (256 writes)
 *                     - DESC0..DESC5 + 6 BASE regs, DESC0 readback
 *                     - CTRL.START doorbell, STATUS.dsc_pend accept
 *                       wait, STATUS.ldone_cnt drain-gated completion
 *                       poll, final all_done sticky poll
 *                     - ID/VER + 12-shadow pattern roundtrip at t0,
 *                       IRQ_EN/IRQ_STAT raise + W1C at frame end
 *                   ldone/adone are now COUNTED THROUGH THE CSR (final
 *                   STATUS snapshot), not TB pulse counters -- the PS
 *                   visible view is what the gate asserts.
 *
 *                   Y check identical to M10 TB V1.1: AXI write slave
 *                   BFM scatters strobed bytes into yd at physical
 *                   addresses; YBASE reg = L*YSPAN so the mirror
 *                   layout is bit-identical to the M10/M11 gates.
 *                   Gate token: TB_CSR_ENGINE_PASS / _FAIL.
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vlog -work work_arr ..\..\rtl\yolo_engine_top.v
 *                          ..\..\rtl\yolo_csr.v (+array V1.2a closure)
 *                          ..\tb_yolo_engine_top.v
 *                     vsim -c -novopt +STIM=../stim/m10 +WDT_MS=900000 \
 *                          -do "run -all; quit -f" work_arr.tb_yolo_engine_top
 * Dependencies    : rtl/yolo_engine_top.v, rtl/yolo_csr.v,
 *                   rtl/yolo_gemm_array.v (V1.2a) + closure,
 *                   rtl/yolo_conv_core.v, sim/m10_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-16) by LSL : Initial release (M12 A1 CSR/engine
 *     gate). Derived from tb_yolo_gemm_array.v V1.1 (golden chain,
 *     BFMs and compare logic copied unchanged; descriptor/LUT/status
 *     drive rewritten onto the AXI-Lite master BFM).
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_engine_top;

    // ---- DUT geometry (SIM 8x8, matches the M10 gate build) ----
    localparam OC_EDGE   = 8;
    localparam N_EDGE    = 8;
    localparam ROW_AW    = 3;
    localparam COL_AW    = 3;
    localparam OC_AW     = 11;
    localparam N_AW      = 16;
    localparam K_AW      = 12;
    localparam ADDR_W    = 32;
    localparam NL_MAX    = 8;
    localparam FLDS      = 28;      // tokens per layer row
    localparam IMG_WORDS = 66000;   // >= n_ddrwords.hex (65621)
    localparam YSPAN     = 410000;  // >= max oc*n (R1 409600)
    localparam SENT      = 8'hA5;

    // ---- CSR register map mirror (contract: hw_contract/address_map.md;
    //      RTL: rtl/yolo_csr.v -- three-way sync) ----
    localparam [31:0] RB       = 32'h43C1_0000;   // C_BASEADDR
    localparam [31:0] O_ID     = 32'h000;
    localparam [31:0] O_VER    = 32'h004;
    localparam [31:0] O_CTRL   = 32'h008;
    localparam [31:0] O_STATUS = 32'h00C;
    localparam [31:0] O_DESC0  = 32'h010;
    localparam [31:0] O_DESC1  = 32'h014;
    localparam [31:0] O_DESC2  = 32'h018;
    localparam [31:0] O_DESC3  = 32'h01C;
    localparam [31:0] O_DESC4  = 32'h020;
    localparam [31:0] O_DESC5  = 32'h024;
    localparam [31:0] O_WBASE  = 32'h028;
    localparam [31:0] O_XBASE  = 32'h02C;
    localparam [31:0] O_YBASE  = 32'h030;
    localparam [31:0] O_BBASE  = 32'h034;
    localparam [31:0] O_MBASE  = 32'h038;
    localparam [31:0] O_SBASE  = 32'h03C;
    localparam [31:0] O_IRQ_EN = 32'h040;
    localparam [31:0] O_IRQ_ST = 32'h044;
    localparam [31:0] O_LUT    = 32'h400;

    // ---- clock / reset ----
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // ---- AXI4-Lite master (PS role) ----
    reg  [31:0] m_axil_awaddr  = 0;
    reg         m_axil_awvalid = 1'b0;
    reg  [31:0] m_axil_wdata   = 0;
    reg  [3:0]  m_axil_wstrb   = 4'hF;
    reg         m_axil_wvalid  = 1'b0;
    wire        m_axil_awready;
    wire        m_axil_wready;
    wire [1:0]  m_axil_bresp;
    wire        m_axil_bvalid;
    reg         m_axil_bready  = 1'b1;   // always ready for B
    reg  [31:0] m_axil_araddr  = 0;
    reg         m_axil_arvalid = 1'b0;
    wire        m_axil_arready;
    wire [31:0] m_axil_rdata;
    wire [1:0]  m_axil_rresp;
    wire        m_axil_rvalid;
    reg         m_axil_rready  = 1'b1;   // always ready for R

    // ---- AXI4 read master BFM wiring (W/params; M10 names kept) ----
    wire [ADDR_W-1:0]    araddr;
    wire [7:0]           arlen;
    wire [2:0]           arsize;
    wire [1:0]           arburst;
    wire                 arvalid;
    wire                 rready;
    wire                 arready;
    reg  [63:0]          rdata;
    reg                  rvalid;
    reg                  rlast;

    // ---- AXI4 write master BFM wiring (Y; M10 names kept) ----
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

    // ---- X plane comb port + irq ----
    wire [ADDR_W-1:0]    x_addr;
    reg  [7:0]           x_rdata;
    wire                 irq;

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

    // Y capture (DUT scatter via write BFM + golden scatter, sentinel =
    // single-write check); n_yerr = Y AXI protocol guards
    reg [7:0]            yd [0:NL_MAX*YSPAN-1];
    reg [7:0]            yg [0:NL_MAX*YSPAN-1];
    integer              cur_layer = 0;
    integer              n_ywr = 0, n_dbl = 0, n_ybad = 0, n_yerr = 0;

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
    yolo_engine_top #(
        .C_BASEADDR (RB),
        .OC_EDGE    (OC_EDGE),
        .N_EDGE     (N_EDGE),
        .ROW_AW     (ROW_AW),
        .COL_AW     (COL_AW),
        .OC_AW      (OC_AW),
        .N_AW       (N_AW),
        .K_AW       (K_AW)
    ) dut (
        .clk_i            (clk),
        .rst_n            (rst_n),
        // AXI4-Lite slave
        .s_axi_awaddr     (m_axil_awaddr),
        .s_axi_awprot     (3'b000),
        .s_axi_awvalid    (m_axil_awvalid),
        .s_axi_awready    (m_axil_awready),
        .s_axi_wdata      (m_axil_wdata),
        .s_axi_wstrb      (m_axil_wstrb),
        .s_axi_wvalid     (m_axil_wvalid),
        .s_axi_wready     (m_axil_wready),
        .s_axi_bresp      (m_axil_bresp),
        .s_axi_bvalid     (m_axil_bvalid),
        .s_axi_bready     (m_axil_bready),
        .s_axi_araddr     (m_axil_araddr),
        .s_axi_arprot     (3'b000),
        .s_axi_arvalid    (m_axil_arvalid),
        .s_axi_arready    (m_axil_arready),
        .s_axi_rdata      (m_axil_rdata),
        .s_axi_rresp      (m_axil_rresp),
        .s_axi_rvalid     (m_axil_rvalid),
        .s_axi_rready     (m_axil_rready),
        // AXI4 read master (W/params)
        .m_axi_araddr     (araddr),
        .m_axi_arlen      (arlen),
        .m_axi_arsize     (arsize),
        .m_axi_arburst    (arburst),
        .m_axi_arvalid    (arvalid),
        .m_axi_arready    (arready),
        .m_axi_rdata      (rdata),
        .m_axi_rlast      (rlast),
        .m_axi_rvalid     (rvalid),
        .m_axi_rready     (rready),
        // AXI4 write master (Y)
        .m_axi_awaddr     (awaddr),
        .m_axi_awlen      (awlen),
        .m_axi_awsize     (awsize),
        .m_axi_awburst    (awburst),
        .m_axi_awvalid    (awvalid),
        .m_axi_awready    (awready),
        .m_axi_wdata      (wdata),
        .m_axi_wstrb      (wstrb),
        .m_axi_wlast      (wlast),
        .m_axi_wvalid     (wvalid),
        .m_axi_wready     (wready),
        .m_axi_bvalid     (bvalid),
        .m_axi_bresp      (bresp),
        .m_axi_bready     (bready),
        // X plane byte port
        .x_addr_o         (x_addr),
        .x_rdata_i        (x_rdata),
        .irq_o            (irq)
    );

    // =================================================================
    // AXI4-Lite master tasks (PS role)
    // =================================================================
    integer n_csr = 0;      // AXI-Lite / readback / IRQ errors (declared
                            // before the tasks that bump it -- 10.1c
                            // sequential identifier resolution)

    // Readys are pure register functions (bpend_r / rpend_r) -- stable
    // within a cycle; negedge drives + negedge polls are race free.
    task axil_wr;
        input [31:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            m_axil_awaddr  = a;
            m_axil_awvalid = 1'b1;
            m_axil_wdata   = d;
            m_axil_wstrb   = 4'hF;
            m_axil_wvalid  = 1'b1;
            while (!(m_axil_awready === 1'b1 && m_axil_wready === 1'b1))
                @(negedge clk);
            @(posedge clk);          // accept edge (AW + W together)
            @(negedge clk);
            m_axil_awvalid = 1'b0;
            m_axil_wvalid  = 1'b0;
            while (m_axil_bvalid !== 1'b1) @(negedge clk);
            if (m_axil_bresp !== 2'b00) begin
                n_csr = n_csr + 1;
                $display("[tb] ERR AXI-Lite B resp=%0d @%h",
                         m_axil_bresp, a);
            end
            @(negedge clk);          // B consumed (bready held high)
        end
    endtask

    task axil_rd;
        input  [31:0] a;
        output [31:0] d;
        begin
            @(negedge clk);
            m_axil_araddr  = a;
            m_axil_arvalid = 1'b1;
            while (m_axil_arready !== 1'b1) @(negedge clk);
            @(posedge clk);          // AR accept edge (data latched)
            @(negedge clk);
            m_axil_arvalid = 1'b0;
            while (m_axil_rvalid !== 1'b1) @(negedge clk);
            d = m_axil_rdata;
            if (m_axil_rresp !== 2'b00) begin
                n_csr = n_csr + 1;
                $display("[tb] ERR AXI-Lite R resp=%0d @%h",
                         m_axil_rresp, a);
            end
            @(negedge clk);          // R consumed (rready held high)
        end
    endtask

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

    // ---- Y AXI4 write slave BFM (identical to M10 TB V1.1) ----
    wire       yaw_stall_w = (lfsr[7:4]  == 4'h0);
    wire       yw_stall_w  = (lfsr[11:8] == 4'h0);
    wire [1:0] ybgap_w     = lfsr[13:12];

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

    // W monitor + scatter: protocol guards + strobed bytes -> yd
    integer  jw;
    reg [ADDR_W-1:0] yb_addr;
    always @(posedge clk) begin
        if (rst_n) begin
            if (awvalid && awready) begin
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
                for (jw = 0; jw < 8; jw = jw + 1) begin
                    if (wstrb[jw]) begin
                        yb_addr = yaw_addr + yaw_beat*8 + jw;
                        n_ywr = n_ywr + 1;
                        if (yd[yb_addr] === SENT) begin
                            yd[yb_addr] <= wdata[8*jw +: 8];
                        end else begin
                            n_dbl = n_dbl + 1;
                            if (n_dbl == 1)
                                $display("[tb] ERROR double DUT write addr=%0d",
                                         yb_addr);
                        end
                    end
                end
            end
        end
    end

    // =================================================================
    // golden M0 instances (synthetic layers; comb-served from image)
    // =================================================================
    reg  g0_start = 1'b0, g2_start = 1'b0, g3_start = 1'b0, g5_start = 1'b0;
    wire g0_busy, g0_done, g2_busy, g2_done, g3_busy, g3_done;
    wire g5_busy, g5_done;
    wire [7:0]  g0_xa;
    wire [12:0] g2_xa, g3_xa, g5_xa;
    wire [7:0]  g0_wa;
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
    // serves are WIRES driven by continuous assigns (M0-proven pattern)
    wire signed [7:0]  g0_xd, g0_wd, g2_wd, g3_wd, g5_wd;
    wire signed [7:0]  g2_xd, g3_xd, g5_xd;
    wire signed [31:0] g0_bd, g0_md, g2_bd, g2_md, g3_bd, g3_md;
    wire signed [31:0] g5_bd, g5_md;
    wire [7:0]  g0_sd, g2_sd, g3_sd, g5_sd;
    wire signed [7:0]  g0_ld, g2_ld, g3_ld, g5_ld;
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
    // main sequence (PS role: everything through the CSR)
    // =================================================================
    reg [1023:0] stim = "../stim/m10";
    integer      wdt_ms = 900000;
    integer      max_lay = 0;       // +MAXLAYER: smoke first-K-layers flow
    integer      n_run;
    integer      total_out = 0;
    integer      total_run = 0;
    integer      n_cmp = 0, n_err = 0, first_err_L = 0;
    integer      first_err_i = 0;
    integer      pk;
    reg [7:0]    ev, gv;
    reg [31:0]   dv, dpat, st_final;
    reg [31:0]   rw_addr [0:11];

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin end
        if ($value$plusargs("MAXLAYER=%d", max_lay)) begin end

        $readmemh({stim, "/n_layers.hex"},  memtmp); n_layers = memtmp[0];
        $readmemh({stim, "/n_ddrwords.hex"},memtmp); n_words  = memtmp[0];
        if (n_words > IMG_WORDS) begin
            $display("TB_CSR_ENGINE_FAIL (image %0d > %0d)", n_words,
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
        n_run = (max_lay > 0 && max_lay < n_layers) ? max_lay : n_layers;
        for (L = 0; L < n_run; L = L + 1)
            total_run = total_run + lay[L*FLDS+1] * lay[L*FLDS+2];
        // RW register address list (pattern roundtrip at t0)
        rw_addr[0]  = RB + O_DESC0;  rw_addr[1]  = RB + O_DESC1;
        rw_addr[2]  = RB + O_DESC2;  rw_addr[3]  = RB + O_DESC3;
        rw_addr[4]  = RB + O_DESC4;  rw_addr[5]  = RB + O_DESC5;
        rw_addr[6]  = RB + O_WBASE;  rw_addr[7]  = RB + O_XBASE;
        rw_addr[8]  = RB + O_YBASE;  rw_addr[9]  = RB + O_BBASE;
        rw_addr[10] = RB + O_MBASE;  rw_addr[11] = RB + O_SBASE;
        $display("[tb] engine stim=%0s layers=%0d img_words=%0d total_out=%0d",
                 stim, n_layers, n_words, total_out);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // ---- t0 self-check: ID / VER / 12-shadow pattern roundtrip ----
        axil_rd(RB + O_ID, dv);
        if (dv !== 32'h594F4C31) begin
            n_csr = n_csr + 1;
            $display("[tb] ERR ID read %h", dv);
        end
        axil_rd(RB + O_VER, dv);
        if (dv !== 32'h0001_0000) begin
            n_csr = n_csr + 1;
            $display("[tb] ERR VER read %h", dv);
        end
        for (i = 0; i < 12; i = i + 1) begin
            dpat = 32'h5A000000 + i * 32'h010101;
            axil_wr(rw_addr[i], dpat);
            axil_rd(rw_addr[i], dv);
            if (dv !== dpat) begin
                n_csr = n_csr + 1;
                $display("[tb] ERR RW roundtrip @%h got=%h exp=%h",
                         rw_addr[i], dv, dpat);
            end
        end
        // frame setup: IRQ enables + stats clear + clear verify
        axil_wr(RB + O_IRQ_EN, 32'h3);
        axil_wr(RB + O_CTRL, 32'h2);          // CLR_STATS
        axil_rd(RB + O_STATUS, dv);
        if (dv[31:16] !== 16'd0 || dv[2] !== 1'b0) begin
            n_csr = n_csr + 1;
            $display("[tb] ERR CLR_STATS left status=%h", dv);
        end

        for (L = 0; L < n_run; L = L + 1) begin
            // inter-layer gap (idle cycles)
            for (i = 0; i < lay[L*FLDS+0]; i = i + 1) @(negedge clk);
            // LUT preload through the CSR window
            for (i = 0; i < 256; i = i + 1)
                axil_wr(RB + O_LUT + 4*i,
                        {24'b0, imgbyte(lay[L*FLDS+22] + i)});
            // descriptor program (packing mirrors yolo_csr.v unpack)
            axil_wr(RB + O_DESC0,
                    {lay[L*FLDS+2][15:0], 5'b0, lay[L*FLDS+1][10:0]});
            axil_wr(RB + O_DESC1,
                    {13'b0, lay[L*FLDS+15][0], lay[L*FLDS+14][0],
                     lay[L*FLDS+16][0], 4'b0, lay[L*FLDS+3][11:0]});
            axil_wr(RB + O_DESC2, {lay[L*FLDS+5][15:0], lay[L*FLDS+4][15:0]});
            axil_wr(RB + O_DESC3, {lay[L*FLDS+7][15:0], lay[L*FLDS+6][15:0]});
            axil_wr(RB + O_DESC4,
                    {lay[L*FLDS+11][7:0], lay[L*FLDS+10][7:0],
                     lay[L*FLDS+9][7:0],  lay[L*FLDS+8][7:0]});
            axil_wr(RB + O_DESC5, {16'b0, lay[L*FLDS+13][7:0],
                                    lay[L*FLDS+12][7:0]});
            axil_wr(RB + O_WBASE, lay[L*FLDS+17]);
            axil_wr(RB + O_XBASE, lay[L*FLDS+18]);
            axil_wr(RB + O_YBASE, L*YSPAN);  // mirror layout identical
                                              // to the M10 gate
            axil_wr(RB + O_BBASE, lay[L*FLDS+19]);
            axil_wr(RB + O_MBASE, lay[L*FLDS+20]);
            axil_wr(RB + O_SBASE, lay[L*FLDS+21]);
            // DESC0 readback spot check (decode path exercised)
            axil_rd(RB + O_DESC0, dv);
            if (dv !== {lay[L*FLDS+2][15:0], 5'b0, lay[L*FLDS+1][10:0]}) begin
                n_csr = n_csr + 1;
                $display("[tb] ERR DESC0 readback L=%0d got=%h", L, dv);
            end
            // DESC1 readback spot check (flag packing: last[16] first[17]
            // act[18], k[11:0] -- the smoke run caught the first draft
            // packing them at [14:12], losing act=1 on L0)
            axil_rd(RB + O_DESC1, dv);
            if (dv !== {13'b0, lay[L*FLDS+15][0], lay[L*FLDS+14][0],
                        lay[L*FLDS+16][0], 4'b0, lay[L*FLDS+3][11:0]}) begin
                n_csr = n_csr + 1;
                $display("[tb] ERR DESC1 readback L=%0d got=%h", L, dv);
            end
            // doorbell + accept wait (dsc_pend clears at the handshake)
            axil_wr(RB + O_CTRL, 32'h1);
            pk = 0;
            axil_rd(RB + O_STATUS, dv);
            while (dv[3] === 1'b1) begin
                pk = pk + 1;
                if (pk > 64) begin
                    $display("TB_CSR_ENGINE_FAIL (doorbell stuck) L=%0d", L);
                    $finish;
                end
                axil_rd(RB + O_STATUS, dv);
            end
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
            // poll ldone_cnt == L+1 (drain-gated: all Y bytes of the
            // layer have landed when the count advances)
            pk = 0;
            axil_rd(RB + O_STATUS, dv);
            while (dv[31:16] < (L + 1)) begin
                pk = pk + 1;
                if (pk > 5_000_000) begin
                    $display("TB_CSR_ENGINE_FAIL (ldone poll timeout) L=%0d",
                             L);
                    $finish;
                end
                axil_rd(RB + O_STATUS, dv);
            end
            $display("[tb] layer %0d done @t=%0t (oc=%0d n=%0d k=%0d)",
                     L, $time, lay[L*FLDS+1], lay[L*FLDS+2], lay[L*FLDS+3]);
            repeat (8) @(negedge clk);
            cur_layer = L + 1;
        end

        // ---- frame end: all_done sticky + IRQ raise/W1C (full gate
        //      only -- smoke runs stop before the last=1 descriptor,
        //      so all_done never fires there) ----
        if (n_run == n_layers) begin
            pk = 0;
            axil_rd(RB + O_STATUS, dv);
            while (dv[2] !== 1'b1) begin
                pk = pk + 1;
                if (pk > 64) begin
                    $display("TB_CSR_ENGINE_FAIL (all_done poll timeout)");
                    $finish;
                end
                axil_rd(RB + O_STATUS, dv);
            end
            st_final = dv;
            if (irq !== 1'b1) begin
                n_csr = n_csr + 1;
                $display("[tb] ERR irq_o not asserted at frame end");
            end
            axil_wr(RB + O_IRQ_ST, 32'h3);        // W1C both
            repeat (4) @(negedge clk);
            if (irq !== 1'b0) begin
                n_csr = n_csr + 1;
                $display("[tb] ERR irq_o not cleared after W1C");
            end
            axil_rd(RB + O_IRQ_ST, dv);
            if (dv[1:0] !== 2'b00) begin
                n_csr = n_csr + 1;
                $display("[tb] ERR IRQ_STAT not clear: %h", dv);
            end
        end else begin
            axil_rd(RB + O_STATUS, st_final);     // smoke: ldone snapshot
        end

        // final wait: golden cores whose layer ran + tail drain
        if (0 < n_run) while (g0_dn == 0) @(posedge clk);
        if (2 < n_run) while (g2_dn == 0) @(posedge clk);
        if (3 < n_run) while (g3_dn == 0) @(posedge clk);
        if (5 < n_run) while (g5_dn == 0) @(posedge clk);
        repeat (16) @(negedge clk);

        // ---- compare (identical to the M10 gate) ----
        for (L = 0; L < n_run; L = L + 1) begin
            for (i = 0; i < lay[L*FLDS+1]*lay[L*FLDS+2]; i = i + 1) begin
                ev = yd[L*YSPAN + i];
                n_cmp = n_cmp + 1;
                if (ev === SENT) begin
                    // 0xA5 is a legal output value: a DUT write of 0xA5
                    // is indistinguishable from "never written".
                    // Invariants (checked in PASS): dut_wr==total_out &&
                    // dbl==0 imply every cell written exactly once, and
                    // gold_wr==oc*n && gdbl==0 imply the golden covered
                    // every cell -- so gold-side 0xA5 means the DUT
                    // value matches. Flag only when the reference
                    // value differs.
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

        if (n_run == n_layers) begin
            if (n_err == 0 && n_dbl == 0 && n_ybad == 0 && n_yerr == 0
                && (g0_db + g2_db + g3_db + g5_db) == 0
                && n_ywr == total_out
                && (g0_wr + g2_wr + g3_wr + g5_wr) == 343 + 400 + 2304 + 200
                && st_final[31:16] == n_layers && st_final[2] == 1'b1
                && n_csr == 0) begin
                $display("TB_CSR_ENGINE_PASS layers=%0d compared=%0d dut_wr=%0d gold_wr=%0d ldone=%0d adone=%0d csr=%0d",
                         n_layers, n_cmp, n_ywr,
                         g0_wr + g2_wr + g3_wr + g5_wr, st_final[31:16],
                         st_final[2], n_csr);
            end else begin
                $display("TB_CSR_ENGINE_FAIL err=%0d dbl=%0d gdbl=%0d unwritten=%0d yaxi=%0d csr=%0d dut_wr=%0d(exp %0d) gold_wr=%0d ldone=%0d(exp %0d) adone=%0d",
                         n_err, n_dbl, g0_db + g2_db + g3_db + g5_db, n_ybad,
                         n_yerr, n_csr, n_ywr, total_out,
                         g0_wr + g2_wr + g3_wr + g5_wr, st_final[31:16],
                         n_layers, st_final[2]);
            end
        end else begin
            // smoke: layers actually run; gold_wr = synthetic goldens
            // that ran; adone/IRQ checks skipped (no last=1 descriptor)
            if (n_err == 0 && n_dbl == 0 && n_ybad == 0 && n_yerr == 0
                && (g0_db + g2_db + g3_db + g5_db) == 0
                && n_ywr == total_run
                && st_final[31:16] == n_run
                && n_csr == 0) begin
                $display("TB_CSR_ENGINE_SMOKE layers=%0d compared=%0d dut_wr=%0d gold_wr=%0d ldone=%0d csr=%0d",
                         n_run, n_cmp, n_ywr,
                         g0_wr + g2_wr + g3_wr + g5_wr, st_final[31:16],
                         n_csr);
            end else begin
                $display("TB_CSR_ENGINE_FAIL err=%0d dbl=%0d gdbl=%0d unwritten=%0d yaxi=%0d csr=%0d dut_wr=%0d(exp %0d) ldone=%0d(exp %0d)",
                         n_err, n_dbl, g0_db + g2_db + g3_db + g5_db, n_ybad,
                         n_yerr, n_csr, n_ywr, total_run,
                         st_final[31:16], n_run);
            end
        end
        $finish;
    end

    // heartbeat + watchdog
    always #10_000_000
        $display("[tb] heartbeat t=%0t cur_layer=%0d ywr=%0d", $time,
                 cur_layer, n_ywr);
    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_CSR_ENGINE_FAIL (timeout) t=%0t cur_layer=%0d ywr=%0d",
                 $time, cur_layer, n_ywr);
        $finish;
    end

endmodule
