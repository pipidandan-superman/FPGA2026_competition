//====================================================================
// File name   : hdmi_out_adv7511_v1_0.v
// Author      : LSL
// Create date : 2026-09-06
// Description : RGB888 HDMI output top with externally supplied timing
// Target      : FPGA
// Revision    : V1.0
//====================================================================

module hdmi_out_adv7511_v1_0 #(
    parameter              FAST_SIM        = 1'b0       ,
    parameter              ENABLE_READBACK = 1'b1       ,
    parameter              PIX_CLK_FREQ_HZ = 25_000_000
) (
    input  wire               PIX_CLK    ,
    input  wire               RST_N      ,
    input  wire        [23:0] RGB888     ,
    input  wire               DE         ,
    input  wire               H_SYNC     ,
    input  wire               V_SYNC     ,
    input  wire               HDMI_INT   ,
    inout  wire               HDMI_SDA   ,
    output reg         [15:0] HDMI_DATA  ,
    output wire               HDMI_CLK   ,
    output reg                HDMI_HSYNC ,
    output reg                HDMI_VSYNC ,
    output reg                HDMI_DE    ,
    output wire               HDMI_SCL
);

    wire [15:0] conversion_data;
    wire [15:0] physical_data;
    wire        conversion_de;
    wire        conversion_hsync;
    wire        conversion_vsync;
    wire        cfg_done;
    wire        cfg_error;
    wire [ 5:0] cfg_readback_match;
    wire [47:0] cfg_readback_data;

    rgb2ycbcr422 u_rgb2ycbcr422 (
        .clk_i      (PIX_CLK)          ,
        .rst_n_i    (RST_N)            ,
        .rgb888_i   (RGB888)           ,
        .de_i       (DE)               ,
        .hsync_i    (H_SYNC)           ,
        .vsync_i    (V_SYNC)           ,
        .data_o     (conversion_data)  ,
        .de_o       (conversion_de)    ,
        .hsync_o    (conversion_hsync) ,
        .vsync_o    (conversion_vsync)
    );

    // The successful EES-331 project maps {Y,Cb/Cr} to the reversed 16-bit
    // physical bus. Keep this board-proven swap unchanged.
    assign physical_data = {conversion_data[7:0], conversion_data[15:8]};

    adv7511_cfg_top #(
        .FAST_SIM            (FAST_SIM)        ,
        .ENABLE_READBACK     (ENABLE_READBACK) ,
        .CLK_FREQ_HZ         (PIX_CLK_FREQ_HZ) ,
        .POWER_UP_DELAY_MS   (200)             ,
        .DEVICE_ADDR         (7'h39)           ,
        .IIC_CLOCK_DIVIDER   (252)             ,
        .PROTOCOL_TIMEOUT_MS (3000)
    ) u_adv7511_cfg_top (
        .clk_i            (PIX_CLK)            ,
        .rst_n_i          (RST_N)              ,
        .cfg_done_o       (cfg_done)           ,
        .cfg_error_o      (cfg_error)          ,
        .readback_match_o (cfg_readback_match) ,
        .readback_data_o  (cfg_readback_data)  ,
        .scl_o            (HDMI_SCL)           ,
        .sda_io           (HDMI_SDA)
    );

    always @(negedge PIX_CLK or negedge RST_N) begin
        if (!RST_N) begin
            HDMI_DATA   <= 16'd0;
            HDMI_DE     <= 1'b0;
            HDMI_HSYNC  <= 1'b0;
            HDMI_VSYNC  <= 1'b0;
        end else begin
            HDMI_DATA   <= physical_data;
            HDMI_DE     <= conversion_de;
            HDMI_HSYNC  <= conversion_hsync;
            HDMI_VSYNC  <= conversion_vsync;
        end
    end

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT        (1'b0)      ,
        .SRTYPE      ("SYNC")
    ) u_hdmi_clk_oddr (
        .C  (PIX_CLK),
        .CE (1'b1)   ,
        .D1 (1'b1)   ,
        .D2 (1'b0)   ,
        .R  (1'b0)   ,
        .S  (1'b0)   ,
        .Q  (HDMI_CLK)
    );

    wire unused_hdmi_int = HDMI_INT;
    wire unused_cfg_status = cfg_done | cfg_error |
                             (|cfg_readback_match);

endmodule
