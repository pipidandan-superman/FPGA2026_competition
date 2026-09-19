/************************************************************************
 * File Name       : yolo_conv_core.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_conv_core
 * Description     : M0 parameterized scalar conv core (integer contract,
 *                   1 MAC/cycle, combinational RAM reads). Generalization
 *                   of gate-passed yolo_conv0_core.sv: arbitrary
 *                   IC/OC/KH/KW/stride/pad via parameters, PAD_VAL selects
 *                   first-layer z-fold (-128) vs inner-layer 0, HAS_ACT
 *                   selects SiLU LUT vs pass-through. Numeric chain is
 *                   bit-identical to the frozen contract:
 *                     acc  int32 = sum_k w*x  (pad taps substituted by
 *                             PAD_VAL, integer sum order-invariant)
 *                     n    int64 = (acc + bias_eff[oc]) * M[oc]
 *                     y_pre      = sat_i8(rne_shift(n, shift[oc]))  (RNE
 *                             ties-to-even, shift in [0,62])
 *                     y          = HAS_ACT ? LUT[y_pre+128] : y_pre
 *                   RAM interfaces (combinational read, 1-cycle latency
 *                   semantics identical to conv0 core):
 *                     x_addr = ic*(IH*IW) + ih*IW + iw   (0 when pad tap)
 *                     w_addr = oc*KP + k,  k = ic*(KH*KW) + kh*KW + kw
 *                     y_addr = oc*(OH*OW) + oy*OW + ox
 *                   Address widths X_AW/W_AW/Y_AW/P_AW are explicit
 *                   parameters and must cover IC*IH*IW / OC*KP /
 *                   OC*OH*OW / OC respectively (TB computes them exactly).
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M0). Numeric path
 *     ported unchanged from yolo_conv0_core.sv (TB_CONV0_PASS,
 *     2026-09-15_yolo7020_g3_conv0_rtl_sim_run01); shape/pad/act
 *     generalization verified by TB_CONVGEN_PASS synthetic matrix.
 *   - V1.1 (2026-09-15) by LSL : Fix K decomposition bug found by real
 *     conv0 regression (case0 221550/409600 errs): k_ic was k/KP
 *     (=k/(IC*KH*KW), plane index stuck at 0 for k<KP); correct is
 *     k/(KH*KW). Synthetic matrix with degenerate requant params had
 *     masked this (see run01 README); generator fixed jointly.
 *   - V1.2 (2026-09-15) by LSL : Fix out-of-range part-select found by
 *     M10 array integration: bias/m/shift addr ports were oc[P_AW-1:0],
 *     which reads X for the nonexistent high bit(s) whenever P_AW >
 *     OC_CW (M10 golden instance OC=7/P_AW=4/OC_CW=3: all bias/m/shift
 *     serves X, whole layers' outputs X). Zero-extend oc to OC_PW before
 *     the slice; bits are identical for every P_AW <= OC_CW config, so
 *     all M0 gate cases (P_AW == OC_CW) are unchanged -- re-run M0 gate
 *     run02 for the regression proof (11/11 identical PASS).
 ************************************************************************/

module yolo_conv_core #(
    parameter IC      = 3,
    parameter OC      = 16,
    parameter KH      = 3,
    parameter KW      = 3,
    parameter IH      = 320,
    parameter IW      = 320,
    parameter SH      = 2,
    parameter SW      = 2,
    parameter PH      = 1,
    parameter PW      = 1,
    parameter [7:0]   PAD_VAL = 8'h80,  // first layer -128; 8'h00 otherwise
    parameter HAS_ACT = 1,
    parameter X_AW    = 19,             // must cover IC*IH*IW
    parameter W_AW    = 9,              // must cover OC*KP
    parameter Y_AW    = 20,             // must cover OC*OH*OW
    parameter P_AW    = 4               // must cover OC
) (
    input  wire               clk_i,
    input  wire               rst_n,
    input  wire               start_i,
    output wire               busy_o,
    output reg                done_o,
    output wire [X_AW-1:0]    x_addr_o,
    input  wire signed [7:0]  x_rdata_i,
    output wire [W_AW-1:0]    w_addr_o,
    input  wire signed [7:0]  w_rdata_i,
    output wire [P_AW-1:0]    bias_addr_o,
    input  wire signed [31:0] bias_rdata_i,
    output wire [P_AW-1:0]    m_addr_o,
    input  wire signed [31:0] m_rdata_i,
    output wire [P_AW-1:0]    shift_addr_o,
    input  wire [7:0]         shift_rdata_i,
    output wire [7:0]         lut_addr_o,
    input  wire signed [7:0]  lut_rdata_i,
    output reg                y_we_o,
    output reg [Y_AW-1:0]     y_addr_o,
    output reg signed [7:0]   y_wdata_o
);

    // ---- constant width helper (Verilog-2001 constant function) ----
    function [31:0] clog2;
        input [31:0] value;
        integer v;
        integer r;
        begin
            v = value - 1;
            r = 0;
            while (v > 0) begin
                v = v >> 1;
                r = r + 1;
            end
            if (r == 0) begin
                r = 1;
            end
            clog2 = r;
        end
    endfunction

    localparam KP    = IC * KH * KW;
    localparam OH    = (IH + 2 * PH - KH) / SH + 1;
    localparam OW    = (IW + 2 * PW - KW) / SW + 1;
    localparam K_CW  = clog2(KP);
    localparam OC_CW = clog2(OC);
    localparam OY_CW = clog2(OH);
    localparam OX_CW = clog2(OW);

    localparam [2:0] S_IDLE   = 3'd0,
                     S_MAC    = 3'd1,
                     S_REQUANT = 3'd2,
                     S_LUTW   = 3'd3,
                     S_DONE   = 3'd4;

    reg [2:0] state;
    reg [2:0] next_state;

    reg [OC_CW-1:0] oc;
    reg [OY_CW-1:0] oy;
    reg [OX_CW-1:0] ox;
    reg [K_CW-1:0]  k;
    reg signed [31:0] acc;
    reg signed [7:0]  y_pre;

    wire k_last     = (k == KP - 1);
    wire last_pixel = (oc == OC - 1) && (oy == OH - 1) && (ox == OW - 1);

    // ---- RNE right shift, ties to even (s in [0,62]; ported from conv0) ----
    function signed [63:0] rne_shift;
        input signed [63:0] n;
        input [7:0]         s;
        reg signed [63:0] q;
        reg [63:0] low_mask;
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
        input signed [63:0] v;
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

    // ---- window decomposition and RAM addresses (combinational) ----
    // Mixed-sign expressions are evaluated as 32-bit unsigned (modulo 2^32);
    // the resulting bit pattern equals the true two's-complement value, so
    // the signed comparisons below behave exactly (same discipline as the
    // $signed wrapping used on the arithmetic path).
    reg [31:0] k_ic;
    reg [31:0] k_ih;
    reg [31:0] k_iw;
    reg signed [31:0] ih;
    reg signed [31:0] iw;
    reg x_in;

    always @(*) begin
        k_ic = k / (KH * KW);
        k_ih = (k % (KH * KW)) / KW;
        k_iw = k % KW;
        ih   = oy * SH + k_ih - PH;
        iw   = ox * SW + k_iw - PW;
        x_in = (ih >= 0) && (ih < IH) && (iw >= 0) && (iw < IW);
    end

    wire [31:0] x_addr_full = k_ic * (IH * IW) + ih * IW + iw;
    wire [31:0] w_addr_full = oc * KP + k;
    wire [31:0] y_addr_full = oc * (OH * OW) + oy * OW + ox;

    assign x_addr_o    = x_in ? x_addr_full[X_AW-1:0] : {X_AW{1'b0}};
    assign w_addr_o    = w_addr_full[W_AW-1:0];
    // oc zero-extension before the P_AW slice: oc[P_AW-1:0] reads X bits
    // when P_AW > OC_CW (out-of-range part-select) -- M10 hit it with
    // OC=7/P_AW=4 (OC_CW=3) and every bias/m/shift serve went X, while
    // M0's gate never exercised P_AW > OC_CW. oc_ext keeps the selected
    // bits identical whenever P_AW <= OC_CW (zero behavioral change).
    localparam OC_PW = (P_AW > OC_CW) ? P_AW : OC_CW;
    wire [OC_PW-1:0] oc_ext = oc;
    assign bias_addr_o = oc_ext[P_AW-1:0];
    assign m_addr_o    = oc_ext[P_AW-1:0];
    assign shift_addr_o = oc_ext[P_AW-1:0];
    assign lut_addr_o  = y_pre + 8'sd128;
    assign busy_o      = (state != S_IDLE);

    // ---- requant operands (sign-safe wiring, same fix as conv0) ----
    wire signed [32:0] sum_b = $signed({bias_rdata_i[31], bias_rdata_i}) + acc;
    wire signed [63:0] prod  = sum_b * m_rdata_i;

    // ---- FSM block 1: state register ----
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ---- FSM block 2: next-state logic ----
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start_i) begin
                    next_state = S_MAC;
                end
            end
            S_MAC: begin
                if (k_last) begin
                    next_state = S_REQUANT;
                end
            end
            S_REQUANT: begin
                next_state = S_LUTW;
            end
            S_LUTW: begin
                if (last_pixel) begin
                    next_state = S_DONE;
                end else begin
                    next_state = S_MAC;
                end
            end
            S_DONE: begin
                next_state = S_IDLE;
            end
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // ---- datapath: MAC accumulator and requant result ----
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            k     <= {K_CW{1'b0}};
            acc   <= 32'sd0;
            y_pre <= 8'sd0;
        end else begin
            if (state == S_IDLE && start_i) begin
                k   <= {K_CW{1'b0}};
                acc <= 32'sd0;
            end else if (state == S_MAC) begin
                // $signed must wrap the ternary: the pad constant 8'h80
                // would otherwise be zero-extended to +128 (10.1c poison).
                if (k == {K_CW{1'b0}}) begin
                    acc <= $signed(x_in ? x_rdata_i : PAD_VAL) * w_rdata_i;
                end else begin
                    acc <= acc + $signed(x_in ? x_rdata_i : PAD_VAL) * w_rdata_i;
                end
                if (!k_last) begin
                    k <= k + 1'b1;
                end
            end else if (state == S_REQUANT) begin
                y_pre <= sat_i8(rne_shift(prod, shift_rdata_i));
            end else if (state == S_LUTW) begin
                k   <= {K_CW{1'b0}};
                acc <= 32'sd0;
            end
        end
    end

    // ---- datapath: output-tile counters, write channel, done ----
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            oc       <= {OC_CW{1'b0}};
            oy       <= {OY_CW{1'b0}};
            ox       <= {OX_CW{1'b0}};
            y_we_o   <= 1'b0;
            y_addr_o <= {Y_AW{1'b0}};
            y_wdata_o <= 8'sd0;
            done_o   <= 1'b0;
        end else begin
            y_we_o <= 1'b0;
            done_o <= 1'b0;
            if (state == S_IDLE && start_i) begin
                oc <= {OC_CW{1'b0}};
                oy <= {OY_CW{1'b0}};
                ox <= {OX_CW{1'b0}};
            end else if (state == S_LUTW) begin
                y_we_o   <= 1'b1;
                y_addr_o <= y_addr_full[Y_AW-1:0];
                if (HAS_ACT != 0) begin
                    y_wdata_o <= lut_rdata_i;
                end else begin
                    y_wdata_o <= y_pre;
                end
                if (ox == OW - 1) begin
                    ox <= {OX_CW{1'b0}};
                    if (oy == OH - 1) begin
                        oy <= {OY_CW{1'b0}};
                        if (oc == OC - 1) begin
                            oc <= {OC_CW{1'b0}};
                        end else begin
                            oc <= oc + 1'b1;
                        end
                    end else begin
                        oy <= oy + 1'b1;
                    end
                end else begin
                    ox <= ox + 1'b1;
                end
            end else if (state == S_DONE) begin
                done_o <= 1'b1;
            end
        end
    end

endmodule
