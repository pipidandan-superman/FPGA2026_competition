//====================================================================
// File name   : hdmi_colorbar_vtc_top.v
// Author      : LSL
// Create date : 2026-09-04
// Description : RGB888 480p colorbar source with board-swap YCbCr422 transport
// Target      : Zynq-7020 EES-331 board
// Revision    : V1.9
//====================================================================

module hdmi_colorbar_vtc_top (
    input  wire        sys_clk_100m,
    input  wire        reset_n     ,
    input  wire        SW0         ,
    input  wire        HDMI_INT    ,
    inout  wire        HDMI_SDA    ,
    output reg  [15:0] HDMI_DATA   ,
    output reg         HDMI_HSYNC  ,
    output reg         HDMI_VSYNC  ,
    output reg         HDMI_DE     ,
    output wire        HDMI_CLK    ,
    output wire        HDMI_SCL    ,
    output wire [7:0]  LED
);

    localparam [7:0] BUILD_SIGNATURE = 8'hA5;

    wire pix_clk;
    wire clock_locked;
    wire pixel_reset_n;

    wire vtc_active;
    wire vtc_hsync;
    wire vtc_vsync;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire       adv7511_cfg_done;
    wire       adv7511_cfg_error;
    wire [5:0] adv7511_readback_match;
    wire [47:0] adv7511_readback_data;

    reg  [23:0] test_rgb;
    wire [15:0] conversion_data;
    wire        conversion_de;
    wire        conversion_hsync;
    wire        conversion_vsync;
    reg  [7:0]  direct_y_value;
    reg  [7:0]  direct_cb_value;
    reg  [7:0]  direct_cr_value;
    reg  [15:0] direct_input_data;
    reg  [15:0] direct_data_s1;
    reg  [15:0] direct_data_s2;
    reg  [15:0] direct_data_s3;
    reg         direct_de_s1;
    reg         direct_de_s2;
    reg         direct_de_s3;
    reg         direct_hsync_s1;
    reg         direct_hsync_s2;
    reg         direct_hsync_s3;
    reg         direct_vsync_s1;
    reg         direct_vsync_s2;
    reg         direct_vsync_s3;
    reg         sw0_sync1;
    reg         sw0_sync2;
    reg         video_mode_direct;
    wire [15:0] selected_data;
    wire [15:0] physical_data;
    wire        selected_de;
    wire        selected_hsync;
    wire        selected_vsync;
    reg [7:0] pixel_reset_shift;

    clk_wiz_0 u_clk_wiz_0 (
        .clk_out1(pix_clk),
        .reset   (~reset_n),
        .locked  (clock_locked),
        .clk_in1 (sys_clk_100m)
    );

    always @(posedge pix_clk or negedge reset_n) begin
        if (!reset_n) begin
            pixel_reset_shift <= 8'hff;
        end else if (!clock_locked) begin
            pixel_reset_shift <= 8'hff;
        end else begin
            pixel_reset_shift <= {1'b0, pixel_reset_shift[7:1]};
        end
    end

    assign pixel_reset_n = reset_n & clock_locked & ~(|pixel_reset_shift);

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
            3'd0: test_rgb = 24'hFFFFFF; // White
            3'd1: test_rgb = 24'h000000; // Black
            3'd2: test_rgb = 24'hFF0000; // Red
            3'd3: test_rgb = 24'h0000FF; // Blue
            3'd4: test_rgb = 24'h00FF00; // Green
            default: test_rgb = 24'h000000;
        endcase
    end

    // Direct YCbCr422 source. Values match the BT.601 limited-range
    // conversion and are packed as Style 3: {Y, Cb/Cr}.
    always @* begin
        direct_y_value  = 8'h10;
        direct_cb_value = 8'h80;
        direct_cr_value = 8'h80;

        if (vtc_active) begin
            case (pixel_x[9:7])
                3'd0: begin
                    direct_y_value  = 8'hEB;
                    direct_cb_value = 8'h80;
                    direct_cr_value = 8'h80;
                end
                3'd1: begin
                    direct_y_value  = 8'h10;
                    direct_cb_value = 8'h80;
                    direct_cr_value = 8'h80;
                end
                3'd2: begin
                    direct_y_value  = 8'h51;
                    direct_cb_value = 8'h5A;
                    direct_cr_value = 8'hEF;
                end
                3'd3: begin
                    direct_y_value  = 8'h28;
                    direct_cb_value = 8'hEF;
                    direct_cr_value = 8'h6D;
                end
                3'd4: begin
                    direct_y_value  = 8'h90;
                    direct_cb_value = 8'h35;
                    direct_cr_value = 8'h22;
                end
                default: begin
                    direct_y_value  = 8'h10;
                    direct_cb_value = 8'h80;
                    direct_cr_value = 8'h80;
                end
            endcase
        end

        direct_input_data = {
            direct_y_value,
            pixel_x[0] ? direct_cr_value : direct_cb_value
        };
    end

    // Synchronize the board switch and latch its value only at the first
    // pixel of a frame. SW0=0 selects RGB888 conversion; SW0=1 selects
    // direct YCbCr422 transport.
    always @(posedge pix_clk or negedge reset_n) begin
        if (!reset_n) begin
            sw0_sync1       <= 1'b0;
            sw0_sync2       <= 1'b0;
            video_mode_direct <= 1'b0;
        end else begin
            sw0_sync1 <= SW0;
            sw0_sync2 <= sw0_sync1;

            if (pixel_reset_n && (pixel_x == 10'd0) &&
                (pixel_y == 10'd0)) begin
                video_mode_direct <= sw0_sync2;
            end
        end
    end

    // The source image is native RGB888. The board only connects 16 ADV7511
    // data pins, so conversion to the board's YCbCr422 transport occurs here.
    rgb2ycbcr422 u_rgb2ycbcr422 (
        .clk_i   (pix_clk)         ,
        .rst_n_i (pixel_reset_n)   ,
        .rgb888_i(test_rgb)        ,
        .de_i    (vtc_active)      ,
        .hsync_i (vtc_hsync)       ,
        .vsync_i (vtc_vsync)       ,
        .data_o  (conversion_data) ,
        .de_o    (conversion_de)   ,
        .hsync_o (conversion_hsync),
        .vsync_o (conversion_vsync)
    );

    // Match rgb2ycbcr422's three-register video latency exactly.
    always @(posedge pix_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            direct_data_s1  <= 16'd0;
            direct_data_s2  <= 16'd0;
            direct_data_s3  <= 16'd0;
            direct_de_s1    <= 1'b0;
            direct_de_s2    <= 1'b0;
            direct_de_s3    <= 1'b0;
            direct_hsync_s1 <= 1'b0;
            direct_hsync_s2 <= 1'b0;
            direct_hsync_s3 <= 1'b0;
            direct_vsync_s1 <= 1'b0;
            direct_vsync_s2 <= 1'b0;
            direct_vsync_s3 <= 1'b0;
        end else begin
            direct_data_s1  <= direct_input_data;
            direct_data_s2  <= direct_data_s1;
            direct_data_s3  <= direct_data_s2;
            direct_de_s1    <= vtc_active;
            direct_de_s2    <= direct_de_s1;
            direct_de_s3    <= direct_de_s2;
            direct_hsync_s1 <= vtc_hsync;
            direct_hsync_s2 <= direct_hsync_s1;
            direct_hsync_s3 <= direct_hsync_s2;
            direct_vsync_s1 <= vtc_vsync;
            direct_vsync_s2 <= direct_vsync_s1;
            direct_vsync_s3 <= direct_vsync_s2;
        end
    end

    assign selected_data  = video_mode_direct ? direct_data_s3 : conversion_data;
    assign selected_de    = video_mode_direct ? direct_de_s3 : conversion_de;
    assign selected_hsync = video_mode_direct ? direct_hsync_s3 : conversion_hsync;
    assign selected_vsync = video_mode_direct ? direct_vsync_s3 : conversion_vsync;

    // selected_data is logical 16-bit YCbCr422: {Y, Cb/Cr}. The EES-331 port
    // order is reversed relative to that logical bus, and the board PASS image
    // confirms that the constrained HDMI_DATA bytes must be exchanged here.
    assign physical_data = {selected_data[7:0], selected_data[15:8]};
    // Board regression guard: do not restore the unswapped form. It produced
    // chroma stripes in the red/blue/green bars on 2026-09-06.
    always @(negedge pix_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            HDMI_DATA   <= 16'd0;
            HDMI_DE     <= 1'b0;
            HDMI_HSYNC  <= 1'b0;
            HDMI_VSYNC  <= 1'b0;
        end else begin
            HDMI_DATA   <= physical_data;
            HDMI_DE     <= selected_de;
            HDMI_HSYNC  <= selected_hsync;
            HDMI_VSYNC  <= selected_vsync;
        end
    end

    adv7511_cfg_top #(
        .ENABLE_READBACK     (1'b1),
        .CLK_FREQ_HZ         (25_000_000),
        .POWER_UP_DELAY_MS   (200),
        .DEVICE_ADDR         (7'h39),
        .IIC_CLOCK_DIVIDER   (252),
        .PROTOCOL_TIMEOUT_MS (3000)
    ) u_adv7511_cfg_top (
        .clk_i      (pix_clk),
        .rst_n_i    (pixel_reset_n),
        .cfg_done_o (adv7511_cfg_done),
        .cfg_error_o(adv7511_cfg_error),
        .readback_match_o(adv7511_readback_match),
        .readback_data_o (adv7511_readback_data) ,
        .scl_o      (HDMI_SCL),
        .sda_io     (HDMI_SDA)
    );

    // Hold S1 to show the build signature. After release, LED7 shows the
    // selected video source and LED6:LED0 show the low seven readback bits.
    // The LED displays R0x16. Its masked fields are expected as 30h and the
    // raw value is 38h. The board byte order correction is performed above.
    // FFh means SDA remained released/high throughout the returned byte.
    assign LED = reset_n ? {video_mode_direct, adv7511_readback_data[22:16]} :
                           BUILD_SIGNATURE;

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT        (1'b0),
        .SRTYPE      ("SYNC")
    ) u_hdmi_clk_oddr (
        .C  (pix_clk),
        .CE (1'b1),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (1'b0),
        .S  (1'b0),
        .Q  (HDMI_CLK)
    );

    wire unused_hdmi_int = HDMI_INT;
    wire unused_cfg_status = adv7511_cfg_done | adv7511_cfg_error |
                             (|adv7511_readback_match);

endmodule
