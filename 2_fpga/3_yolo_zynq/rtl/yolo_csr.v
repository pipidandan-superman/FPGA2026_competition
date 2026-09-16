/************************************************************************
 * File Name       : yolo_csr.v
 * Developer       : LSL
 * Date            : 2026-09-16
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_csr
 * Description     : M12 A1 AXI4-Lite control/status register file for
 *                   the GEMM engine. Address contract single source of
 *                   truth = hw_contract/address_map.md (C_BASEADDR
 *                   parameterized; no hard-coded base in logic).
 *
 *                   PS v1 flow (software feeds one layer at a time):
 *                     1. frame start: CTRL.CLR_STATS
 *                     2. per layer: LUT window preload (256 writes, only
 *                        when the table changes) -> DESC0..DESC5 + six
 *                        BASE regs -> CTRL.START doorbell
 *                     3. poll STATUS: ldone_cnt[31:16] advances only
 *                        after the Y segmenter drained (layer_done is
 *                        drain-gated in the array) -- every Y byte of
 *                        that layer has landed; next DESC writes are
 *                        safe once dsc_ready=1 && dsc_pend=0
 *                     4. frame end: all_done sticky STATUS[2]
 *
 *                   Software contract: do NOT rewrite DESC or BASE regs
 *                   STATUS.dsc_pend=1 (doorbell not yet accepted). The
 *                   array samples the shadow only at the accept edge,
 *                   but a rewrite before that edge would be accepted
 *                   instead of the intended values.
 *
 *                   Register map (offset from C_BASEADDR, 32-bit):
 *                    0x00 R   ID       0x594F4C31
 *                    0x04 R   VER      0x0001_0000 (A1)
 *                    0x08 W   CTRL     [0] START doorbell
 *                                      [1] CLR_STATS (ldone_cnt /
 *                                          all_done sticky / IRQ raw)
 *                    0x0C R   STATUS   [0] busy  [1] dsc_ready
 *                                      [2] all_done sticky
 *                                      [3] dsc_pend (doorbell queued)
 *                                      [31:16] ldone_cnt
 *                    0x10 RW  DESC0    [10:0] oc, [31:16] n
 *                    0x14 RW  DESC1    [11:0] k, [16] last,
 *                                      [17] first, [18] act
 *                    0x18 RW  DESC2    [15:0] ih, [31:16] iw
 *                    0x1C RW  DESC3    [15:0] ow, [31:16] ic
 *                    0x20 RW  DESC4    [7:0] kh [15:8] kw
 *                                      [23:16] sh [31:24] sw
 *                    0x24 RW  DESC5    [7:0] ph, [15:8] pw
 *                    0x28 RW  WBASE    0x2C XBASE   0x30 YBASE
 *                    0x34 RW  BBASE    0x38 MBASE   0x3C SBASE
 *                    0x40 RW  IRQ_EN   [0] layer_done [1] all_done
 *                    0x44 RW  IRQ_STAT write-1-to-clear [0]/[1]
 *                    0x400 + 4*i  W  LUT[i] = wdata[7:0], i = 0..255
 *                    (window 0x400..0x7FF, write-only, reads 0)
 *                   Unmapped offsets: OKAY, writes ignored, reads 0.
 *
 *                   AXI4-Lite slave: single outstanding; AW and W are
 *                   accepted together in the cycle both are valid
 *                   (readys depend on the response registers only --
 *                   no valid dependency, deadlock free); B held until
 *                   bready; byte strobes merged into the shadows.
 *                   LUT window writes ignore strobe bytes != 0 (a LUT
 *                   entry is one byte; PS must use word writes there).
 * Dependencies    : none (glue only; descriptor widths parameterized
 *                   to match yolo_gemm_array ports)
 * Revision History:
 *   - V1.0 (2026-09-16) by LSL : Initial release (M12 A1).
 ************************************************************************/

module yolo_csr #(
    parameter [31:0] C_BASEADDR = 32'h43C1_0000,
    parameter        OC_AW      = 11,   // descriptor OC width
    parameter        N_AW       = 16,   // descriptor N width
    parameter        K_AW       = 12    // descriptor K width
) (
    input  wire                  clk_i,
    input  wire                  rst_n,
    // ---- AXI4-Lite slave (PS GP0) ----
    input  wire [31:0]           s_axi_awaddr,
    input  wire [2:0]            s_axi_awprot,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [31:0]           s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [31:0]           s_axi_araddr,
    input  wire [2:0]            s_axi_arprot,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output wire [31:0]           s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,
    // ---- layer descriptor stream (to yolo_gemm_array) ----
    output wire                  dsc_valid_o,
    input  wire                  dsc_ready_i,
    output wire [OC_AW-1:0]      dsc_oc_o,
    output wire [N_AW-1:0]       dsc_n_o,
    output wire [K_AW-1:0]       dsc_k_o,
    output wire                  dsc_last_o,
    output wire [15:0]           dsc_ih_o,
    output wire [15:0]           dsc_iw_o,
    output wire [15:0]           dsc_ow_o,
    output wire [15:0]           dsc_ic_o,
    output wire [7:0]            dsc_kh_o,
    output wire [7:0]            dsc_kw_o,
    output wire [7:0]            dsc_sh_o,
    output wire [7:0]            dsc_sw_o,
    output wire [7:0]            dsc_ph_o,
    output wire [7:0]            dsc_pw_o,
    output wire                  dsc_first_o,
    output wire                  dsc_act_o,
    output wire [31:0]           dsc_wbase_o,
    output wire [31:0]           dsc_xbase_o,
    output wire [31:0]           dsc_ybase_o,
    output wire [31:0]           dsc_bbase_o,
    output wire [31:0]           dsc_mbase_o,
    output wire [31:0]           dsc_sbase_o,
    // ---- SiLU LUT preload window (to yolo_gemm_array) ----
    output wire                  lut_we_o,
    output wire [7:0]            lut_waddr_o,
    output wire [7:0]            lut_wdata_o,
    // ---- array status ----
    input  wire                  layer_done_i,
    input  wire                  all_done_i,
    input  wire                  busy_i,
    output wire                  irq_o
);

    // ----------------------------------------------------------------
    // register indices (offset >> 2)
    // ----------------------------------------------------------------
    localparam [9:0] R_ID       = 10'd0;   // 0x00
    localparam [9:0] R_VER      = 10'd1;   // 0x04
    localparam [9:0] R_CTRL     = 10'd2;   // 0x08
    localparam [9:0] R_STATUS   = 10'd3;   // 0x0C
    localparam [9:0] R_DESC0    = 10'd4;   // 0x10
    localparam [9:0] R_DESC1    = 10'd5;   // 0x14
    localparam [9:0] R_DESC2    = 10'd6;   // 0x18
    localparam [9:0] R_DESC3    = 10'd7;   // 0x1C
    localparam [9:0] R_DESC4    = 10'd8;   // 0x20
    localparam [9:0] R_DESC5    = 10'd9;   // 0x24
    localparam [9:0] R_WBASE    = 10'd10;  // 0x28
    localparam [9:0] R_XBASE    = 10'd11;  // 0x2C
    localparam [9:0] R_YBASE    = 10'd12;  // 0x30
    localparam [9:0] R_BBASE    = 10'd13;  // 0x34
    localparam [9:0] R_MBASE    = 10'd14;  // 0x38
    localparam [9:0] R_SBASE    = 10'd15;  // 0x3C
    localparam [9:0] R_IRQ_EN   = 10'd16;  // 0x40
    localparam [9:0] R_IRQ_STAT = 10'd17;  // 0x44

    // ----------------------------------------------------------------
    // byte-strobe merge helper (declared before first use)
    // ----------------------------------------------------------------
    function [31:0] merge32;
        input [31:0] old_v;
        input [31:0] new_v;
        input [3:0]  strb;
        begin
            merge32 = { strb[3] ? new_v[31:24] : old_v[31:24],
                        strb[2] ? new_v[23:16] : old_v[23:16],
                        strb[1] ? new_v[15:8]  : old_v[15:8],
                        strb[0] ? new_v[7:0]   : old_v[7:0] };
        end
    endfunction

    // ----------------------------------------------------------------
    // AXI4-Lite write channel: AW+W accepted together, single B
    // ----------------------------------------------------------------
    reg         bpend_r;
    wire        wr_fire_w = s_axi_awvalid && s_axi_wvalid && !bpend_r;

    assign s_axi_awready = !bpend_r;
    assign s_axi_wready  = !bpend_r;
    assign s_axi_bvalid  = bpend_r;
    assign s_axi_bresp   = 2'b00;                     // OKAY

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) bpend_r <= 1'b0;
        else        bpend_r <= wr_fire_w || (bpend_r && !s_axi_bready);
    end

    // write decode (offset from C_BASEADDR)
    wire [31:0] woff_w    = s_axi_awaddr - C_BASEADDR;
    wire        wcore_w   = (woff_w[15:10] == 6'd0);  // 0x000..0x3FF
    wire        wlut_w    = (woff_w[15:10] == 6'd1);  // 0x400..0x7FF
    wire [9:0]  wreg_w    = woff_w[11:2];

    // LUT window: one-cycle write pulse, entry = low byte, word strobe
    assign lut_we_o    = wr_fire_w && wlut_w && s_axi_wstrb[0];
    assign lut_waddr_o = woff_w[9:2];
    assign lut_wdata_o = s_axi_wdata[7:0];

    // ----------------------------------------------------------------
    // register file
    // ----------------------------------------------------------------
    reg [31:0] desc0_r, desc1_r, desc2_r, desc3_r, desc4_r, desc5_r;
    reg [31:0] wbase_r, xbase_r, ybase_r, bbase_r, mbase_r, sbase_r;
    reg [1:0]  irq_en_r;
    reg [1:0]  irq_raw_r;
    reg        start_pend_r;      // doorbell queued (dsc_valid)
    reg [15:0] ldone_cnt_r;       // layer_done pulse count
    reg        adone_st_r;        // all_done sticky

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            desc0_r      <= 32'd0;
            desc1_r      <= 32'd0;
            desc2_r      <= 32'd0;
            desc3_r      <= 32'd0;
            desc4_r      <= 32'd0;
            desc5_r      <= 32'd0;
            wbase_r      <= 32'd0;
            xbase_r      <= 32'd0;
            ybase_r      <= 32'd0;
            bbase_r      <= 32'd0;
            mbase_r      <= 32'd0;
            sbase_r      <= 32'd0;
            irq_en_r     <= 2'b00;
            irq_raw_r    <= 2'b00;
            start_pend_r <= 1'b0;
            ldone_cnt_r  <= 16'd0;
            adone_st_r   <= 1'b0;
        end else begin
            // ---- doorbell: set on CTRL.START (last assignment wins so
            //      a fresh START re-arms even on the accept edge of a
            //      stale one), clear on the array accept handshake ----
            if (start_pend_r && dsc_ready_i) start_pend_r <= 1'b0;

            // ---- register writes ----
            if (wr_fire_w && wcore_w) begin
                case (wreg_w)
                    R_CTRL: begin
                        if (s_axi_wstrb[0]) begin
                            if (s_axi_wdata[0]) start_pend_r <= 1'b1;
                            if (s_axi_wdata[1]) begin
                                ldone_cnt_r <= 16'd0;
                                adone_st_r  <= 1'b0;
                                irq_raw_r   <= 2'b00;
                            end
                        end
                    end
                    R_DESC0: desc0_r <= merge32(desc0_r, s_axi_wdata, s_axi_wstrb);
                    R_DESC1: desc1_r <= merge32(desc1_r, s_axi_wdata, s_axi_wstrb);
                    R_DESC2: desc2_r <= merge32(desc2_r, s_axi_wdata, s_axi_wstrb);
                    R_DESC3: desc3_r <= merge32(desc3_r, s_axi_wdata, s_axi_wstrb);
                    R_DESC4: desc4_r <= merge32(desc4_r, s_axi_wdata, s_axi_wstrb);
                    R_DESC5: desc5_r <= merge32(desc5_r, s_axi_wdata, s_axi_wstrb);
                    R_WBASE: wbase_r <= merge32(wbase_r, s_axi_wdata, s_axi_wstrb);
                    R_XBASE: xbase_r <= merge32(xbase_r, s_axi_wdata, s_axi_wstrb);
                    R_YBASE: ybase_r <= merge32(ybase_r, s_axi_wdata, s_axi_wstrb);
                    R_BBASE: bbase_r <= merge32(bbase_r, s_axi_wdata, s_axi_wstrb);
                    R_MBASE: mbase_r <= merge32(mbase_r, s_axi_wdata, s_axi_wstrb);
                    R_SBASE: sbase_r <= merge32(sbase_r, s_axi_wdata, s_axi_wstrb);
                    R_IRQ_EN: begin
                        if (s_axi_wstrb[0]) irq_en_r <= s_axi_wdata[1:0];
                    end
                    R_IRQ_STAT: begin
                        // W1C -- array pulses placed after this line so
                        // a pulse racing the clear is never lost
                        if (s_axi_wstrb[0])
                            irq_raw_r <= irq_raw_r & ~s_axi_wdata[1:0];
                    end
                    default: ;                       // RO / unmapped
                endcase
            end

            // ---- array status capture ----
            if (layer_done_i) begin
                ldone_cnt_r  <= ldone_cnt_r + 16'd1;
                irq_raw_r[0] <= 1'b1;
            end
            if (all_done_i) begin
                adone_st_r   <= 1'b1;
                irq_raw_r[1] <= 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // AXI4-Lite read channel
    // ----------------------------------------------------------------
    wire [31:0] roff_w  = s_axi_araddr - C_BASEADDR;
    wire        rcore_w = (roff_w[15:10] == 6'd0);
    wire [9:0]  rreg_w  = roff_w[11:2];

    reg  [31:0] rdec_w;
    always @(*) begin
        rdec_w = 32'd0;
        if (rcore_w) begin
            case (rreg_w)
                R_ID:       rdec_w = 32'h594F4C31;
                R_VER:      rdec_w = 32'h0001_0000;
                R_STATUS:   rdec_w = {ldone_cnt_r, 12'd0, start_pend_r,
                                      adone_st_r, dsc_ready_i, busy_i};
                R_DESC0:    rdec_w = desc0_r;
                R_DESC1:    rdec_w = desc1_r;
                R_DESC2:    rdec_w = desc2_r;
                R_DESC3:    rdec_w = desc3_r;
                R_DESC4:    rdec_w = desc4_r;
                R_DESC5:    rdec_w = desc5_r;
                R_WBASE:    rdec_w = wbase_r;
                R_XBASE:    rdec_w = xbase_r;
                R_YBASE:    rdec_w = ybase_r;
                R_BBASE:    rdec_w = bbase_r;
                R_MBASE:    rdec_w = mbase_r;
                R_SBASE:    rdec_w = sbase_r;
                R_IRQ_EN:   rdec_w = {30'd0, irq_en_r};
                R_IRQ_STAT: rdec_w = {30'd0, irq_raw_r};
                default:    rdec_w = 32'd0;
            endcase
        end
    end

    reg         rpend_r;
    reg  [31:0] rdata_q;
    wire        rd_fire_w = s_axi_arvalid && !rpend_r;

    assign s_axi_arready = !rpend_r;
    assign s_axi_rvalid  = rpend_r;
    assign s_axi_rdata   = rdata_q;
    assign s_axi_rresp   = 2'b00;                     // OKAY

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            rpend_r <= 1'b0;
            rdata_q <= 32'd0;
        end else begin
            rpend_r <= rd_fire_w || (rpend_r && !s_axi_rready);
            if (rd_fire_w) rdata_q <= rdec_w;
        end
    end

    // ----------------------------------------------------------------
    // descriptor stream outputs (pure shadow plumbing)
    // ----------------------------------------------------------------
    assign dsc_valid_o = start_pend_r;
    assign dsc_oc_o    = desc0_r[OC_AW-1:0];
    assign dsc_n_o     = desc0_r[31:16];
    assign dsc_k_o     = desc1_r[K_AW-1:0];
    assign dsc_last_o  = desc1_r[16];
    assign dsc_first_o = desc1_r[17];
    assign dsc_act_o   = desc1_r[18];
    assign dsc_ih_o    = desc2_r[15:0];
    assign dsc_iw_o    = desc2_r[31:16];
    assign dsc_ow_o    = desc3_r[15:0];
    assign dsc_ic_o    = desc3_r[31:16];
    assign dsc_kh_o    = desc4_r[7:0];
    assign dsc_kw_o    = desc4_r[15:8];
    assign dsc_sh_o    = desc4_r[23:16];
    assign dsc_sw_o    = desc4_r[31:24];
    assign dsc_ph_o    = desc5_r[7:0];
    assign dsc_pw_o    = desc5_r[15:8];
    assign dsc_wbase_o = wbase_r;
    assign dsc_xbase_o = xbase_r;
    assign dsc_ybase_o = ybase_r;
    assign dsc_bbase_o = bbase_r;
    assign dsc_mbase_o = mbase_r;
    assign dsc_sbase_o = sbase_r;

    assign irq_o = (irq_raw_r[0] & irq_en_r[0])
                 | (irq_raw_r[1] & irq_en_r[1]);

endmodule
