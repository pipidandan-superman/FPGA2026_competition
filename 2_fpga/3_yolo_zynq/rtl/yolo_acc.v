/************************************************************************
 * File Name       : yolo_acc.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_acc
 * Description     : M2 fabric per-lane int32 accumulator bank for the
 *                   GEMM PE array (architecture baseline section 3.2:
 *                   partial sums accumulate in LUT fabric, one int32
 *                   per DSP lane, independent of DSP cascade).
 *
 *                   Contract (mirrors the scalar core acc semantics):
 *                     - clr_i has priority over en_i (tile start);
 *                     - en_i=0 holds (K-breakpoint resume: the requant/
 *                       drain phase pauses accumulation, then the next
 *                       K chunk resumes on the same accumulator);
 *                     - int32 two's-complement add with natural wrap
 *                       (contract domain |sum| <= 2304*127*128 < 2^31
 *                       never wraps; wrap semantics kept bit-identical
 *                       to numpy int32 anyway).
 *                   Lane wiring is flat: lane l occupies
 *                   d_i/q_o[l*32 +: 32]. Correction terms of the M1
 *                   packing (lane0 -w<<<7, lane1 +P[16]) are applied
 *                   by the array wrapper before d_i, not here.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M2).
 ************************************************************************/

module yolo_acc #(
    parameter N_LANES = 8,                    // independent int32 lanes
    parameter DATA_W  = 32                    // lane width (int32)
) (
    input  wire                       clk_i,
    input  wire                       rst_n,
    input  wire                       clr_i,  // sync clear, priority over en
    input  wire                       en_i,   // 0 = hold (K breakpoint)
    input  wire [N_LANES*DATA_W-1:0]  d_i,    // per-lane addends
    output wire [N_LANES*DATA_W-1:0]  q_o     // registered accumulators
);

    reg [N_LANES*DATA_W-1:0] acc_r;
    integer l;

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            acc_r <= {(N_LANES*DATA_W){1'b0}};
        end else if (clr_i) begin
            acc_r <= {(N_LANES*DATA_W){1'b0}};
        end else if (en_i) begin
            for (l = 0; l < N_LANES; l = l + 1) begin
                acc_r[l*DATA_W +: DATA_W] <=
                    acc_r[l*DATA_W +: DATA_W] + d_i[l*DATA_W +: DATA_W];
            end
        end
    end

    assign q_o = acc_r;

endmodule
