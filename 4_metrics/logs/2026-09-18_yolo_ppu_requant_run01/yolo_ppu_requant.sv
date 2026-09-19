/************************************************************************
 * File Name       : yolo_ppu_requant.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ppu_requant
 * Description     : PPU requant core (PPU manual section 5.1, shared by
 *                   add engine both lanes and xfer engine per segment):
 *                   y_q = sat_i8(rne_shift(int64(x_q) * M, s)).
 *
 *   Numeric contract (PPU manual section 2.1, verbatim intref run04):
 *     x_q signed INT8  [-128, 127]
 *     M    unsigned-in-signed-32 [0, 2^31)  (normalized [2^30,2^31),
 *          or 0 = dead channel -> y=0 naturally; PL never computes M)
 *     s    6-bit [0, 62]
 *     prod = $signed(x) * $signed(M)        INT64 (|prod| < 2^38)
 *     RNE  q = floor(prod/2^s); rem = prod - q*2^s (= low s bits,
 *          always in [0, 2^s)); round up when rem > 2^(s-1), or
 *          rem == 2^(s-1) and q odd (ties to even, covers negative
 *          products: -1.5 -> -2, -2.5 -> -2); s == 0 bypasses shift;
 *     sat  clamp INT8.
 *     Identity pair (M=2^30, s=30) is plain arithmetic here -- the
 *     same-scale COPY shortcut lives in the xfer engine, not in this
 *     core (manual 5.1/5.2).
 *
 *   Structure mirrors the GEMM-line proven lane (rtl/GEMM/
 *   yolo_gemm_tail.sv stage-2/3, gate run05): shift+mask remainder
 *   (non-negative), tie & q[0] -> +1.  The intref dead negative
 *   branches (twice < -full) are provably unreachable since
 *   rem in [0, 2^s) and are omitted; the P2 gate cross-checks against
 *   the python oracle on adversarial tie vectors (construction
 *   coverage required: tie odd/even both signs, sat both rails,
 *   dead channel, s=0, identity, s>=39).
 *
 *   Timing: 3-stage pipeline, identical contract to GEMM tail.
 *   Element fed during cycle D (in_valid) -> x captured edge1,
 *   prod registered edge2, y registered edge3 -> y_valid during
 *   cycle D+3.  Back-to-back beats stream; invalid beats carry no
 *   state; (M, s) ride WITH their element (may change every cycle).
 * Dependencies    : None (pure fabric + one 32x32 signed multiply,
 *                   inference decided by synthesis -- no DSP claim).
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release (P2a).
 ************************************************************************/

module yolo_ppu_requant #(
    parameter integer R = 1              // elements per beat
) (
    input  wire                     clk_i,      //运算时钟
    input  wire                     rst_i,      //同步复位，高有效（清 valid 流水）
    // ---- element stream in (cycle D) ----
    input  wire                     in_valid_i, //本拍 R 个元素有效
    input  wire                     in_last_i,  //本拍为任务最后一个有效元素
    input  wire signed [R-1:0][7:0]  x_i,       //x_q（INT8）
    input  wire signed [R-1:0][31:0] m_i,       //M（段/OC 参数，随元素入流水）
    input  wire        [R-1:0][5:0]  sh_i,      //shift，域 0..62
    // ---- y stream out (cycle D+3) ----
    output wire                     y_valid_o,
    output wire                     y_last_o,
    output wire signed [R-1:0][7:0] y_o
);

    // ---- per-lane datapath registers ----
    reg signed [7:0]   x1_r  [0:R-1];   //stage1: x 入流水
    reg signed [31:0]  m1_r  [0:R-1];   //stage1: M 入流水
    reg        [5:0]   sh1_r [0:R-1];   //stage1: shift 入流水
    reg signed [63:0]  prod_r[0:R-1];   //stage2: x_sext * M
    reg        [5:0]   sh2_r [0:R-1];   //stage2: shift 随乘积
    reg signed [7:0]   y_r   [0:R-1];   //stage3: RNE+sat 结果

    // ---- sideband pipeline（valid/last 与数据同拍走）----
    reg v1_r, v2_r, v3_r;
    reg last1_r, last2_r, last3_r;

    integer i;

    always @(posedge clk_i) begin
        if (rst_i) begin
            v1_r <= 1'b0; v2_r <= 1'b0; v3_r <= 1'b0;
            last1_r <= 1'b0; last2_r <= 1'b0; last3_r <= 1'b0;
        end else begin
            // stage 1: x/M/shift 入流水（无算术，驱动侧可逐拍换参）
            v1_r    <= in_valid_i;
            last1_r <= in_valid_i & in_last_i;
            for (i = 0; i < R; i = i + 1) begin
                x1_r[i]  <= $signed(x_i[i]);
                m1_r[i]  <= $signed(m_i[i]);
                sh1_r[i] <= sh_i[i];
            end
            // stage 2: prod（32 位符号扩展乘，上下文扩到 64 位）
            v2_r    <= v1_r;
            last2_r <= last1_r;
            for (i = 0; i < R; i = i + 1) begin
                prod_r[i] <= $signed({{24{x1_r[i][7]}}, x1_r[i]}) * m1_r[i];
                sh2_r[i]  <= sh1_r[i];
            end
            // stage 3 valid 传播（y 在 generate 块内寄存）
            v3_r    <= v2_r;
            last3_r <= last2_r;
        end
    end

    // ---- stage 3: RNE -> sat（对 stage2 寄存器做组合，结果入 y_r）----
    genvar g;
    generate
        for (g = 0; g < R; g = g + 1) begin : lane
            // 64 位宽的 floor 移位/余数掩码（规避变宽部分选择）
            wire [63:0] mask_w = (sh2_r[g] == 6'd0) ? 64'd0
                               : ((64'd1 << sh2_r[g]) - 64'd1);
            wire [63:0] half_w = 64'd1 << (sh2_r[g] - 6'd1); //仅 sh>0 有效
            wire signed [63:0] qsh_w = prod_r[g] >>> sh2_r[g]; //floor；s=0 恒等
            wire [63:0] rem_w = prod_r[g] & mask_w;      //∈[0, 2^s)
            wire round_up_w = (sh2_r[g] != 6'd0)
                            && ((rem_w > half_w)
                                || ((rem_w == half_w) && qsh_w[0])); //ties to even
            wire signed [63:0] qn_w = qsh_w + (round_up_w ? 64'sd1 : 64'sd0);
            wire signed [63:0] qs_w = (qn_w > 64'sd127)  ? 64'sd127
                                    : (qn_w < -64'sd128) ? -64'sd128
                                    : qn_w;

            always @(posedge clk_i) begin
                y_r[g] <= qs_w[7:0];
            end

            assign y_o[g] = y_r[g];
        end
    endgenerate

    assign y_valid_o = v3_r;
    assign y_last_o  = v3_r & last3_r;

endmodule
