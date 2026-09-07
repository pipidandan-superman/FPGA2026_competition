//====================================================================
// File name   : hdmi_colorbar_vtc_top_mode_tb.sv
// Author      : LSL / Codex
// Create date : 2026-09-05
// Description : Verify frame-safe modes and EES-331 physical byte mapping
// Target      : ModelSim
// Revision    : V1.4
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

module hdmi_colorbar_vtc_top_mode_tb;

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

    always @(negedge u_dut.pix_clk) begin : check_board_lanes
        reg [15:0] launched_word;
        launched_word = u_dut.physical_data;
        if (u_dut.pixel_reset_n) begin
            #1;
            if (hdmi_data !== launched_word) begin
                $fatal(1, "BOARD_LANE_FAIL: HDMI_DATA must equal byte-swapped physical_data");
            end
        end
    end

    function automatic [15:0] expected_data (
        input integer color_index,
        input integer chroma_is_cr
    );
        begin
            case (color_index)
                0: expected_data = chroma_is_cr ? 16'hEB80 : 16'hEB80;
                1: expected_data = chroma_is_cr ? 16'h1080 : 16'h1080;
                2: expected_data = chroma_is_cr ? 16'h51EF : 16'h515A;
                3: expected_data = chroma_is_cr ? 16'h286D : 16'h28EF;
                4: expected_data = chroma_is_cr ? 16'h9022 : 16'h9035;
                default: expected_data = 16'h1080;
            endcase
        end
    endfunction

    task automatic check_selected_data (
        input integer expected_x,
        input integer color_index
    );
        reg [15:0] expected_word;
        reg [9:0]  target_x;
        integer    guard_cycles;
        begin
            target_x = expected_x + 2;
            begin : find_pixel
                for (guard_cycles = 0; guard_cycles < 500000; guard_cycles = guard_cycles + 1) begin
                    @(posedge sys_clk_100m);
                    if (u_dut.pixel_x === target_x) begin
                        #1;
                        expected_word = expected_data(color_index, expected_x % 2);
                        if (u_dut.selected_data !== expected_word) begin
                            $fatal(1, "MODE_DATA_FAIL: x=%0d got=%04h expected=%04h mode=%b",
                                   expected_x, u_dut.selected_data, expected_word,
                                   u_dut.video_mode_direct);
                        end
                        if (u_dut.physical_data !==
                            {expected_word[7:0], expected_word[15:8]}) begin
                            $fatal(1, "BOARD_SWAP_FAIL: x=%0d got=%04h expected=%04h",
                                   expected_x, u_dut.physical_data,
                                   {expected_word[7:0], expected_word[15:8]});
                        end
                        disable find_pixel;
                    end
                end
                $fatal(1, "MODE_DATA_TIMEOUT: x=%0d target=%0d", expected_x, target_x);
            end
        end
    endtask

    initial begin
        sys_clk_100m = 1'b0;
        reset_n      = 1'b0;
        SW0          = 1'b0;

        #20;
        if (led !== 8'hA5) begin
            $fatal(1, "MODE_RESET_FAIL: led=%02h", led);
        end

        reset_n = 1'b1;
        repeat (16) @(posedge sys_clk_100m);
        wait ((u_dut.pixel_reset_n == 1'b1) &&
              (u_dut.video_mode_direct == 1'b0));

        check_selected_data(0,   0);
        check_selected_data(128, 1);
        check_selected_data(256, 2);
        check_selected_data(384, 3);
        check_selected_data(512, 4);

        // A mid-frame switch must not affect the active frame.
        wait ((u_dut.vtc_active == 1'b1) &&
              (u_dut.pixel_y == 10'd100) &&
              (u_dut.pixel_x == 10'd200));
        SW0 = 1'b1;
        repeat (20) @(posedge sys_clk_100m);
        if (u_dut.video_mode_direct !== 1'b0) begin
            $fatal(1, "MIDFRAME_SWITCH_FAIL: mode changed before frame boundary");
        end

        // Wait for the next frame origin, then allow the synchronizer to settle.
        wait ((u_dut.pixel_y != 10'd0));
        wait ((u_dut.pixel_x == 10'd0) && (u_dut.pixel_y == 10'd0));
        repeat (4) @(posedge sys_clk_100m);
        if (u_dut.video_mode_direct !== 1'b1) begin
            $fatal(1, "FRAME_SWITCH_FAIL: direct mode not latched at frame boundary");
        end

        check_selected_data(0,   0);
        check_selected_data(128, 1);
        check_selected_data(256, 2);
        check_selected_data(384, 3);
        check_selected_data(512, 4);

        result_file = $fopen(
            "E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/mode_result.txt",
            "w"
        );
        $fdisplay(result_file,
                  "MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch");
        $fclose(result_file);
        $display("MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch");
        $finish;
    end

endmodule
