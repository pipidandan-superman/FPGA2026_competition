//====================================================================
// File name   : hdmi_colorbar_vtc_top.v
// Author      : LSL
// Create date : 2026-09-04
// Description : Standalone 480p HDMI colorbar test without PS
// Target      : Zynq-7020 EES-331 board
// Revision    : V1.0
//====================================================================

module hdmi_colorbar_vtc_top (
    input  wire        sys_clk_100m,
    input  wire        reset_n     ,
    input  wire        HDMI_INT    ,
    inout  wire        HDMI_SDA    ,
    output wire [15:0] HDMI_DATA   ,
    output wire        HDMI_HSYNC  ,
    output wire        HDMI_VSYNC  ,
    output wire        HDMI_DE     ,
    output wire        HDMI_CLK    ,
    output wire        HDMI_SCL
);

    wire pix_clk;
    wire clock_locked;
    wire pixel_reset_n;

    wire vtc_active;
    wire vtc_hsync;
    wire vtc_vsync;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;

    reg [23:0] rgb_colorbar;
    reg [7:0] pixel_reset_shift = 8'hff;

    clk_wiz_0 u_clk_wiz_0 (
        .clk_out1(pix_clk),
        .reset   (~reset_n),
        .locked  (clock_locked),
        .clk_in1 (sys_clk_100m)
    );

    always @(posedge pix_clk) begin
        if (!reset_n || !clock_locked) begin
            pixel_reset_shift <= 8'hff;
        end else begin
            pixel_reset_shift <= {1'b0, pixel_reset_shift[7:1]};
        end
    end

    assign pixel_reset_n = ~(|pixel_reset_shift);

    vtc_480p_1ppc u_vtc_480p (
        .clk_i    (pix_clk),
        .rst_n_i  (pixel_reset_n),
        .active_o (vtc_active),
        .hsync_o  (vtc_hsync),
        .vsync_o  (vtc_vsync),
        .pixel_x_o(pixel_x),
        .pixel_y_o(pixel_y)
    );

    always @* begin
        case (pixel_x[9:7])
            3'd0: rgb_colorbar = 24'hffffff;
            3'd1: rgb_colorbar = 24'hffff00;
            3'd2: rgb_colorbar = 24'h00ffff;
            3'd3: rgb_colorbar = 24'h00ff00;
            3'd4: rgb_colorbar = 24'hff00ff;
            default: rgb_colorbar = 24'h000000;
        endcase
    end

    hdmi_out_adv7511 #(
        .PIX_CLK_FREQ_HZ(25_000_000)
    ) u_hdmi_out_adv7511 (
        .PIX_CLK   (pix_clk),
        .RST_N     (pixel_reset_n),
        .RGB888    (rgb_colorbar),
        .DE        (vtc_active),
        .H_SYNC    (vtc_hsync),
        .V_SYNC    (vtc_vsync),
        .HDMI_INT  (HDMI_INT),
        .HDMI_SDA  (HDMI_SDA),
        .HDMI_DATA (HDMI_DATA),
        .HDMI_CLK  (HDMI_CLK),
        .HDMI_HSYNC(HDMI_HSYNC),
        .HDMI_VSYNC(HDMI_VSYNC),
        .HDMI_DE   (HDMI_DE),
        .HDMI_SCL  (HDMI_SCL)
    );

endmodule
