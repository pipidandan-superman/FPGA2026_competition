/************************************************************************
 * File Name       : yolo_pe_pack.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_pe_pack
 * Description     : M1 DSP48E1 dual-int8 packing PE (one DSP, two
 *                   independent w*x products per multiply). Serves one
 *                   OC row and two adjacent N columns of the GEMM array
 *                   (architecture baseline section 3.2, PROD tier).
 *
 *                   Corrected layout (M1 gate finding; the baseline
 *                   section 3.2 literal text fails for negative x --
 *                   exhaustive 2^24 evidence in pe_pack_vecgen.py and
 *                   run01 README):
 *                     A[24:0] = { x1[7:0], 9'b0, x0b[7:0] }
 *                               x0b = x0 + 128 (MSB flip, unsigned byte)
 *                               A = x1*2^17 + x0b exactly, x0b in [0,255]
 *                               needs no sign embedding (a signed low
 *                               operand cannot ride in the low field:
 *                               sign-extended gap injects +2^17*w into
 *                               the upper lane, zero gap injects 256*w
 *                               into the lower lane).
 *                     B[17:0] = sign-extended w
 *                     P       = A*B  (43-bit)
 *                     lane0   = $signed(P[16:0]) - (w <<< 7)
 *                               (P[16:0] = w*(x0+128); subtracting the
 *                               shifted broadcast w removes the bias --
 *                               wiring only, no multiplier)
 *                     lane1   = $signed(P[33:17]) + P[16]
 *                               (a negative low product borrows 1 from
 *                               the upper field; P[16] is exactly that
 *                               borrow as the low lane's sign bit)
 *                   Bounds: |w*(x0+128)| <= 127*255 = 32385 < 2^16 so
 *                   lane0_raw fits signed 17; |w*x| <= 127*128 = 16256
 *                   so both outputs fit signed 16 payload.
 *
 *                   Combinational by intent: the M1 gate validates the
 *                   bit layout; DSP48 pipeline registers (MREG/PREG)
 *                   belong to the integration wrapper / OOC timing
 *                   (M10/M12), not to the unit contract. A later
 *                   optimization may fold the +128 bias into X-tile
 *                   storage (same 8 bits); the module contract stays
 *                   "raw int8 in, exact w*x out".
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M1). Bias-embedded
 *     packing proven exact by exhaustive 2^24 Python bit model +
 *     TB_PE_PACK_PASS; two rejected layouts (baseline literal and
 *     sign-extended gap) documented with their exhaustive fail counts.
 ************************************************************************/

module yolo_pe_pack #(
    parameter X_W = 8,                        // activation width (int8)
    parameter W_W = 8                         // weight width (int8)
) (
    input  wire signed [X_W-1:0] x0_i,        // activation, N column n
    input  wire signed [X_W-1:0] x1_i,        // activation, N column n+1
    input  wire signed [W_W-1:0] w_i,         // weight, broadcast (OC row)
    output wire signed [16:0]     p0_o,       // lane n   = w*x0
    output wire signed [16:0]     p1_o        // lane n+1 = w*x1
);

    // ---- DSP48E1 operand field geometry ----
    localparam LANE_SHIFT = 17;               // upper lane base bit
    localparam GAP_W      = 9;                // gap bits [16:8]
    localparam A_W        = 25;
    localparam B_W        = 18;
    localparam P_W        = A_W + B_W;        // 43

    // ---- x0 biased to unsigned byte: x0b = x0 + 128 == MSB flip ----
    wire [X_W-1:0] x0b = {~x0_i[X_W-1], x0_i[X_W-2:0]};

    // ---- A = x1*2^17 + x0b (x1 signed at the operand top, gap zero) ----
    wire signed [A_W-1:0] a_w = {x1_i, {GAP_W{1'b0}}, x0b};

    // ---- B = w sign-extended to 18 bits ----
    wire signed [B_W-1:0] b_w = {{(B_W-W_W){w_i[W_W-1]}}, w_i};

    // ---- P = A*B at full 43-bit width (context-determined signed mult,
    //      same discipline as the conv core prod) ----
    wire signed [P_W-1:0] p_w = a_w * b_w;

    // ---- lane0: undo the +128 bias with the shifted broadcast w ----
    wire signed [16:0] lane0_raw = $signed(p_w[16:0]);
    wire signed [16:0] w_sh7     = $signed({{2{w_i[W_W-1]}}, w_i, 7'b0000000});
    assign p0_o = lane0_raw - w_sh7;

    // ---- lane1: restore the borrow taken by a negative low product ----
    wire signed [16:0] lane1_raw = $signed(p_w[33:LANE_SHIFT]);
    assign p1_o = lane1_raw + $signed({16'b0, p_w[16]});

endmodule
