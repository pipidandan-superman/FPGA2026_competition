//====================================================================
// File name   : tb_slave_delay.sv
// Author      : Codex
// Create date : 2026-09-12
// Description : Independent PS-PL AXI-Lite register test
// Target      : FPGA
// Revision    : V1.0
//====================================================================
`timescale 1ns/1ps
module tb_slave_delay (
    output reg done = 0
);
    reg          clk = 0;
    reg          resetn = 0;
    reg  [11:0]  s_axi_awaddr = 0;
    reg          s_axi_awvalid = 0;
    wire         s_axi_awready;
    reg  [31:0]  s_axi_wdata = 0;
    reg  [3:0]   s_axi_wstrb = 0;
    reg          s_axi_wvalid = 0;
    wire         s_axi_wready;
    wire [1:0]   s_axi_bresp;
    wire         s_axi_bvalid;
    reg          s_axi_bready = 0;
    reg  [11:0]  s_axi_araddr = 0;
    reg          s_axi_arvalid = 0;
    wire         s_axi_arready;
    wire [31:0]  s_axi_rdata;
    wire [1:0]   s_axi_rresp;
    wire         s_axi_rvalid;
    reg          s_axi_rready = 0;
    wire         wr_valid;
    reg          wr_ready = 0;
    wire [11:0]  wr_addr;
    wire [31:0]  wr_data;
    wire [3:0]   wr_strb;
    reg          wr_rsp_valid = 0;
    wire         wr_rsp_ready;
    reg  [1:0]   wr_rsp = 0;
    wire         rd_valid;
    reg          rd_ready = 0;
    wire [11:0]  rd_addr;
    reg          rd_rsp_valid = 0;
    wire         rd_rsp_ready;
    reg  [31:0]  rd_data = 0;
    reg  [1:0]   rd_rsp = 0;
    always #5 clk = ~clk;
    axi_lite_slave dut (
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

    reg writer_done = 0, reader_done = 0;
    initial begin
        repeat (4) @(negedge clk);
        resetn = 1;
        fork
            begin
                @(negedge clk); s_axi_wdata = 32'habcdef12; s_axi_wstrb = 4'h5;
                s_axi_wvalid = 1;
                do @(posedge clk); while (!s_axi_wready);
                @(negedge clk); s_axi_wvalid = 0;
                repeat (13) @(negedge clk);
                s_axi_awaddr = 12'h124; s_axi_awvalid = 1;
                do @(posedge clk); while (!s_axi_awready);
                @(negedge clk); s_axi_awvalid = 0;
                wait (s_axi_bvalid);
                repeat (29) begin
                    @(negedge clk);
                    if (!s_axi_bvalid || s_axi_bresp !== 2)
                        $fatal(1, "Delayed write response unstable");
                end
                s_axi_bready = 1;
                @(negedge clk); s_axi_bready = 0;
                writer_done = 1;
            end
            begin
                @(negedge clk); s_axi_araddr = 12'h678; s_axi_arvalid = 1;
                do @(posedge clk); while (!s_axi_arready);
                @(negedge clk); s_axi_arvalid = 0;
                wait (s_axi_rvalid);
                repeat (21) begin
                    @(negedge clk);
                    if (!s_axi_rvalid || s_axi_rdata !== 32'hfedc5678 || s_axi_rresp !== 2)
                        $fatal(1, "Delayed read response unstable");
                end
                s_axi_rready = 1;
                @(negedge clk); s_axi_rready = 0;
                reader_done = 1;
            end
            begin
                wait (wr_valid);
                repeat (32) begin
                    @(negedge clk);
                    if (!wr_valid || wr_addr !== 12'h124 ||
                        wr_data !== 32'habcdef12 || wr_strb !== 5)
                        $fatal(1, "Write request changed while backend stalled");
                end
                wr_ready = 1;
                @(negedge clk); wr_ready = 0;
                repeat (37) @(negedge clk);
                wr_rsp = 2; wr_rsp_valid = 1;
                do @(posedge clk); while (!wr_rsp_ready);
                @(negedge clk); wr_rsp_valid = 0;
            end
            begin
                wait (rd_valid);
                repeat (49) begin
                    @(negedge clk);
                    if (!rd_valid || rd_addr !== 12'h678)
                        $fatal(1, "Read request changed while backend stalled");
                end
                rd_ready = 1;
                @(negedge clk); rd_ready = 0;
                repeat (31) @(negedge clk);
                rd_data = 32'hfedc5678; rd_rsp = 2; rd_rsp_valid = 1;
                do @(posedge clk); while (!rd_rsp_ready);
                @(negedge clk); rd_rsp_valid = 0;
            end
        join
        wait (reader_done && writer_done);
        repeat (20) @(negedge clk);
        if (s_axi_bvalid || s_axi_rvalid || wr_valid || rd_valid)
            $fatal(1, "Delayed backend produced extra transaction");
        $display("AXILT_DELAYED_BACKEND_PASS");
        done = 1;
    end
endmodule

