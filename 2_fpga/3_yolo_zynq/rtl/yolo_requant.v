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
 *                   rne_shift / sat_i8 semantics bit-for-bit identical
 *                   to rtl/yolo_conv_core.v (V1.1, TB_CONVGEN_PASS) /
 *                   pynq/intarith.py (G2 contract).
 *
 *                   V1.1 pipeline split (B0 dbg7c: the V1.0 single-
 *                   cycle 47-level chain was the -24.6ns owner):
 *                     c0: capture acc/bias/m/shift (+v0)
 *                     c1: sum_b 33b add                         (+v1)
 *                     c1b: operand re-registration (V1.2g:
 *                         sum_x/m_x, DSP AREG/BREG candidates)  (+v1b)
 *                     c2: prod 33x32 mult (DSP-absorbable:
 *                         registered operands and result)        (+v2)
 *                     c2b: prod2 = prod re-registered (V1.2f:
 *                         fabric stage, DSP PREG -> FF)          (+v2b)
 *                     c3: q = prod >>> s ; half = prod[s-1] (variable
 *                         bit mux) ; sticky = (|lo | q[0]) folded to
 *                         ONE bit (V1.2)                     (+v3)
 *                     c4: y_pre = sat_i8(q + round_up)          (out)
 *                     round_up = half & sticky, forced 0 when
 *                     s == 0 (half = 0) -- identical to the V1.0
 *                     rne_shift function since |(p & (2^(s-1)-1))
 *                     == |(p << (65-s)) exactly (bit set bijection
 *                     p[s-2:0] -> nonzero). Latency 1 -> 7 cycles
 *                     (V1.2g), throughput 1/cycle, en_i=0 holds every
 *                     stage (y_pre_o only changes for valid beats).
 *
 *                   Domain contract:
 *                     - shift in [0, 62];
 *                     - m in [-2^31+1, 2^31-1]. INT32_MIN is excluded:
 *                       |sum_b| <= 2^32 keeps |prod| < 2^63 for every
 *                       other m (bit-exact int64 semantics); m = -2^31
 *                       with sum_b = -2^32 would wrap. Real model M is
 *                       positive in [2^30, 2^31); the negative rail is
 *                       adversarial coverage, +-（2^31-1) included.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M5).
 *   - V1.1 (2026-09-16) by LSL : 5-stage pipeline (B0 -24.6ns fix);
 *     numeric function bit-identical, latency 1 -> 5, throughput
 *     unchanged. Gate: M5 (TB scoreboard for the new latency).
 *   - V1.2 (2026-09-16) by LSL : B0 dbg8e requant −1.75ns/22 级（c4 拍
 *     64 位 lo_sh OR 归约 + 舍入加 + 饱和全链）——lo_sh 降为 c3 组合
 *     线，跨寄存器边界的只剩 1 位 sticky = (|lo_sh)|prod[s]（与旧
 *     (|lo_sh_r)|q_r[0] 对同一 prod/s 逐位等价）；c4 只剩 half&sticky、
 *     舍入加与饱和。流水深度/吞吐不变（PIPE=5 不变）。门重跑：M5 +
 *     M10 + B0 v16。dbg8f 后精化一：掩码式（v17 跑，位精确）——但
 *     dbg8g 显示反而 22 级（(1<<(s-1))-1 借位链成纹波），且原桶形式
 *     18 级里 prod[s] 位选串在树后。精化二（V1.2b）：桶形式保留，q[0]
 *     位选挪到 c2 沿（q_lsb_r <= prod_c_w[s_r1]，与乘法寄存同沿并行），
 *     c3 = 桶形 6+OR 树 6+OR 1 ≈13 级。位精确同上。门重跑：M5 v18 +
 *     M10 v18 + B0 v18。
 *   - V1.2c (2026-09-17) by LSL : B0 v19 OOC FAIL 根治——V1.2b 的 c2
 *     组合位选 tap（prod_c_w[s_r1]）迫使综合把 33x32 乘法拆出 DSP 级
 *     联、部分积落 fabric CARRY4 纹波：v19 实测 sum→prod_r −2.868ns/
 *     14 级（v17 同行 RTL +0.379ns/1 级纯 DSP 吸收）、sum→q_lsb_r
 *     −4.853ns/18 级（2×DSP 级联+12×CARRY4+MUXF7/8，本 OOC WNS
 *     owner）。修复：删 c2 tap 与 q_lsb_r 寄存器，位选挪回 c3 沿从
 *     **已寄存**的 prod_r[s_r2] 取——与桶形（6 级）/OR 树（6 级）并
 *     联、根上一元 OR（mux 3 级不串树后），c3 仍 ≈13 级；乘法恢复
 *     v17 映射。位值逐位相同（同一 prod 同一 s 仅晚一拍相对乘法寄存
 *     采样，sticky_r 捕获拍不变）、PIPE=5/吞吐/hold 语义全不变——
 *     M5 黄金无需再生成（v18 激励直接复跑）。门重跑：M5 v20 + M10
 *     v20 + B0 v20。
 *   - V1.2d (2026-09-17) by LSL : B0 v21 ooc 残余两档同批位精确修复
 *     （PIPE=5/吞吐/hold 语义不变，M5 黄金继续复用）：
 *     ① c3 owner prod_r→sticky_r −0.713——V1.2c 形式 |(prod<<(65−s))
 *     综合为 64b 桶形串 64b OR 树（~12L）。位 j 经该移位存活（j+65−s
 *     ≤63）⟺ j≤s−2，故 |(prod<<(65−s)) == |prod[s−2:0] 严格成立——
 *     桶形改为与 c2 沿预寄存的 mask_r（= ~(全 1<<(s−1))，仅依赖 s_r1，
 *     与乘法完全并联；c2 余量大：v17 DSP 级联路径 +0.379）AND 后 OR
 *     树（2+6L），prod[s] 位选并联。移位借位链规避：掩码用"移位后取
 *     反"而非 (1<<k)−1（后者 64 位借位纹波）。s=0 掩 0（旧行为
 *     移位 ≥64 → 0，逐位一致）。
 *     ② c4 档 sticky_r→y_pre_o −0.563——V1.0 sat_i8 全 64 位加+双向比
 *     较（~18L）改为范围归约：在域 [−128,127] ⟺ q[63:7] 全 0 或全 1
 *     （56b OR/AND 归约并联 ~6L），域内仅 q[7:0]+ru 的 9 位加有意义
 *     且唯一溢出为 +128（q=127&ru=1）。穷举边界核验逐位一致（域外
 *     饱和先于加法跨界、−128+ru≤1 不下溢）。首版溢出判据
 *     sum9[8]&&!sum9[7] 位序写反（128 的 9 位补码是 0_1000_0000，
 *     [8]=0），M5 v22 门拦下 13 错（全部 y=−128 exp=127 即本例）——
 *     改 (sum9==9'd128) 后复跑通过。教训：数值路径改动必跑门再进门
 *     链下游（本次 M10/eng/OOC v22 均在 M5 FAIL 后即刻终止重发）。
 *     门重跑：M5 v22 + M10 v22 + B0 v22（含 M12 csr/eng）。
 *   - V1.2e (2026-09-17) by LSL : B0 v23 ooc（top10 全体 prod_c_w__2/CLK
 *     →q_r −0.457…−0.340——c3 拍 64 输出桶形 `prod >>> s` 本体，DSP P
 *     寄存 CLK→P + 6 级 mux + 64 负载路由）。q_r 的全部消费者只需三样：
 *     ① q[7:0]（c4 9 位舍入加）——q[j]=prod[j+s]，越界补符号，即 8 个
 *     64:1 窗口 mux（每比特 idx=(s+j)>63 判符号，2+3L）；② q[63]——
 *     算术右移保号，恒等于 prod[63]（0L）；③ 在域判定——q∈[−128,127]
 *     ⟺ −2^(s+7) ≤ prod ≤ 2^(s+7)−1（floor 除法边界反推），即
 *     magn<2^(s+7)，magn = prod[63]?~prod:prod（2L），用 c2 沿从 s_r1
 *     预寄存的 himask_r（= ~(全1<<(s+7))，s≥57 → 0 = 恒过，与 mask_r
 *     同模式同沿）AND 后 6L OR 归约。64 位桶形整体消失（64 FF → 10 FF）。
 *     c4 域内/域外臂逐位等价（sum9 用 q8_r，饱和方向用 qneg_r，ir_r =
 *     原 ir_pos||ir_neg）。PIPE=5/吞吐/hold 语义不变，M5 黄金继续复用。
 *     首版 himask 写成 ~(全1<<(s+7))——那是低位掩码 2^t−1，等价于拿
 *     magn 的低 t 位做在域判定（向量 acc=−257,s=1：q=−129 域外被判
 *     域内，窗口 0x7F+ru=1 触发 ovf → +127，黄金 −128）；M5 v24 门
 *     拦下 2739 错（错型 y=+127 exp=0x80），改全 1<<(s+7) 后复跑通过
 *     （失败 transcript 留档 m5_v24a_xsim_fail.log）。与 V1.2d 的 ovf
 *     判据同属"位级手推 vs 数值字面量"类错误，第二次被 M5 拦截。
 *     门重跑：M5 + M10 + M12 csr + B0 v24。
 *   - V1.2f (2026-09-17) by LSL : B0 v24 ooc 残档（top10 六条
 *     prod_c_w__2/CLK→q8_r/ir_r/half_r −0.224…−0.076）——64 位桶形虽已
 *     消失，但窗口 mux/掩码 OR 树仍从 DSP 内部发火：prod_r 被综合吸收
 *     为 DSP48E1 P 寄存器，CLK→P 出 DSP 的长连线 + 3 级 64:1 窗口
 *     mux（q8_r 数据侧）为剩余关键维，同拍位选无解（64:1 = 3 级 LUT
 *     不可再降）。修复：乘法寄存后增设一级 fabric 重寄存 prod2_r
 *     （PIPE 5→6，纯输出侧重定时）：解码拍从布局自由的 fabric FF 发火，
 *     mask_r/himask_r 相应挪至 c2b 沿从 s_r2 生成（同值晚一拍，位精确）。
 *     y_pre_o/vld_o 晚一拍出现，数值逐位不变；下游全为 vld 门控的按序
 *     消费（Y 分段器 rq_rdy 背压、M10/M12 字节序比对、M11 headcheck
 *     sha256），ctrl S_DRAIN 不受影响（其长度由 gemm_array 侧 acc 落地
 *     链决定，与 requant 内部深度无关——输入在 S_RQ 的 rq_en 拍即被 c0
 *     捕获）。M5 记分板按序配对（en 拍入队/vld 拍出队），黄金 hex 复用，
 *     仅 TB 的 PIPE 影子链参数 5→6。门重跑：M5 v25 + M10 v25 +
 *     M12 csr v25 + B0 v25。
 *   - V1.2g (2026-09-17) by LSL : B0 v25 ooc 残档（top10 全体同族
 *     sum_r_reg/C→prod_c_w__2/PCIN −0.079）——33x32 乘法映射为 2-DSP
 *     级联，DSP1 被组合穿透（A 脚→乘法器→加法器→PCOUT 4.036ns，占
 *     数据路径 5.262ns 的 85%；起因：sum_r 是 c1 加法器的输出，无输入
 *     寄存器可供吸收）。修复：乘法操作数增设一级直通重寄存 sum_x_r/
 *     m_x_r（c1b 沿，PIPE 6→7，纯输入侧重定时），为映射器提供
 *     AREG/BREG 候选——级联跳变改从 DSP 内部寄存器发火，外部 FDCE
 *     0.46ns + 布线 0.77ns + DSP A 入口级全部离径。s 链相应伸长一级
 *     （s_x_r），数值逐位不变（同一乘积仅晚一拍）。下游同 V1.2f 论证
 *     （按序 vld 门控消费；gemm_array V1.9 尾链适配 d8→d9）。M5 黄金
 *     复用，TB PIPE 6→7。门重跑：M5 v26 + M10 v26 + M12 csr v26 +
 *     B0 v26。
 ************************************************************************/

module yolo_requant #(
    parameter ACC_W = 32                    // acc/bias operand width
) (
    input  wire                    clk_i,
    input  wire                    rst_n,
    input  wire                    en_i,    // 0 = hold pipeline
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

    // ---- stage 0: operand capture ----
    reg signed [ACC_W-1:0] acc_r0;
    reg signed [ACC_W-1:0] bias_r0;
    reg signed [31:0]      m_r0;
    reg [7:0]              s_r0;
    reg                    v0_r;

    // ---- stage 1: bias add ----
    reg signed [SUM_W-1:0]  sum_r;
    reg signed [31:0]       m_r1;
    reg [7:0]               s_r1;
    reg                     v1_r;

    // ---- stage 1b: multiply operand re-registration (V1.2g) ----
    // v25 OOC sole owner family: sum_r_reg/C -> prod_c_w__2/PCIN -0.079.
    // The 33x32 multiply maps to a 2-DSP cascade; DSP1 is traversed
    // combinationally (A pin -> multiplier -> adder -> PCOUT, 4.04ns of
    // the 5.26ns data path) because no input registers exist to absorb --
    // sum_r is the c1 adder's own output. One pass-through stage on both
    // operands gives the mapper AREG/BREG candidates; the cascade hop
    // then launches from a DSP-internal register (external FDCE 0.46 +
    // route 0.77 + DSP A-input stage all leave the path).
    reg signed [SUM_W-1:0]  sum_x_r;
    reg signed [31:0]       m_x_r;
    reg [7:0]               s_x_r;
    reg                     v1b_r;

    // ---- stage 2: multiply ----
    reg signed [PROD_W-1:0] prod_r;    // DSP PREG (synthesis absorbs this
                                       // register into the DSP48E1 output)
    reg [7:0]               s_r2;
    reg                     v2_r;

    // ---- stage 2b: product re-registration (V1.2f) ----
    reg signed [PROD_W-1:0] prod2_r;   // fabric re-register of the product:
                                       // the v24 OOC owner family launched
                                       // INSIDE the DSP (P-reg -> 64:1
                                       // window mux / mask OR trees across
                                       // the long DSP->fabric route, no
                                       // same-cycle fix: 64:1 = 3 LUT
                                       // levels is irreducible); one more
                                       // cycle gives the decode a
                                       // placer-free fabric launch FF
    reg [7:0]               s3_r;      // s_r2 delayed one (decode select)
    reg                     v2b_r;

    // masks are generated at the c2b edge from s_r2 (V1.2f: same values,
    // one cycle later than V1.2d/V1.2e made them from s_r1 -- they must
    // be current during the c3 DECODE cycle, which now reads prod2_r)
    reg [PROD_W-1:0]        mask_r;   // V1.2d: bits [s-2:0] sticky mask
                                      // (independent of the multiply -- a
                                      // pure parallel barrel; plenty of
                                      // slack in its cycle)
    reg [PROD_W-1:0]        himask_r; // V1.2e: bits [63:s+7] high mask
                                      // (= all-ones << (s+7); 0 when
                                      // s >= 57 -- bound 2^(s+7) then
                                      // exceeds any int64 magnitude, the
                                      // in-range test is constant-true)

    // ---- stage 3: RNE shift decode (V1.2e: windowed -- no 64b barrel;
    //      V1.2f: launches from the fabric prod2_r, not the DSP PREG) ----
    reg [7:0]               q8_r;     // q[7:0] window (q = prod >>> s):
                                      // q[j] = prod[j+s], sign-filled past
                                      // bit 63 -- eight 64:1 window muxes
    reg                     qneg_r;   // q[63]: arithmetic shift preserves
                                      // the sign, so q[63] == prod[63]
    reg                     ir_r;     // in-range [-128,127], algebraic form
                                      // -2^(s+7) <= prod <= 2^(s+7)-1
    reg                     half_r;         // prod[s-1], 0 when s==0
    reg                     sticky_r;       // V1.2: (|lo_sh)|q[0] folded
                                            // to ONE bit at the c3 edge
                                            // (was a 64b reg + 64b OR
                                            // reduce inside c4)
    reg                     v3_r;

    // c3 combinational decode (V1.2d: sticky via MASKED OR -- the V1.2c
    // form |(prod << (65-s)) synthesized as a 64b barrel feeding a 64b OR
    // tree serially, ~12L: the v21 WNS owner -0.713). Bit j of prod survives
    // that shift (j + 65-s <= 63) iff j <= s-2, so |(prod << (65-s)) ==
    // |prod[s-2:0] exactly -- replace the barrel by AND with mask_r
    // (registered at c2b, = ~(all-ones << (s-1))): AND 2L + OR tree 6L,
    // prod2_r[s3_r] bit-mux (3L) in parallel, root OR. Same bit, same edge.
    wire              sticky_w = prod2_r[s3_r] | (|(prod2_r & mask_r));

    // V1.2e: q[7:0] window -- q[j] = prod[j+s] for j+s <= 63, prod[63]
    // (sign fill) beyond. Eight 64:1 muxes (2L guard + 3L select), one FF
    // load each -- replaces the 64-output barrel (v23 owner -0.457).
    wire [7:0] q8_w;
    genvar     gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_q8win
            wire [8:0] idx_w = {1'b0, s3_r} + gi;
            assign q8_w[gi] = (idx_w > 9'd63) ? prod2_r[63]
                                                 : prod2_r[idx_w[5:0]];
        end
    endgenerate

    // V1.2e: in-range test without q's high bits: q in [-128,127] (floor
    // division by 2^s) iff -2^(s+7) <= prod <= 2^(s+7)-1 iff
    // magn < 2^(s+7), magn = prod[63] ? ~prod : prod. Bit-exact against
    // the V1.2d ir_pos/ir_neg pair (same predicate, algebraic form).
    wire [PROD_W-1:0] magn_w = prod2_r[63] ? ~prod2_r : prod2_r;
    wire              ir_w   = !(|(magn_w & himask_r));

    wire round_up_w = half_r & sticky_r;

    // c2 multiply (V1.2c: pure DSP-cascade mapping, no combinational
    // taps -- the V1.2b q_lsb tap here was the v19 OOC root cause;
    // V1.2g: operands are the c1b registers so the cascade hop launches
    // from DSP input registers, not the fabric sum_r FF)
    wire signed [PROD_W-1:0] prod_c_w = sum_x_r * m_x_r;

    // ---- stage 4: rounding add + saturate, V1.2e windowed inputs ----
    // In-range was resolved at c3 (ir_r); the add needs only the q[7:0]
    // window (sum9, 9 bits) and the saturate direction only q[63]
    // (qneg_r; arithmetic shift preserves the sign). +128 remains the
    // sole in-range overflow (q=127 & ru=1); the out-of-range arm
    // saturates before the add can cross a boundary, and q=-128 + ru
    // cannot underflow.
    wire [8:0] sum9_w   = {q8_r[7], q8_r} + {8'd0, round_up_w};
    wire       ovf_w    = (sum9_w == 9'd128);     // +128 = 9'b0_1000_0000
                                                  // (first cut tested [8]&&! [7]
                                                  // -- wrong bit: 128's 9b
                                                  // encoding has [8]=0; the
                                                  // M5 v22 FAIL's 13 errors
                                                  // were exactly this case)

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            acc_r0   <= {ACC_W{1'b0}};
            bias_r0  <= {ACC_W{1'b0}};
            m_r0     <= 32'sd0;
            s_r0     <= 8'd0;
            v0_r     <= 1'b0;
            sum_r    <= {SUM_W{1'b0}};
            m_r1     <= 32'sd0;
            sum_x_r  <= {SUM_W{1'b0}};
            m_x_r    <= 32'sd0;
            s_x_r    <= 8'd0;
            v1b_r    <= 1'b0;
            s_r1     <= 8'd0;
            v1_r     <= 1'b0;
            prod_r   <= {PROD_W{1'b0}};
            s_r2     <= 8'd0;
            v2_r     <= 1'b0;
            prod2_r  <= {PROD_W{1'b0}};
            s3_r     <= 8'd0;
            v2b_r    <= 1'b0;
            mask_r   <= {PROD_W{1'b0}};
            himask_r <= {PROD_W{1'b0}};
            q8_r     <= 8'd0;
            qneg_r   <= 1'b0;
            ir_r     <= 1'b0;
            half_r   <= 1'b0;
            sticky_r <= 1'b0;
            v3_r     <= 1'b0;
            y_pre_o  <= 8'sd0;
            vld_o    <= 1'b0;
        end else begin
            // c0
            v0_r <= en_i;
            if (en_i) begin
                acc_r0  <= acc_i;
                bias_r0 <= bias_i;
                m_r0    <= m_i;
                s_r0    <= shift_i;
            end
            // c1
            v1_r <= v0_r;
            if (v0_r) begin
                sum_r <= $signed({bias_r0[ACC_W-1], bias_r0}) + acc_r0;
                m_r1  <= m_r0;
                s_r1  <= s_r0;
            end
            // c1b (V1.2g: multiply operand re-registration)
            v1b_r <= v1_r;
            if (v1_r) begin
                sum_x_r <= sum_r;
                m_x_r   <= m_r1;
                s_x_r   <= s_r1;
            end
            // c2 (multiply only -- V1.2f: masks moved to the c2b edge,
            // where their input s_r2 is registered and their consumer
            // cycle is exactly one later)
            v2_r <= v1b_r;
            if (v1b_r) begin
                prod_r  <= prod_c_w;
                s_r2    <= s_x_r;
            end
            // c2b (V1.2f: product re-registration + mask barrels, all
            // launching from registers -- pure route + FF for prod2_r,
            // ~3L shift for the masks from s_r2)
            v2b_r <= v2_r;
            if (v2_r) begin
                prod2_r <= prod_r;
                s3_r    <= s_r2;
                // V1.2d: ~(all-ones << (s-1)) = bits [s-2:0], no borrow
                // chain (shift-then-invert; a (1<<k)-1 subtractor would
                // ripple). s=0 -> mask 0 (sticky then = prod[0] alone,
                // matching the old shift>=64 -> 0 exactly).
                mask_r  <= (s_r2 == 8'd0) ? {PROD_W{1'b0}}
                          : ~({PROD_W{1'b1}} << (s_r2 - 8'd1));
                // V1.2e: in-range HIGH mask = bits [63:s+7] = all-ones
                // << (s+7) (NOT ~(ones<<(s+7)) -- that is the low mask
                // 2^t-1, the first cut tested magn's LOW bits and the
                // M5 v24 FAIL's 2739 errors were exactly that inversion);
                // s >= 57 -> 0 (bound 2^(s+7) > any int64 magnitude, test
                // const-true). Single shift, no borrow form.
                himask_r <= (s_r2 >= 8'd57) ? {PROD_W{1'b0}}
                          : ({PROD_W{1'b1}} << (s_r2 + 8'd7));
            end
            // c3
            v3_r <= v2b_r;
            if (v2b_r) begin
                // V1.2e: windowed decode -- q8/qneg/ir replace the 64b
                // barrel `q_r <= prod_r >>> s_r2` (v23 owner -0.457);
                // V1.2f: sources are prod2_r/s3_r (fabric launch);
                // half/sticky unchanged (parallel, both already passing)
                q8_r     <= q8_w;
                qneg_r   <= prod2_r[63];
                ir_r     <= ir_w;
                half_r   <= (s3_r == 8'd0) ? 1'b0 : prod2_r[s3_r - 8'd1];
                sticky_r <= sticky_w;
            end
            // c4
            vld_o <= v3_r;
            if (v3_r) begin
                y_pre_o <= ir_r
                         ? (ovf_w ? 8'sd127 : sum9_w[7:0])
                         : (qneg_r ? -8'sd128 : 8'sd127);
            end
        end
    end

endmodule
