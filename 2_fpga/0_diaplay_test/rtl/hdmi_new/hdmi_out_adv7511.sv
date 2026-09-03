/************************************************************************
 * File Name       : hdmi_out_adv7511.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : hdmi_out_adv7511
 * Description     : HDMI output top level for ADV7511, containing RGB to
 *                   YCbCr422 conversion, initialization and aligned output.
 * Dependencies    : rgb2ycbcr422, adv7511_i2c_init
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

module hdmi_out_adv7511 #(
    parameter bit          FAST_SIM        = 1'b0      ,
    parameter int unsigned PIX_CLK_FREQ_HZ = 25_175_000
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
    wire        conversion_de;
    wire        conversion_hsync;
    wire        conversion_vsync;
    wire        initialization_done;
    wire        initialization_error;

    rgb2ycbcr422 u_rgb2ycbcr422 (
        .clk_i   (PIX_CLK)        ,
        .rst_n_i (RST_N)          ,
        .rgb888_i(RGB888)         ,
        .de_i    (DE)             ,
        .hsync_i (H_SYNC)         ,
        .vsync_i (V_SYNC)         ,
        .data_o  (conversion_data),
        .de_o    (conversion_de)  ,
        .hsync_o (conversion_hsync),
        .vsync_o (conversion_vsync)
    );

    adv7511_cfg_top #(
        .FAST_SIM          (FAST_SIM)        ,
        .CLK_FREQ_HZ       (PIX_CLK_FREQ_HZ) ,
        .POWER_UP_DELAY_MS (120)             ,
        .DEVICE_ADDR       (7'h39)           ,
        .IIC_CLOCK_DIVIDER (252)             ,
        .PROTOCOL_TIMEOUT_MS(3000)
    ) u_adv7511_cfg_top (
        .clk_i      (PIX_CLK)            ,
        .rst_n_i    (RST_N)              ,
        .cfg_done_o (initialization_done),
        .cfg_error_o(initialization_error),
        .scl_o      (HDMI_SCL)           ,
        .sda_io     (HDMI_SDA)
    );

    always_ff @(posedge PIX_CLK or negedge RST_N) begin
        if (!RST_N) begin
            HDMI_DATA <= 16'd0;
            HDMI_DE <= 1'b0;
            HDMI_HSYNC <= 1'b0;
            HDMI_VSYNC <= 1'b0;
        end else begin
            HDMI_DATA <= conversion_data;
            HDMI_DE <= conversion_de;
            HDMI_HSYNC <= conversion_hsync;
            HDMI_VSYNC <= conversion_vsync;
        end
    end

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT        (1'b0)      ,
        .SRTYPE      ("SYNC")
    ) u_hdmi_clk_oddr (
        .C (PIX_CLK),
        .CE(1'b1)   ,
        .D1(1'b1)   ,
        .D2(1'b0)   ,
        .R (1'b0)   ,
        .S (1'b0)   ,
        .Q (HDMI_CLK)
    );

endmodule
