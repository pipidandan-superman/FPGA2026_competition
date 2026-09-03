/************************************************************************
 * File Name       : rgb2ycbcr422.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : rgb2ycbcr422
 * Description     : Converts RGB888 to BT.709 YCbCr and packs one Y and
 *                   one alternating Cb/Cr value per pixel clock.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

module rgb2ycbcr422 (
    input  wire               clk_i   ,
    input  wire               rst_n_i ,
    input  wire        [23:0] rgb888_i,
    input  wire               de_i    ,
    input  wire               hsync_i ,
    input  wire               vsync_i ,
    output wire        [15:0] data_o  ,
    output reg                de_o    ,
    output reg                hsync_o ,
    output reg                vsync_o
);

    localparam logic signed [11:0] COEFF_Y_R      = 12'sd752  ;
    localparam logic signed [11:0] COEFF_Y_G      = 12'sd1588 ;
    localparam logic signed [11:0] COEFF_Y_B       = 12'sd254  ;
    localparam logic signed [11:0] COEFF_CB_R      = -12'sd412 ;
    localparam logic signed [11:0] COEFF_CB_G      = -12'sd1387;
    localparam logic signed [11:0] COEFF_CB_B      = 12'sd1799 ;
    localparam logic signed [11:0] COEFF_CR_R      = 12'sd1799 ;
    localparam logic signed [11:0] COEFF_CR_G      = -12'sd1633;
    localparam logic signed [11:0] COEFF_CR_B      = -12'sd165 ;
    localparam logic signed [21:0] BIAS_Y         = 22'sd65536 ;
    localparam logic signed [21:0] BIAS_CHROMA    = 22'sd524288;
    localparam logic signed [21:0] RESULT_MAX     = 22'sd1044480;
    localparam int unsigned                        CHROMA_SCALE_SHIFT = 12;

    logic signed [29:0] y_product_s1   ;
    logic signed [29:0] cb_product_s1  ;
    logic signed [29:0] cr_product_s1  ;
    logic signed [29:0] y_sum_s1       ;
    logic signed [29:0] cb_sum_s1      ;
    logic signed [29:0] cr_sum_s1      ;
    logic signed [21:0] y_sum_s2       ;
    logic signed [21:0] cb_sum_s2      ;
    logic signed [21:0] cr_sum_s2      ;
    logic        [7:0]  rgb_r_s1      ;
    logic        [7:0]  rgb_g_s1      ;
    logic        [7:0]  rgb_b_s1      ;
    logic        [7:0]  y_value_s3    ;
    logic        [7:0]  cb_value_s3   ;
    logic        [7:0]  cr_value_s3   ;
    logic               chroma_is_cb_s1;
    logic               chroma_is_cb_s2;
    logic               chroma_is_cb_s3;
    logic               de_s1         ;
    logic               hsync_s1      ;
    logic               vsync_s1      ;
    logic               de_s2         ;
    logic               hsync_s2      ;
    logic               vsync_s2      ;
    logic               chroma_is_cb0 ;
    logic               chroma_is_cb_d;
    logic               de_s0         ;
    logic               hsync_s0      ;
    logic               vsync_s0      ;
    logic               de_prev       ;

    assign de_s0 = de_i;
    assign hsync_s0 = hsync_i;
    assign vsync_s0 = vsync_i;
    assign chroma_is_cb0 = (de_i == 1'b0) ? 1'b0 :
                           ((de_prev == 1'b0) ? 1'b1 : ~chroma_is_cb_d);
    assign data_o = {y_value_s3, chroma_is_cb_s3 ? cb_value_s3 : cr_value_s3};

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            y_product_s1 <= 30'sd0;
            cb_product_s1 <= 30'sd0;
            cr_product_s1 <= 30'sd0;
            y_sum_s1 <= 30'sd0;
            cb_sum_s1 <= 30'sd0;
            cr_sum_s1 <= 30'sd0;
            chroma_is_cb_s1 <= 1'b0;
            chroma_is_cb_d <= 1'b0;
            de_prev <= 1'b0;
            de_s1 <= 1'b0;
            hsync_s1 <= 1'b0;
            vsync_s1 <= 1'b0;
        end else begin
            y_product_s1 <= $signed({1'b0, rgb888_i[23:16]}) * COEFF_Y_R;
            cb_product_s1 <= $signed({1'b0, rgb888_i[23:16]}) * COEFF_CB_R;
            cr_product_s1 <= $signed({1'b0, rgb888_i[23:16]}) * COEFF_CR_R;
            y_sum_s1 <= $signed({1'b0, rgb888_i[15:8]}) * COEFF_Y_G;
            cb_sum_s1 <= $signed({1'b0, rgb888_i[15:8]}) * COEFF_CB_G;
            cr_sum_s1 <= $signed({1'b0, rgb888_i[15:8]}) * COEFF_CR_G;
            chroma_is_cb_s1 <= chroma_is_cb0;
            de_s1 <= de_s0;
            hsync_s1 <= hsync_s0;
            vsync_s1 <= vsync_s0;
            chroma_is_cb_d <= chroma_is_cb0;
            de_prev <= de_s0;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            y_sum_s2 <= 22'sd0;
            cb_sum_s2 <= 22'sd0;
            cr_sum_s2 <= 22'sd0;
            chroma_is_cb_s2 <= 1'b0;
            de_s2 <= 1'b0;
            hsync_s2 <= 1'b0;
            vsync_s2 <= 1'b0;
        end else begin
            y_sum_s2 <= y_sum_s1 + y_product_s1 + $signed({4'b0000, rgb_b_s1}) * COEFF_Y_B + BIAS_Y;
            cb_sum_s2 <= cb_sum_s1 + cb_product_s1 + $signed({4'b0000, rgb_b_s1}) * COEFF_CB_B + BIAS_CHROMA;
            cr_sum_s2 <= cr_sum_s1 + cr_product_s1 + $signed({4'b0000, rgb_b_s1}) * COEFF_CR_B + BIAS_CHROMA;
            chroma_is_cb_s2 <= chroma_is_cb_s1;
            de_s2 <= de_s1;
            hsync_s2 <= hsync_s1;
            vsync_s2 <= vsync_s1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rgb_r_s1 <= 8'd0;
            rgb_g_s1 <= 8'd0;
            rgb_b_s1 <= 8'd0;
        end else begin
            rgb_r_s1 <= rgb888_i[23:16];
            rgb_g_s1 <= rgb888_i[15:8];
            rgb_b_s1 <= rgb888_i[7:0];
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            y_value_s3 <= 8'd0;
            cb_value_s3 <= 8'd0;
            cr_value_s3 <= 8'd0;
            chroma_is_cb_s3 <= 1'b0;
            de_o <= 1'b0;
            hsync_o <= 1'b0;
            vsync_o <= 1'b0;
        end else begin
            y_value_s3 <= clip_result(y_sum_s2);
            cb_value_s3 <= clip_result(cb_sum_s2);
            cr_value_s3 <= clip_result(cr_sum_s2);
            chroma_is_cb_s3 <= chroma_is_cb_s2;
            de_o <= de_s2;
            hsync_o <= hsync_s2;
            vsync_o <= vsync_s2;
        end
    end

    function automatic logic [7:0] clip_result (
        input logic signed [21:0] scaled_value
    );
        begin
            if (scaled_value < 22'sd0) begin
                clip_result = 8'd0;
            end else if (scaled_value > RESULT_MAX) begin
                clip_result = 8'd255;
            end else begin
                clip_result = scaled_value[CHROMA_SCALE_SHIFT+:8];
            end
        end
    endfunction

endmodule
