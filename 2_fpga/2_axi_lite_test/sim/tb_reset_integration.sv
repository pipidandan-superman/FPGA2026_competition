//====================================================================
// File name   : tb_reset_integration.sv
// Author      : Codex
// Create date : 2026-09-13
// Description : Official reset IP polarity and CSR release regression
// Target      : FPGA
// Revision    : V1.0
//====================================================================
`timescale 1ns/1ps
module tb_reset_integration;
    reg clk = 0;
    reg ext_resetn = 0;
    wire resetn;
    wire faulty_resetn;
    reg arvalid = 0;
    wire arready;
    wire rvalid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    integer result_file;
    always #5 clk = ~clk;

    AXI_LITE_test_control_reset_0 corrected (
        .slowest_sync_clk(clk),
        .ext_reset_in(ext_resetn),
        .aux_reset_in(1'b1),
        .mb_debug_sys_rst(1'b0),
        .dcm_locked(1'b1),
        .peripheral_aresetn(resetn)
    );
    AXI_LITE_test_control_reset_0 faulty (
        .slowest_sync_clk(clk),
        .ext_reset_in(ext_resetn),
        .aux_reset_in(1'b0),
        .mb_debug_sys_rst(1'b0),
        .dcm_locked(1'b1),
        .peripheral_aresetn(faulty_resetn)
    );
    axi_lite_test_top csr (
        .clk(clk),
        .resetn(resetn),
        .s_axi_awaddr(12'b0),
        .s_axi_awprot(3'b0),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(),
        .s_axi_wdata(32'b0),
        .s_axi_wstrb(4'b0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(),
        .s_axi_bresp(),
        .s_axi_bvalid(),
        .s_axi_bready(1'b1),
        .s_axi_araddr(12'b0),
        .s_axi_arprot(3'b0),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(1'b1)
    );
    task automatic check_release;
        repeat (160) @(negedge clk);
        if (resetn !== 1'b1 || faulty_resetn !== 1'b0)
            $fatal(1, "Reset polarity/release failure");
        arvalid = 1;
        do @(posedge clk); while (arready !== 1'b1);
        @(negedge clk);
        arvalid = 0;
        do @(negedge clk); while (rvalid !== 1'b1);
        if (rdata !== 32'h41584c54 || rresp !== 2'b00)
            $fatal(1, "CSR identity after reset mismatch");
        @(negedge clk);
    endtask
    initial begin
        $display("VITA_VIVADO_STAGE OFFICIAL_RESET_IP");
        repeat (30) @(negedge clk);
        ext_resetn = 1;
        check_release();
        ext_resetn = 0;
        repeat (20) @(negedge clk);
        if (resetn !== 1'b0) $fatal(1, "External reset did not assert");
        ext_resetn = 1;
        check_release();
        result_file = $fopen("reset_result.json", "w");
        $fdisplay(result_file, "{\"marker\":\"AXILT_OFFICIAL_RESET_PASS\",\"fault_reproduced\":true,\"csr_reads\":2}");
        $fclose(result_file);
        $display("AXILT_OFFICIAL_RESET_PASS fault held reset; corrected CSR reads=2");
        $display("VITA_VIVADO_RESULT PASS");
        $display("EES_VIVADO_RESULT PASS");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Reset integration watchdog");
    end
endmodule
