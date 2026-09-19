//====================================================================
// File name   : axi_lite_test_top.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Independent PS-PL AXI-Lite register test
// Target      : FPGA
// Revision    : V1.0
//====================================================================
module axi_lite_test_top (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET resetn, FREQ_HZ 100000000" *)
    input  wire         clk           ,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire         resetn        ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
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
    input  wire         s_axi_rready  
);
    wire         wr_valid;
    wire         wr_ready;
    wire [11:0]  wr_addr;
    wire [31:0]  wr_data;
    wire [3:0]   wr_strb;
    wire         wr_rsp_valid;
    wire         wr_rsp_ready;
    wire [1:0]   wr_rsp;
    wire         rd_valid;
    wire         rd_ready;
    wire [11:0]  rd_addr;
    wire         rd_rsp_valid;
    wire         rd_rsp_ready;
    wire [31:0]  rd_data;
    wire [1:0]   rd_rsp;
    wire exec_start, exec_done;
    wire [31:0] exec_input, exec_result;

    axi_lite_slave u_slave (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .s_axi_awaddr   (s_axi_awaddr  ),
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
        .s_axi_arvalid  (s_axi_arvalid ),
        .s_axi_arready  (s_axi_arready ),
        .s_axi_rdata    (s_axi_rdata   ),
        .s_axi_rresp    (s_axi_rresp   ),
        .s_axi_rvalid   (s_axi_rvalid  ),
        .s_axi_rready   (s_axi_rready  ),
        .wr_valid       (wr_valid      ),
        .wr_ready       (wr_ready      ),
        .wr_addr        (wr_addr       ),
        .wr_data        (wr_data       ),
        .wr_strb        (wr_strb       ),
        .wr_rsp_valid   (wr_rsp_valid  ),
        .wr_rsp_ready   (wr_rsp_ready  ),
        .wr_rsp         (wr_rsp        ),
        .rd_valid       (rd_valid      ),
        .rd_ready       (rd_ready      ),
        .rd_addr        (rd_addr       ),
        .rd_rsp_valid   (rd_rsp_valid  ),
        .rd_rsp_ready   (rd_rsp_ready  ),
        .rd_data        (rd_data       ),
        .rd_rsp         (rd_rsp        )
    );

    axi_lite_reg_bank u_regs (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .wr_valid       (wr_valid      ),
        .wr_ready       (wr_ready      ),
        .wr_addr        (wr_addr       ),
        .wr_data        (wr_data       ),
        .wr_strb        (wr_strb       ),
        .wr_rsp_valid   (wr_rsp_valid  ),
        .wr_rsp_ready   (wr_rsp_ready  ),
        .wr_rsp         (wr_rsp        ),
        .rd_valid       (rd_valid      ),
        .rd_ready       (rd_ready      ),
        .rd_addr        (rd_addr       ),
        .rd_rsp_valid   (rd_rsp_valid  ),
        .rd_rsp_ready   (rd_rsp_ready  ),
        .rd_data        (rd_data       ),
        .rd_rsp         (rd_rsp        ),
        .exec_start     (exec_start    ),
        .exec_input     (exec_input    ),
        .exec_done      (exec_done     ),
        .exec_result    (exec_result   )
    );

    reg_test_executor u_executor (
        .clk        (clk        ),
        .resetn     (resetn     ),
        .start      (exec_start ),
        .test_input (exec_input ),
        .done       (exec_done  ),
        .result     (exec_result)
    );
endmodule

