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
 *                   V1.2 (2026-09-16, UG479 v1.10 full-compliance pass,
 *                   user directive "strictly per the manual"): the
 *                   primitive configuration now follows UG479 to the
 *                   letter:
 *                   (1) 3-stage multiply pipeline AREG=BREG=MREG=PREG=1
 *                       (UG479 p.14 "At least three pipeline registers
 *                       are required for both multiply ... to run at
 *                       full speed", p.47 "For multiplier-based designs,
 *                       the DSP48E1 slice requires a three-stage
 *                       pipeline"). ACASCREG=BCASCREG=1 forced by Table
 *                       2-3 (AREG=1 -> ACASCREG must be 1). MODULE
 *                       CONTRACT CHANGE: p0_o/p1_o are valid 3 cycles
 *                       after x and w presentation (inputs in cycle D ->
 *                       outputs in cycle D+3).
 *                   (2) Unused data ports tied per Table 2-2 note 1:
 *                       C/D tied High with the port register selected
 *                       and CE/RST Low (leakage power rule).
 *                   (3) Control attributes explicit: OPMODEREG=
 *                       CARRYINSELREG=0 (equal, UG479 p.41) and
 *                       ALUMODEREG=INMODEREG=CARRYINREG=0 -- controls
 *                       flow through, no hidden default-1 registers
 *                       (V1.1 left them at the Table 2-3 defaults of 1,
 *                       silently registering the static OPMODE/ALUMODE).
 *                   (4) Live pipeline registers get synchronous
 *                       active-high resets RSTA/RSTB/RSTM/RSTP (Table
 *                       2-4: reset has priority) from ~rst_n_i.
 *                   The lane0 bias correction consumes w DELAYED 3
 *                   cycles (w_d3_r) so it aligns with the registered P
 *                   (P in cycle D+3 reflects w from cycle D). Values
 *                   are unchanged -- M1 golden set stays valid; only
 *                   the latency contract moved.
 *
 *                   V1.1 context: the multiply became a direct DSP48E1
 *                   primitive instance (one DSP per PE) after Vivado
 *                   2025.2 decomposed the inferred packed product into
 *                   two 8-bit multipliers (228 DSP > 220-site budget).
 *                   OPMODE=7'b0000101 / ALUMODE=4'b0000 / INMODE=
 *                   5'b00000 keep P = A*B. Note: the unisim model gates
 *                   its OPMODE muxes for the first 100ns of simulation
 *                   ($time > 100000 in DSP48E1.v) -- TBs must not
 *                   compare inside that warm-up window.
 * Dependencies    : unisim DSP48E1 (xsim: xelab <tb> glbl -L unisim)
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M1). Bias-embedded
 *     packing proven exact by exhaustive 2^24 Python bit model +
 *     TB_PE_PACK_PASS; two rejected layouts (baseline literal and
 *     sign-extended gap) documented with their exhaustive fail counts.
 *   - V1.1 (2026-09-16) by LSL : DSP48E1 direct primitive instance
 *     (M12 B0 DSP over-mapping fix; exactly one DSP per PE). clk_i
 *     port added for the mandatory primitive CLK pin.
 *   - V1.2 (2026-09-16) by LSL : UG479 (v1.10) strict compliance --
 *     3-stage pipeline (AREG/BREG/MREG/PREG=1), C/D tie-off per
 *     Table 2-2 note 1, explicit flow-through control attributes,
 *     synchronous DSP resets via new rst_n_i port, w_d3 alignment
 *     delay. LATENCY 0 -> 3 cycles. Gate rerun: M1/M4/M8/M10/M11
 *     chain (frozen numeric contract).
 ************************************************************************/

module yolo_pe_pack #(
    parameter X_W = 8,                        // activation width (int8)
    parameter W_W = 8                         // weight width (int8)
) (
    input  wire               clk_i,          // DSP48E1 CLK (common to all
                                              // internal registers)
    input  wire               rst_n_i,        // V1.2: synchronous resets
                                              // for the 4 live pipeline
                                              // registers (RSTA/B/M/P)
    input  wire signed [X_W-1:0] x0_i,        // activation, N column n
    input  wire signed [X_W-1:0] x1_i,        // activation, N column n+1
    input  wire signed [W_W-1:0] w_i,         // weight, broadcast (OC row)
    output wire signed [16:0]     p0_o,       // lane n   = w*x0 (D+3)
    output wire signed [16:0]     p1_o        // lane n+1 = w*x1 (D+3)
);

    // ---- DSP48E1 operand field geometry ----
    localparam LANE_SHIFT = 17;               // upper lane base bit
    localparam GAP_W      = 9;               // gap bits [16:8]
    localparam A_W        = 25;
    localparam B_W        = 18;
    localparam P_W        = A_W + B_W;        // 43

    // ---- x0 biased to unsigned byte: x0b = x0 + 128 == MSB flip ----
    wire [X_W-1:0] x0b = {~x0_i[X_W-1], x0_i[X_W-2:0]};

    // ---- A = x1*2^17 + x0b (x1 signed at the operand top, gap zero).
    //      The A port is 30-bit; the multiplier uses A[24:0]. ----
    wire [29:0] a_w = {5'b00000, x1_i, {GAP_W{1'b0}}, x0b};

    // ---- B = w sign-extended to 18 bits ----
    wire [B_W-1:0] b_w = {{(B_W-W_W){w_i[W_W-1]}}, w_i};

    // ---- P = A*B in exactly one DSP48E1 (tie-off validated on the
    //      unisim model: 11264 vectors incl. all sign corners, 0 fail).
    //      V1.2 pipeline (UG479 p.14/p.47): inputs in cycle D ->
    //      A2/B2 at edge D -> M at edge D+1 -> P at edge D+2 ->
    //      dsp_p_w valid in cycle D+3. ----
    wire [47:0] dsp_p_w;

    DSP48E1 #(
        // 3-stage multiply pipeline (UG479 p.14, p.47)
        .AREG(1), .BREG(1), .MREG(1), .PREG(1),
        // UG479 Table 2-3: AREG=1 -> ACASCREG must be 1 (B likewise)
        .ACASCREG(1), .BCASCREG(1),
        // UG479 Table 2-2 note 1 (unused data ports: tie High, select
        // the port register, CE/RST Low -- leakage power rule)
        .CREG(1), .DREG(1),
        .ADREG(0),                             // pre-adder path unused
        // controls flow through (static constants); OPMODEREG must
        // equal CARRYINSELREG (UG479 p.41)
        .OPMODEREG(0), .CARRYINSELREG(0), .ALUMODEREG(0),
        .INMODEREG(0), .CARRYINREG(0),
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"), .USE_DPORT("FALSE"),
        .USE_MULT("MULTIPLY"), .USE_SIMD("ONE48"),
        .USE_PATTERN_DETECT("NO_PATDET")
    ) u_dsp48 (
        .CLK(clk_i),
        .A(a_w), .ACIN(30'b0), .B(b_w), .BCIN(18'b0),
        // unused C/D per Table 2-2 note 1: all ones, reg selected,
        // CE Low, RST Low (the dead registers hold their initial
        // state; their loads -- Z mux=0 and pre-adder off -- never
        // select them)
        .C(48'hFFFFFFFFFFFF), .D(25'h1FFFFFF), .PCIN(48'b0),
        .CARRYIN(1'b0), .CARRYCASCIN(1'b0), .CARRYINSEL(3'b000),
        .INMODE(5'b00000), .OPMODE(7'b0000101), .ALUMODE(4'b0000),
        // live pipeline registers: CE High (A2/B2 are the AREG=1/
        // BREG=1 stages per Table 2-3; M/P always); dead stages: CE Low
        .CEA2(1'b1), .CEB2(1'b1), .CEM(1'b1), .CEP(1'b1),
        .CEA1(1'b0), .CEB1(1'b0), .CEAD(1'b0),
        .CEC(1'b0), .CED(1'b0),
        .CEALUMODE(1'b0), .CECTRL(1'b0), .CECARRYIN(1'b0),
        .CEINMODE(1'b0),
        // synchronous active-high resets with priority (Table 2-4) on
        // the live registers; C/D RST stay Low per Table 2-2 note 1;
        // control registers do not exist (attrs = 0)
        .RSTA(~rst_n_i), .RSTB(~rst_n_i), .RSTM(~rst_n_i),
        .RSTP(~rst_n_i),
        .RSTC(1'b0), .RSTD(1'b0), .RSTALLCARRYIN(1'b0),
        .RSTALUMODE(1'b0), .RSTCTRL(1'b0), .RSTINMODE(1'b0),
        .MULTSIGNIN(1'b0),
        .P(dsp_p_w),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .PATTERNBDETECT(),
        .PATTERNDETECT(), .PCOUT(), .UNDERFLOW()
    );

    wire signed [P_W-1:0] p_w = dsp_p_w[P_W-1:0];

    // ---- w alignment: the bias correction must use the w that was
    //      sampled into B2 in cycle D, but P only appears in D+3 --
    //      delay w by the same 3 stages (UG479 pipeline retiming;
    //      values identical, alignment only). ----
    reg signed [W_W-1:0] w_d1_r, w_d2_r, w_d3_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            w_d1_r <= {W_W{1'b0}};
            w_d2_r <= {W_W{1'b0}};
            w_d3_r <= {W_W{1'b0}};
        end else begin
            w_d1_r <= w_i;
            w_d2_r <= w_d1_r;
            w_d3_r <= w_d2_r;
        end
    end

    // ---- lane0: undo the +128 bias with the shifted broadcast w ----
    wire signed [16:0] lane0_raw = $signed(p_w[16:0]);
    wire signed [16:0] w_sh7     = $signed({{2{w_d3_r[W_W-1]}}, w_d3_r,
                                             7'b0000000});
    assign p0_o = lane0_raw - w_sh7;

    // ---- lane1: restore the borrow taken by a negative low product ----
    wire signed [16:0] lane1_raw = $signed(p_w[33:LANE_SHIFT]);
    assign p1_o = lane1_raw + $signed({16'b0, p_w[16]});

endmodule
