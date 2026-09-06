//====================================================================
// File name   : rgb2ycbcr422.sv
// Author      : LSL
// Create date : 2026-09-03
// Description : Convert RGB888 to limited-range BT.601 YCbCr422
// Target      : FPGA/ASIC
// Revision    : V2.0
//====================================================================

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

    localparam logic signed [12:0] COEFF_Y_R   = 13'sd1052;
    localparam logic signed [12:0] COEFF_Y_G   = 13'sd2065;
    localparam logic signed [12:0] COEFF_Y_B   = 13'sd401 ;
    localparam logic signed [12:0] COEFF_CB_R  = -13'sd607;
    localparam logic signed [12:0] COEFF_CB_G  = -13'sd1192;
    localparam logic signed [12:0] COEFF_CB_B  = 13'sd1799;
    localparam logic signed [12:0] COEFF_CR_R  = 13'sd1799;
    localparam logic signed [12:0] COEFF_CR_G  = -13'sd1507;
    localparam logic signed [12:0] COEFF_CR_B  = -13'sd292;
    localparam logic signed [21:0] BIAS_Y      = 22'sd65536;
    localparam logic signed [21:0] BIAS_CHROMA = 22'sd524288;
    localparam logic signed [21:0] RESULT_MAX  = 22'sd1044480;
    localparam int unsigned CHROMA_SCALE_SHIFT = 12;

    logic signed [21:0] y_sum_s1  ;
    logic signed [21:0] cb_sum_s1 ;
    logic signed [21:0] cr_sum_s1 ;
    logic signed [21:0] y_sum_s2  ;
    logic signed [21:0] cb_sum_s2 ;
    logic signed [21:0] cr_sum_s2 ;
    logic        [7:0]  rgb_r_s1  ;
    logic        [7:0]  rgb_g_s1  ;
    logic        [7:0]  rgb_b_s1  ;
    logic               chroma_is_cb_s1;
    logic               chroma_is_cb_s2;
    logic               chroma_is_cb_s3;
    logic               de_s1     ;
    logic               hsync_s1  ;
    logic               vsync_s1  ;
    logic               de_s2     ;
    logic               hsync_s2  ;
    logic               vsync_s2  ;
    logic        [7:0]  y_value_s3;
    logic        [7:0]  cb_value_s3;
    logic        [7:0]  cr_value_s3;
    logic               chroma_is_cb0;
    logic               de_prev   ;

    assign chroma_is_cb0 = (de_i == 1'b0) ? 1'b0 :
                           ((de_prev == 1'b0) ? 1'b1 : ~chroma_is_cb_s1);
    assign data_o = {y_value_s3, chroma_is_cb_s3 ? cb_value_s3 : cr_value_s3};

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rgb_r_s1       <= 8'd0;
            rgb_g_s1       <= 8'd0;
            rgb_b_s1       <= 8'd0;
            y_sum_s1       <= BIAS_Y;
            cb_sum_s1      <= BIAS_CHROMA;
            cr_sum_s1      <= BIAS_CHROMA;
            chroma_is_cb_s1 <= 1'b0;
            de_s1          <= 1'b0;
            hsync_s1       <= 1'b0;
            vsync_s1       <= 1'b0;
            de_prev        <= 1'b0;
        end else begin
            rgb_r_s1 <= rgb888_i[23:16];
            rgb_g_s1 <= rgb888_i[15:8];
            rgb_b_s1 <= rgb888_i[7:0];
            y_sum_s1  <= $signed({1'b0, rgb888_i[23:16]}) * COEFF_Y_R +
                         $signed({1'b0, rgb888_i[15:8]}) * COEFF_Y_G +
                         $signed({1'b0, rgb888_i[7:0] }) * COEFF_Y_B +
                         BIAS_Y;
            cb_sum_s1 <= $signed({1'b0, rgb888_i[23:16]}) * COEFF_CB_R +
                         $signed({1'b0, rgb888_i[15:8]}) * COEFF_CB_G +
                         $signed({1'b0, rgb888_i[7:0] }) * COEFF_CB_B +
                         BIAS_CHROMA;
            cr_sum_s1 <= $signed({1'b0, rgb888_i[23:16]}) * COEFF_CR_R +
                         $signed({1'b0, rgb888_i[15:8]}) * COEFF_CR_G +
                         $signed({1'b0, rgb888_i[7:0] }) * COEFF_CR_B +
                         BIAS_CHROMA;
            chroma_is_cb_s1 <= chroma_is_cb0;
            de_s1    <= de_i;
            hsync_s1 <= hsync_i;
            vsync_s1 <= vsync_i;
            de_prev  <= de_i;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            y_sum_s2        <= BIAS_Y;
            cb_sum_s2       <= BIAS_CHROMA;
            cr_sum_s2       <= BIAS_CHROMA;
            chroma_is_cb_s2 <= 1'b0;
            de_s2           <= 1'b0;
            hsync_s2        <= 1'b0;
            vsync_s2        <= 1'b0;
        end else begin
            y_sum_s2        <= y_sum_s1;
            cb_sum_s2       <= cb_sum_s1;
            cr_sum_s2       <= cr_sum_s1;
            chroma_is_cb_s2 <= chroma_is_cb_s1;
            de_s2           <= de_s1;
            hsync_s2        <= hsync_s1;
            vsync_s2        <= vsync_s1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            y_value_s3      <= 8'd0;
            cb_value_s3     <= 8'd0;
            cr_value_s3     <= 8'd0;
            chroma_is_cb_s3 <= 1'b0;
            de_o            <= 1'b0;
            hsync_o         <= 1'b0;
            vsync_o         <= 1'b0;
        end else begin
            y_value_s3      <= clip_result(y_sum_s2);
            cb_value_s3     <= clip_result(cb_sum_s2);
            cr_value_s3     <= clip_result(cr_sum_s2);
            chroma_is_cb_s3 <= chroma_is_cb_s2;
            de_o            <= de_s2;
            hsync_o         <= hsync_s2;
            vsync_o         <= vsync_s2;
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
