//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
//Date        : Sun Sep 13 09:58:05 2026
//Host        : HC-202510241838 running 64-bit major release  (build 9200)
//Command     : generate_target display_test_wrapper.bd
//Design      : display_test_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module display_test_wrapper
   (BT_RESET_N,
    BT_RX,
    BT_TX,
    DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    FPGA_BT_3V3,
    HDMI_CLK_0,
    HDMI_DATA_0,
    HDMI_DE_0,
    HDMI_HSYNC_0,
    HDMI_INT_0,
    HDMI_SCL_0,
    HDMI_SDA_0,
    HDMI_VSYNC_0,
    PL_RS232_RX,
    PL_RS232_TX,
    cam_data_0,
    cam_href_0,
    cam_pclk_0,
    cam_vsync_0,
    cam_xclk_0,
    clk_in1_0,
    resetn_0,
    sccb_cfg_done_0,
    sccb_clk_0,
    sccb_data_0);
  output BT_RESET_N;
  output BT_RX;
  input BT_TX;
  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;
  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;
  output FPGA_BT_3V3;
  output HDMI_CLK_0;
  output [15:0]HDMI_DATA_0;
  output HDMI_DE_0;
  output HDMI_HSYNC_0;
  input HDMI_INT_0;
  output HDMI_SCL_0;
  inout HDMI_SDA_0;
  output HDMI_VSYNC_0;
  input PL_RS232_RX;
  output PL_RS232_TX;
  input [7:0]cam_data_0;
  input cam_href_0;
  input cam_pclk_0;
  input cam_vsync_0;
  output cam_xclk_0;
  input clk_in1_0;
  input resetn_0;
  output sccb_cfg_done_0;
  output sccb_clk_0;
  inout sccb_data_0;

  wire BT_RESET_N;
  wire BT_RX;
  wire BT_TX;
  wire [14:0]DDR_addr;
  wire [2:0]DDR_ba;
  wire DDR_cas_n;
  wire DDR_ck_n;
  wire DDR_ck_p;
  wire DDR_cke;
  wire DDR_cs_n;
  wire [3:0]DDR_dm;
  wire [31:0]DDR_dq;
  wire [3:0]DDR_dqs_n;
  wire [3:0]DDR_dqs_p;
  wire DDR_odt;
  wire DDR_ras_n;
  wire DDR_reset_n;
  wire DDR_we_n;
  wire FIXED_IO_ddr_vrn;
  wire FIXED_IO_ddr_vrp;
  wire [53:0]FIXED_IO_mio;
  wire FIXED_IO_ps_clk;
  wire FIXED_IO_ps_porb;
  wire FIXED_IO_ps_srstb;
  wire FPGA_BT_3V3;
  wire HDMI_CLK_0;
  wire [15:0]HDMI_DATA_0;
  wire HDMI_DE_0;
  wire HDMI_HSYNC_0;
  wire HDMI_INT_0;
  wire HDMI_SCL_0;
  wire HDMI_SDA_0;
  wire HDMI_VSYNC_0;
  wire PL_RS232_RX;
  wire PL_RS232_TX;
  wire [7:0]cam_data_0;
  wire cam_href_0;
  wire cam_pclk_0;
  wire cam_vsync_0;
  wire cam_xclk_0;
  wire clk_in1_0;
  wire resetn_0;
  wire sccb_cfg_done_0;
  wire sccb_clk_0;
  wire sccb_data_0;

  display_test display_test_i
       (.BT_RESET_N(BT_RESET_N),
        .BT_RX(BT_RX),
        .BT_TX(BT_TX),
        .DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .FPGA_BT_3V3(FPGA_BT_3V3),
        .HDMI_CLK_0(HDMI_CLK_0),
        .HDMI_DATA_0(HDMI_DATA_0),
        .HDMI_DE_0(HDMI_DE_0),
        .HDMI_HSYNC_0(HDMI_HSYNC_0),
        .HDMI_INT_0(HDMI_INT_0),
        .HDMI_SCL_0(HDMI_SCL_0),
        .HDMI_SDA_0(HDMI_SDA_0),
        .HDMI_VSYNC_0(HDMI_VSYNC_0),
        .PL_RS232_RX(PL_RS232_RX),
        .PL_RS232_TX(PL_RS232_TX),
        .cam_data_0(cam_data_0),
        .cam_href_0(cam_href_0),
        .cam_pclk_0(cam_pclk_0),
        .cam_vsync_0(cam_vsync_0),
        .cam_xclk_0(cam_xclk_0),
        .clk_in1_0(clk_in1_0),
        .resetn_0(resetn_0),
        .sccb_cfg_done_0(sccb_cfg_done_0),
        .sccb_clk_0(sccb_clk_0),
        .sccb_data_0(sccb_data_0));
endmodule
