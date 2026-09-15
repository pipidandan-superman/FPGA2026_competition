/************************************************************************
 * File Name       : yolo_requant.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_requant
 * Description     : M5 per-lane requantisation unit for the GEMM PE
 *                   array (architecture baseline section 3.2 numeric
 *                   contract):
 *                     sum_b  = acc + bias_eff              (33b signed)
 *                     prod   = sum_b * m                   (64b signed)
 *                     y_pre  = sat_i8(rne_shift(prod, shift))
 *                   rne_shift / sat_i8 are ported bit-for-bit from
 *                   rtl/yolo_conv_core.v (V1.1, TB_CONVGEN_PASS), which
 *                   itself mirrors pynq/intarith.py (G2 contract).
 *
 *                   Domain contract:
 *                     - shift in [0, 62];
 *                     - m in [-2^31+1, 2^31-1]. INT32_MIN is excluded:
 *                       |sum_b| <= 2^32 keeps |prod| < 2^63 for every
 *                       other m (bit-exact int64 semantics); m = -2^31
 *                       with sum_b = -2^32 would wrap. Real model M is
 *                       positive in [2^30, 2^31); the negative rail is
 *                       adversarial coverage, +-（2^31-1) included.
 *                     - en_i=0 holds y_pre_o (drain/idle phase), vld_o
 *                       is the registered en_i (1-cycle latency pulse).
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M5).
 ************************************************************************/

module yolo_requant #(
    parameter ACC_W = 32                    // acc/bias operand width
) (
    input  wire                    clk_i,
    input  wire                    rst_n,
    input  wire                    en_i,    // 0 = hold y_pre_o
    input  wire signed [ACC_W-1:0] acc_i,   // K-complete partial sum
    input  wire signed [ACC_W-1:0] bias_i,  // effective bias (z-corrected)
    input  wire signed [31:0]      m_i,     // per-channel multiplier
    input  wire [7:0]              shift_i, // per-channel RNE shift [0,62]
    output reg  signed [7:0]       y_pre_o, // pre-activation int8
    output reg                     vld_o
);

    localparam SUM_W  = 33;                 // acc+bias with carry bit
    localparam PROD_W = 64;                 // exact |prod| < 2^63 domain
    localparam I8_MAX = 127;
    localparam I8_MIN = -128;
    localparam SHT_W  = 8;

    // ---- requant operands (sign-safe wiring, same fix as conv0/M0) ----
    wire signed [SUM_W-1:0]  sum_b = $signed({bias_i[ACC_W-1], bias_i}) + acc_i;
    wire signed [PROD_W-1:0] prod  = sum_b * m_i;

    // ---- RNE right shift, ties to even (s in [0,62]; verbatim M0 port) ----
    function signed [PROD_W-1:0] rne_shift;
        input signed [PROD_W-1:0] n;
        input [SHT_W-1:0]         s;
        reg signed [PROD_W-1:0] q;
        reg [PROD_W-1:0]    low_mask;
        reg half;
        reg low_any;
        reg round_up;
        begin
            q = n >>> s;
            if (s == 8'd0) begin
                round_up = 1'b0;
            end else begin
                half     = n[s - 8'd1];
                low_mask = (64'd1 << (s - 8'd1)) - 64'd1;
                low_any  = |(n & low_mask);
                round_up = half & (low_any | q[0]);
            end
            rne_shift = q + (round_up ? 64'sd1 : 64'sd0);
        end
    endfunction

    function signed [7:0] sat_i8;
        input signed [PROD_W-1:0] v;
        begin
            if (v > 64'sd127) begin
                sat_i8 = 8'sd127;
            end else if (v < -64'sd128) begin
                sat_i8 = -8'sd128;
            end else begin
                sat_i8 = v[7:0];
            end
        end
    endfunction

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            y_pre_o <= 8'sd0;
            vld_o   <= 1'b0;
        end else begin
            vld_o <= en_i;
            if (en_i) begin
                y_pre_o <= sat_i8(rne_shift(prod, shift_i));
            end
        end
    end

endmodule
