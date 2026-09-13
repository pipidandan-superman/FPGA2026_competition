//====================================================================
// File name   : tb_video_axi_lite_control.sv
// Author      : Codex
// Create date : 2026-09-13
// Description : 50 MHz integration smoke test for the video AXI wrapper
// Target      : Vivado XSim
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module tb_video_axi_lite_control;

    reg          clk = 1'b0;
    reg          resetn = 1'b0;
    reg  [11:0]  s_axi_awaddr = 12'b0;
    reg  [2:0]   s_axi_awprot = 3'b0;
    reg          s_axi_awvalid = 1'b0;
    wire         s_axi_awready;
    reg  [31:0]  s_axi_wdata = 32'b0;
    reg  [3:0]   s_axi_wstrb = 4'b0;
    reg          s_axi_wvalid = 1'b0;
    wire         s_axi_wready;
    wire [1:0]   s_axi_bresp;
    wire         s_axi_bvalid;
    reg          s_axi_bready = 1'b0;
    reg  [11:0]  s_axi_araddr = 12'b0;
    reg  [2:0]   s_axi_arprot = 3'b0;
    reg          s_axi_arvalid = 1'b0;
    wire         s_axi_arready;
    wire [31:0]  s_axi_rdata;
    wire [1:0]   s_axi_rresp;
    wire         s_axi_rvalid;
    reg          s_axi_rready = 1'b0;

    always #10 clk = ~clk;

    video_axi_lite_control_top dut (
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
        .s_axi_rready   (s_axi_rready  )
    );

    task automatic fail(input string reason);
        $display("MAIN_AXI_WRAPPER_FAIL %s time=%0t", reason, $time);
        $display("VITA_VIVADO_RESULT FAIL");
        $fatal(1, "%s", reason);
    endtask

    task automatic send_aw(input [11:0] address);
        @(negedge clk);
        s_axi_awaddr = address;
        s_axi_awvalid = 1'b1;
        do @(posedge clk); while (s_axi_awready !== 1'b1);
        @(negedge clk);
        s_axi_awvalid = 1'b0;
    endtask

    task automatic send_w(input [31:0] data, input [3:0] strobe);
        @(negedge clk);
        s_axi_wdata = data;
        s_axi_wstrb = strobe;
        s_axi_wvalid = 1'b1;
        do @(posedge clk); while (s_axi_wready !== 1'b1);
        @(negedge clk);
        s_axi_wvalid = 1'b0;
    endtask

    task automatic write_reg(input [11:0] address, input [31:0] data,
                             input [3:0] strobe);
        fork
            send_aw(address);
            send_w(data, strobe);
        join
        wait (s_axi_bvalid === 1'b1);
        if (s_axi_bresp !== 2'b00) begin
            fail($sformatf("write response address=%h response=%h", address, s_axi_bresp));
        end
        @(negedge clk);
        s_axi_bready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        s_axi_bready = 1'b0;
    endtask

    task automatic read_reg(input [11:0] address, output [31:0] data);
        @(negedge clk);
        s_axi_araddr = address;
        s_axi_arvalid = 1'b1;
        do @(posedge clk); while (s_axi_arready !== 1'b1);
        @(negedge clk);
        s_axi_arvalid = 1'b0;
        wait (s_axi_rvalid === 1'b1);
        if (s_axi_rresp !== 2'b00) begin
            fail($sformatf("read response address=%h response=%h", address, s_axi_rresp));
        end
        data = s_axi_rdata;
        @(negedge clk);
        s_axi_rready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        s_axi_rready = 1'b0;
    endtask

    task automatic expect_reg(input [11:0] address, input [31:0] expected);
        reg [31:0] actual;
        read_reg(address, actual);
        if (actual !== expected) begin
            fail($sformatf("read mismatch address=%h actual=%h expected=%h",
                           address, actual, expected));
        end
    endtask

    integer polls;
    reg [31:0] status;
    reg simulation_complete = 1'b0;

    initial begin
        repeat (5) @(negedge clk);
        resetn = 1'b1;
        repeat (3) @(negedge clk);

        expect_reg(12'h000, 32'h41584c54);
        expect_reg(12'h004, 32'h00010000);
        expect_reg(12'h008, 32'h00000001);

        write_reg(12'h00c, 32'h11223344, 4'b1111);
        write_reg(12'h00c, 32'haabbccdd, 4'b0101);
        expect_reg(12'h00c, 32'h11bb33dd);

        write_reg(12'h010, 32'h13579bdf, 4'b1111);
        write_reg(12'h014, 32'h00000001, 4'b1111);
        write_reg(12'h018, 32'h00000001, 4'b1111);
        polls = 0;
        status = 32'b0;
        while (!status[2] && polls < 20) begin
            read_reg(12'h01c, status);
            polls = polls + 1;
        end
        if (!status[2] || status[1]) begin
            fail("command did not complete at 50 MHz");
        end
        expect_reg(12'h020, 32'h00000001);
        expect_reg(12'h024, 32'h00000001);
        expect_reg(12'h028, 32'heca86420);
        expect_reg(12'h030, 32'h00000001);
        write_reg(12'h018, 32'h00000002, 4'b1111);
        expect_reg(12'h01c, 32'h00000001);

        simulation_complete = 1'b1;
        $display("MAIN_AXI_WRAPPER_SIM_PASS clock_hz=50000000");
        $display("VITA_VIVADO_RESULT PASS");
        $display("EES_VIVADO_RESULT PASS");
    end

    initial begin
        #100000;
        if (!simulation_complete) begin
            fail("simulation watchdog");
        end else begin
            $display("MAIN_AXI_WRAPPER_WATCHDOG_OK");
        end
    end

endmodule
