//====================================================================
// File name   : hdmi_colorbar_vtc_top_reset_tb.sv
// Author      : LSL
// Create date : 2026-09-05
// Description : Verify immediate reset assertion when S1 stops pix_clk
// Target      : ModelSim
// Revision    : V1.1
//====================================================================

`timescale 1ns / 1ps

module clk_wiz_0 (
    output wire clk_out1 ,
    input  wire reset    ,
    output wire locked   ,
    input  wire clk_in1
);

    assign clk_out1 = clk_in1 & ~reset;
    assign locked   = ~reset;

endmodule

module ODDR #(
    parameter DDR_CLK_EDGE = "SAME_EDGE",
    parameter INIT         = 1'b0       ,
    parameter SRTYPE       = "SYNC"
) (
    input  wire C  ,
    input  wire CE ,
    input  wire D1 ,
    input  wire D2 ,
    input  wire R  ,
    input  wire S  ,
    output wire Q
);

    assign Q = R ? 1'b0 : (S ? 1'b1 : (CE ? (C ? D1 : D2) : INIT));

endmodule

module hdmi_colorbar_vtc_top_reset_tb;

    reg         sys_clk_100m;
    reg         reset_n;
    reg         SW0;
    tri         hdmi_sda;
    wire [15:0] hdmi_data;
    wire        hdmi_hsync;
    wire        hdmi_vsync;
    wire        hdmi_de;
    wire        hdmi_clk;
    wire        hdmi_scl;
    wire [ 7:0] led;
    integer     result_file;

    pullup(hdmi_scl);
    pullup(hdmi_sda);

    hdmi_colorbar_vtc_top u_dut (
        .sys_clk_100m(sys_clk_100m),
        .reset_n     (reset_n)     ,
        .SW0         (SW0)         ,
        .HDMI_INT    (1'b0)        ,
        .HDMI_SDA    (hdmi_sda)    ,
        .HDMI_DATA   (hdmi_data)   ,
        .HDMI_HSYNC  (hdmi_hsync)  ,
        .HDMI_VSYNC  (hdmi_vsync)  ,
        .HDMI_DE     (hdmi_de)     ,
        .HDMI_CLK    (hdmi_clk)    ,
        .HDMI_SCL    (hdmi_scl)    ,
        .LED         (led)
    );

    always #5 sys_clk_100m = ~sys_clk_100m;

    task automatic check_colorbar_value (
        input logic [ 9:0] expected_x  ,
        input logic [23:0] expected_rgb
    );
        begin
            wait ((u_dut.vtc_active == 1'b1) && (u_dut.pixel_x == expected_x));
            #1;
            if (u_dut.test_rgb !== expected_rgb) begin
                $fatal(1, "COLORBAR_FAIL: x=%0d got=%06h expected=%06h",
                       expected_x, u_dut.test_rgb, expected_rgb);
            end
        end
    endtask

    initial begin
        sys_clk_100m = 1'b0;
        reset_n      = 1'b0;
        SW0          = 1'b0;

        #20;
        if ((u_dut.pixel_reset_n !== 1'b0) || (led !== 8'hA5)) begin
            $fatal(1, "RESET_INITIAL_FAIL: pixel_reset_n=%b led=%02h",
                   u_dut.pixel_reset_n, led);
        end

        reset_n = 1'b1;
        repeat (12) @(posedge sys_clk_100m);
        #1;
        if (u_dut.pixel_reset_n !== 1'b1) begin
            $fatal(1, "RESET_RELEASE_FAIL: pixel_reset_n=%b", u_dut.pixel_reset_n);
        end

        check_colorbar_value(10'd128, 24'h000000);
        check_colorbar_value(10'd256, 24'hFF0000);
        check_colorbar_value(10'd384, 24'h0000FF);
        check_colorbar_value(10'd512, 24'h00FF00);
        check_colorbar_value(10'd0,   24'hFFFFFF);

        #3;
        reset_n = 1'b0;
        #1;
        if ((u_dut.pixel_reset_n !== 1'b0) || (led !== 8'hA5)) begin
            $fatal(1, "RESET_ASSERT_FAIL: pixel_reset_n=%b led=%02h",
                   u_dut.pixel_reset_n, led);
        end

        result_file = $fopen({
            "E:/competition/4_metrics/logs/2026-09-05_adv7511_i2c_rewrite_run01/",
            "top_colorbar_result.txt"},
            "w"
        );
        $fdisplay(result_file,
                  "TOP_COLORBAR_RESET_PASS: five colors, A5 reset signature, reset verified");
        $fclose(result_file);
        $display("TOP_COLORBAR_RESET_PASS: five colors, A5 reset signature, reset verified");
        $finish;
    end

endmodule
