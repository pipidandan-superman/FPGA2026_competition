/************************************************************************
 * File Name       : yolo_engine_top.v
 * Developer       : LSL
 * Date            : 2026-09-16
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_engine_top
 * Description     : M12 A1 top-level assembly of the GEMM engine:
 *                   yolo_csr (AXI4-Lite, PS GP0, C_BASEADDR from the
 *                   address map contract) + yolo_gemm_array (V1.2a)
 *                   with its AXI4 read master (W/params, one HP port)
 *                   and AXI4 write master (Y, one HP port) routed to
 *                   the top. Default geometry = PROD 16x16; the CSR /
 *                   engine gate instantiates the SIM 8x8 build (same
 *                   RTL, different parameters only).
 *
 *                   X plane byte port is passed through unchanged in
 *                   A1 (comb contract: x_rdata_i valid in the same
 *                   cycle as x_addr_o, LUTRAM-style). A2 replaces it
 *                   with xrowgen + a second read DMA (authorized
 *                   loader V2 scope); REQUANT_UNITS pipelining of the
 *                   array tail is likewise A2 -- the engine parameter
 *                   set grows then, not now.
 *
 *                   No logic here beyond plumbing: every function
 *                   lives in a unit-tested module below.
 * Dependencies    : rtl/yolo_csr.v (V1.0), rtl/yolo_gemm_array.v
 *                   (V1.2a) + its dependency closure
 * Revision History:
 *   - V1.0 (2026-09-16) by LSL : Initial release (M12 A1).
 ************************************************************************/

module yolo_engine_top #(
    parameter [31:0] C_BASEADDR = 32'h43C1_0000,  // address_map.md
    parameter        OC_EDGE    = 16,             // PROD default
    parameter        N_EDGE     = 16,
    parameter        K_MAX      = 2304,
    parameter        AW         = 12,
    parameter        ROW_AW     = 4,              // ceil(log2 OC_EDGE)
    parameter        COL_AW     = 4,              // ceil(log2 N_EDGE)
    parameter        ADDR_W     = 32,
    parameter        LEN_W      = 24,
    parameter        OC_AW      = 11,
    parameter        N_AW       = 16,
    parameter        K_AW       = 12,
    parameter        TILE_AW    = 12,
    parameter        MAX_BURST  = 16
) (
    input  wire                  clk_i,
    input  wire                  rst_n,
    // ---- AXI4-Lite slave (PS GP0; descriptor / doorbell / status /
    //      LUT preload window, register map in yolo_csr.v header and
    //      hw_contract/address_map.md) ----
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
    // ---- AXI4 read master: W rows + requant params (HP) ----
    output wire [ADDR_W-1:0]     m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire                  m_axi_arvalid,
    input  wire                  m_axi_arready,
    input  wire [63:0]           m_axi_rdata,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready,
    // ---- AXI4 write master: Y plane rows (HP) ----
    output wire [ADDR_W-1:0]     m_axi_awaddr,
    output wire [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire                  m_axi_awvalid,
    input  wire                  m_axi_awready,
    output wire [63:0]           m_axi_wdata,
    output wire [7:0]            m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_wvalid,
    input  wire                  m_axi_wready,
    input  wire                  m_axi_bvalid,
    input  wire [1:0]            m_axi_bresp,
    output wire                  m_axi_bready,
    // ---- X plane byte read (comb passthrough; A2 = xrowgen + DMA) ----
    output wire [ADDR_W-1:0]     x_addr_o,
    input  wire [7:0]            x_rdata_i,
    // ---- interrupt (CSR IRQ_EN/IRQ_STAT) ----
    output wire                  irq_o
);

    // ----------------------------------------------------------------
    // CSR <-> array plumbing (declared before the instances: 10.1c
    // implicit-net trap when a later explicit declaration conflicts)
    // ----------------------------------------------------------------
    wire                  dsc_valid;
    wire                  dsc_ready;
    wire [OC_AW-1:0]      dsc_oc;
    wire [N_AW-1:0]       dsc_n;
    wire [K_AW-1:0]       dsc_k;
    wire                  dsc_last;
    wire [15:0]           dsc_ih, dsc_iw, dsc_ow, dsc_ic;
    wire [7:0]            dsc_kh, dsc_kw, dsc_sh, dsc_sw, dsc_ph, dsc_pw;
    wire                  dsc_first, dsc_act;
    wire [ADDR_W-1:0]     dsc_wbase, dsc_xbase, dsc_ybase;
    wire [ADDR_W-1:0]     dsc_bbase, dsc_mbase, dsc_sbase;
    wire                  lut_we;
    wire [7:0]            lut_waddr, lut_wdata;
    wire                  layer_done, all_done, busy;

    // ----------------------------------------------------------------
    // control / status register file
    // ----------------------------------------------------------------
    yolo_csr #(
        .C_BASEADDR (C_BASEADDR),
        .OC_AW      (OC_AW),
        .N_AW       (N_AW),
        .K_AW       (K_AW)
    ) u_csr (
        .clk_i          (clk_i),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .dsc_valid_o    (dsc_valid),
        .dsc_ready_i    (dsc_ready),
        .dsc_oc_o       (dsc_oc),
        .dsc_n_o        (dsc_n),
        .dsc_k_o        (dsc_k),
        .dsc_last_o     (dsc_last),
        .dsc_ih_o       (dsc_ih),
        .dsc_iw_o       (dsc_iw),
        .dsc_ow_o       (dsc_ow),
        .dsc_ic_o       (dsc_ic),
        .dsc_kh_o       (dsc_kh),
        .dsc_kw_o       (dsc_kw),
        .dsc_sh_o       (dsc_sh),
        .dsc_sw_o       (dsc_sw),
        .dsc_ph_o       (dsc_ph),
        .dsc_pw_o       (dsc_pw),
        .dsc_first_o    (dsc_first),
        .dsc_act_o      (dsc_act),
        .dsc_wbase_o    (dsc_wbase),
        .dsc_xbase_o    (dsc_xbase),
        .dsc_ybase_o    (dsc_ybase),
        .dsc_bbase_o    (dsc_bbase),
        .dsc_mbase_o    (dsc_mbase),
        .dsc_sbase_o    (dsc_sbase),
        .lut_we_o       (lut_we),
        .lut_waddr_o    (lut_waddr),
        .lut_wdata_o    (lut_wdata),
        .layer_done_i   (layer_done),
        .all_done_i     (all_done),
        .busy_i         (busy),
        .irq_o          (irq_o)
    );

    // ----------------------------------------------------------------
    // GEMM array
    // ----------------------------------------------------------------
    yolo_gemm_array #(
        .OC_EDGE   (OC_EDGE),
        .N_EDGE    (N_EDGE),
        .K_MAX     (K_MAX),
        .AW        (AW),
        .ROW_AW    (ROW_AW),
        .COL_AW    (COL_AW),
        .ADDR_W    (ADDR_W),
        .LEN_W     (LEN_W),
        .OC_AW     (OC_AW),
        .N_AW      (N_AW),
        .K_AW      (K_AW),
        .TILE_AW   (TILE_AW),
        .MAX_BURST (MAX_BURST)
    ) u_array (
        .clk_i        (clk_i),
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
        .araddr_o     (m_axi_araddr),
        .arlen_o      (m_axi_arlen),
        .arsize_o     (m_axi_arsize),
        .arburst_o    (m_axi_arburst),
        .arvalid_o    (m_axi_arvalid),
        .arready_i    (m_axi_arready),
        .rdata_i      (m_axi_rdata),
        .rlast_i      (m_axi_rlast),
        .rvalid_i     (m_axi_rvalid),
        .rready_o     (m_axi_rready),
        .awaddr_o     (m_axi_awaddr),
        .awlen_o      (m_axi_awlen),
        .awsize_o     (m_axi_awsize),
        .awburst_o    (m_axi_awburst),
        .awvalid_o    (m_axi_awvalid),
        .awready_i    (m_axi_awready),
        .wdata_o      (m_axi_wdata),
        .wstrb_o      (m_axi_wstrb),
        .wlast_o      (m_axi_wlast),
        .wvalid_o     (m_axi_wvalid),
        .wready_i     (m_axi_wready),
        .bvalid_i     (m_axi_bvalid),
        .bresp_i      (m_axi_bresp),
        .bready_o     (m_axi_bready),
        .x_addr_o     (x_addr_o),
        .x_rdata_i    (x_rdata_i),
        .lut_we_i     (lut_we),
        .lut_waddr_i  (lut_waddr),
        .lut_wdata_i  (lut_wdata),
        .layer_done_o (layer_done),
        .all_done_o   (all_done),
        .busy_o       (busy)
    );

endmodule
