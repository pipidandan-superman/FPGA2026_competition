//====================================================================
// File name   : video_axi_action_uart_top.v
// Author      : Codex
// Create date : 2026-09-13
// Description : 50 MHz BD wrapper for the AXI action LED and UART control block
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module video_axi_action_uart_top (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET resetn, FREQ_HZ 50000000" *)
    input  wire         clk           ,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire         resetn        ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, FREQ_HZ 50000000, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_REGION 0, HAS_QOS 0, HAS_PROT 1, HAS_WSTRB 1, MAX_BURST_LENGTH 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [11:0]  s_axi_awaddr  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]   s_axi_awprot  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire         s_axi_awvalid ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire         s_axi_awready ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]  s_axi_wdata   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]   s_axi_wstrb   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire         s_axi_wvalid  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire         s_axi_wready  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]   s_axi_bresp   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire         s_axi_bvalid  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire         s_axi_bready  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [11:0]  s_axi_araddr  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]   s_axi_arprot  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire         s_axi_arvalid ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire         s_axi_arready ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0]  s_axi_rdata   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]   s_axi_rresp   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire         s_axi_rvalid  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire         s_axi_rready  ,
    output wire         PL_RS232_TX   ,
    output wire [6:0]   ACTION_LED
);

    axi_action_control_top u_action (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .s_axi_awaddr   (s_axi_awaddr  ),
        .s_axi_awprot   (s_axi_awprot  ),
        .s_axi_awvalid  (s_axi_awvalid ),
        .s_axi_awready  (s_axi_awready ),
        .s_axi_wdata    (s_axi_wdata   ),
        .s_axi_wstrb    (s_axi_wstrb   ),
        .s_axi_wvalid   (s_axi_wvalid  ),
        .s_axi_wready   (s_axi_wready  ),
        .s_axi_bresp    (s_axi_bresp   ),
        .s_axi_bvalid   (s_axi_bvalid  ),
        .s_axi_bready   (s_axi_bready  ),
        .s_axi_araddr   (s_axi_araddr  ),
        .s_axi_arprot   (s_axi_arprot  ),
        .s_axi_arvalid  (s_axi_arvalid ),
        .s_axi_arready  (s_axi_arready ),
        .s_axi_rdata    (s_axi_rdata   ),
        .s_axi_rresp    (s_axi_rresp   ),
        .s_axi_rvalid   (s_axi_rvalid  ),
        .s_axi_rready   (s_axi_rready  ),
        .uart_tx        (PL_RS232_TX   ),
        .action_led     (ACTION_LED    )
    );

endmodule
