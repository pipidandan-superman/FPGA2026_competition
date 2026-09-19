/************************************************************************
 * File Name       : yolo_gemm_tail.sv
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_gemm_tail
 * Description     : GEMM shared tail (manual step 3, GEMM manual
 *                   section 8): bias -> requant multiply -> RNE ->
 *                   saturate INT8 -> SiLU LUT or linear bypass.
 *                   ONE shared instance per array; per-PE tails are
 *                   explicitly forbidden by the module boundary table.
 *
 *   Arithmetic contract (GEMM manual section 8, frozen order):
 *     sum  = acc + bias_eff          signed 33 bit (parameter already
 *                                     includes the first-layer
 *                                     +128*sum(w_q) correction -- the
 *                                     exporter owns that; hardware
 *                                     adds bias exactly ONCE, at the
 *                                     tail, after ALL K blocks);
 *     prod = sum * M                 signed 64 bit (exporter has
 *                                     verified no overflow for the
 *                                     current package);
 *     RNE  q = floor(prod/2^s), r = prod - q*2^s; round up when
 *               r > 2^(s-1), or r == 2^(s-1) and q odd (ties to even);
 *               s == 0 bypasses the shift entirely (no rounding);
 *     sat  clamp to signed INT8;
 *     LUT  address = sat_q + 128 (signed+128, NOT the raw two's
 *               complement byte), or linear bypass when the layer has
 *               no activation. LUT belongs to the LAYER; bias/M/shift
 *               belong to the OC and are supplied per element by the
 *               array from the tile-locked parameter store.
 *
 *   RNE implementation note (V2.2, run16 WNS decision A+B -- user
 *   authorized 2026-09-19): the frozen SEMANTICS above are unchanged;
 *   only the implementation is restructured, with NO wide carry chain
 *   in the rounding stage:
 *       q    = prod >>> s                      (floor, barrel shift)
 *       ru   = prod[s-1] & ( |rem_low| | prod[s] )
 *   where rem_low = prod & ones_below(s-1). Bitwise equivalence to the
 *   definition: rem > half  <=>  prod[s-1]=1 && rem_low != 0;
 *   rem == half  <=>  prod[s-1]=1 && rem_low == 0 (tie -> q odd =
 *   prod[s]). Hand-verified on positive/negative/tie cases; gate
 *   evidence run17 re-cross-checks the run01 golden vectors and the
 *   random battery. The +ru increment is ABSORBED by a 10-bit add in
 *   the sat stage (255+1=256 -> sat 127, -256+1=-255 -> sat -128 --
 *   boundary push-outs saturate correctly, so no 64-bit increment is
 *   ever needed). V2.1's 65-bit magic-add identity (same semantics)
 *   still left 29 logic levels in one cycle (run20 WNS -2.669) and is
 *   superseded by this parallel form.
 *
 *   Timing: 5-stage pipeline (V2.1 deepened from D+4; V2.2 keeps D+5
 *   and restructures stage 3, splitting RNE and sat/addr). Element fed
 *   during cycle D (in_valid):
 *     edge1 sum registered; edge2 prod registered;
 *     stage3 RNE combinational on prod/sh regs -- quotient barrel
 *     shift and the parallel bitwise rounding decision (no wide
 *     carry chain), edge3 qsh/ru registered;
 *     stage4 sign-extension check + 10-bit absorb add + INT8 saturate
 *     + addr add (all narrow logic) on qsh/ru -> the address drives
 *     the BMG read port directly (en = stage-3 valid): BMG registers
 *     it at edge4, dout valid during D+4; q7 bypass registered at
 *     edge4 alongside;
 *     edge5 y registered from (act ? BMG dout : bypass q7) -> y_valid
 *     during cycle D+5. Back-to-back elements stream with no gaps;
 *     invalid beats carry no state (outputs are gated by the valid
 *     pipeline, stale lane content is never published). Parameter
 *     inputs (bias/M/shift) are registered into the pipe with their
 *     element -- the driver may change them the very next cycle.
 *     LUT storage is instantiated as R independent 256x8 BMG IPs, one
 *     per lane, all written broadcast -- IP instance COUNT is the only
 *     parameterization; no internal parameterized memory expression.
 *
 *   LUT write discipline (unchanged): layer-owned data is loaded while
 *   the array is idle; a write colliding with a read of the same
 *   address is out of contract.
 * Dependencies    : blk_mem_gen IP gemm_bm_lut (Simple Dual Port 8x256)
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release (manual step 3).
 *   - V2.0 (2026-09-19) by LSL : LUT reg-array -> gemm_bm_lut BMG IP;
 *     pipeline D+3 -> D+4 (BMG synchronous read). User IP mandate
 *     redo -- gate evidence run13.
 *   - V2.1 (2026-09-19) by LSL : run16 WNS decision A+B (user
 *     authorized): RNE narrowed to the exact magic-add identity
 *     (65-bit), sat/addr split into their own cycle; pipeline
 *     D+4 -> D+5. Array coordinate mirror deepened to match (array
 *     V2.2). Gate evidence run17/run18/run19/run20 (run20 WNS -2.669:
 *     the 65-bit add + barrel still serialized in one cycle).
 *   - V2.2 (2026-09-19) by LSL : rounding decision restructured to
 *     the parallel bitwise form (OR tree, NO wide carry chain); +ru
 *     absorbed by a 10-bit add in the sat stage. Pipeline STAYS D+5,
 *     mirror/array/TB latency untouched. Gate evidence run17b/18b/
 *     19b/20b (same run dirs, second iteration).
 ************************************************************************/

module yolo_gemm_tail #(
    parameter integer R = 1              // elements per beat (manual: start 1-2)
) (
    input  wire               clk_i,      //运算时钟
    input  wire               rst_i,      //同步复位，高有效（清 valid 流水）
    // ---- element stream in (cycle D) ----
    input  wire               in_valid_i, //本拍 R 个元素有效
    input  wire               in_last_i,  //本拍为 tile 最后一个有效元素
    input  wire signed [R-1:0][31:0] acc_i,   //INT32 部分和（已排空终值）
    input  wire signed [R-1:0][31:0] bias_i,  //bias_eff（OC 参数，含首层修正）
    input  wire signed [R-1:0][31:0] m_i,     //M（OC 参数）
    input  wire        [R-1:0][5:0]  sh_i,    //shift，域 0..62
    input  wire               act_en_i,   //tile 常量：1=LUT，0=线性旁路
    // ---- y stream out (cycle D+5) ----
    output wire               y_valid_o,
    output wire               y_last_o,
    output wire signed [R-1:0][7:0]  y_o,
    // ---- SiLU LUT load (256 x 8, layer-owned data) ----
    input  wire               lut_we_i,
    input  wire        [7:0]  lut_wa_i,
    input  wire        [7:0]  lut_wd_i
);

    // ---- per-lane datapath registers ----
    reg signed [32:0]  sum_r  [0:R-1];   //stage1: acc + bias_eff (33 位有符号)
    reg signed [31:0]  m1_r   [0:R-1];   //stage1: M 随元素入流水
    reg signed [63:0]  prod_r [0:R-1];   //stage2: sum * M
    reg        [5:0]   sh1_r  [0:R-1];   //stage1: shift 入流水
    reg        [5:0]   sh2_r  [0:R-1];   //stage2: shift 随乘积
    reg signed [63:0]  qsh_r  [0:R-1];   //stage3: 商 floor(prod/2^s)
    reg        [0:0]   ru_r   [0:R-1];   //stage3: 舍入判决（并行逐位式）
    reg signed [7:0]   q7_r   [0:R-1];   //stage4: sat 结果（旁路路径暂存）
    reg signed [7:0]   y_r    [0:R-1];   //stage5: LUT/旁路结果

    // ---- sideband pipeline（valid/last/act 与数据同拍走）----
    reg v1_r, v2_r, v3_r, v4_r, v5_r;
    reg last1_r, last2_r, last3_r, last4_r, last5_r;
    reg act1_r, act2_r, act3_r, act4_r;

    integer i;

    // ---- 主管线 ----
    always @(posedge clk_i) begin
        if (rst_i) begin
            v1_r <= 1'b0; v2_r <= 1'b0; v3_r <= 1'b0; v4_r <= 1'b0; v5_r <= 1'b0;
            last1_r <= 1'b0; last2_r <= 1'b0; last3_r <= 1'b0;
            last4_r <= 1'b0; last5_r <= 1'b0;
        end else begin
            // stage 1: sum + 参数入流水
            v1_r    <= in_valid_i;
            last1_r <= in_valid_i & in_last_i;
            act1_r  <= act_en_i;
            for (i = 0; i < R; i = i + 1) begin
                sum_r[i] <= $signed(acc_i[i]) + $signed(bias_i[i]);
                m1_r[i]  <= $signed(m_i[i]);
                sh1_r[i] <= sh_i[i];
            end
            // stage 2: prod
            v2_r    <= v1_r;
            last2_r <= last1_r;
            act2_r  <= act1_r;
            for (i = 0; i < R; i = i + 1) begin
                prod_r[i] <= sum_r[i] * m1_r[i];
                sh2_r[i]  <= sh1_r[i];
            end
            // stage 3: RNE（magic-add 等价式，qn 在 generate 块内寄存）
            v3_r    <= v2_r;
            last3_r <= last2_r;
            act3_r  <= act2_r;
            // stage 4: sat+addr（窄逻辑组合驱 BMG，BMG 内部寄存器即第 4
            // 级；q7 在 generate 块内寄存）
            v4_r    <= v3_r;
            last4_r <= last3_r;
            act4_r  <= act3_r;
            // stage 5: y 在 generate 块内自 BMG dout / q7_r 寄存
            v5_r    <= v4_r;
            last5_r <= last4_r;
        end
    end

    // ---- stage 3: RNE 商移位 + 并行舍入判决（无宽进位链）----
    //      stage 4: SE 判验 + 10 位吸收加 + 饱和 + addr ----
    //      stage 5: y = act ? BMG dout : q7_r ----
    genvar g;
    generate
        for (g = 0; g < R; g = g + 1) begin : lane
            // q = prod >>> s（floor；s=0 恒等）；q 的 LSB = prod[s]
            wire signed [63:0] qsh_w = prod_r[g] >>> sh2_r[g];
            wire parity_w = prod_r[g][sh2_r[g]];
            // rem 低半掩码（s 以下 s-1 位）；s=0 时掩码恒 0
            wire [63:0] rmask_w = (sh2_r[g] == 6'd0) ? 64'd0
                                : ((64'd1 << (sh2_r[g] - 6'd1)) - 64'd1);
            wire remnz_w = |(prod_r[g] & rmask_w);
            // 逐位等价：rem>half ⟺ prod[s-1]&rem_low≠0；tie 且 q 奇 ⟺
            // prod[s-1]&rem_low=0&prod[s]——s=0 恒不舍入
            wire ru_w = (sh2_r[g] != 6'd0) && prod_r[g][sh2_r[g] - 6'd1]
                      && (remnz_w || parity_w);

            // stage 4：|q|<=255 时 [63:8] 为符号扩展，ru 由 10 位窄加吸收
            // （255+1=256→127、−256+1=−255→−128 边界仍正确饱和）；否则按
            // 符号钳位
            wire se_ok_w  = (qsh_r[g][63:8] == {56{1'b0}})
                         || (qsh_r[g][63:8] == {56{1'b1}});
            wire signed [9:0] qse_w = {qsh_r[g][8], qsh_r[g][8:0]};
            wire signed [9:0] q9_w  = qse_w + {{9{1'b0}}, ru_r[g]};
            wire signed [7:0] sat9_w = (q9_w > 10'sd127)  ? 8'sd127
                                    : (q9_w < -10'sd128) ? -8'sd128
                                    : q9_w[7:0];
            wire signed [7:0] q7_w = se_ok_w ? sat9_w
                                   : (qsh_r[g][63] ? -8'sd128 : 8'sd127);
            // LUT 地址 = sat + 128（有符号+128，非补码原字节）
            wire [8:0] addr9_w = {q7_w[7], q7_w} + 9'd128;
            wire [7:0] addr_w = addr9_w[7:0];

            // ---- lane LUT：BMG IP（SDP 8x256，读延迟 1）----
            // 例化逐端口对生成 .veo 模板核对（gemm_bm_lut.veo：wea[0:0]，
            // 无 dinb/web/douta 口）。
            // 写口广播（layer load，阵列空闲窗）；读口=stage4 组合地址，
            // enb=v3_r（无效拍地址冻结保持，与流水推进严格同拍）
            wire [7:0] lut_dout;
            gemm_bm_lut u_lut_bmg (
                .clka  (clk_i),
                .ena   (lut_we_i),
                .wea   (1'b1),
                .addra (lut_wa_i),
                .dina  (lut_wd_i),
                .clkb  (clk_i),
                .enb   (v3_r),
                .addrb (addr_w),
                .doutb (lut_dout)
            );

            always @(posedge clk_i) begin
                if (rst_i) begin
                    qsh_r[g] <= 64'sd0;
                    ru_r[g]  <= 1'b0;
                    q7_r[g]  <= 8'sd0;
                    y_r[g]   <= 8'sd0;
                end else begin
                    qsh_r[g] <= qsh_w;                           //stage3 寄存
                    ru_r[g]  <= ru_w;                            //stage3 寄存
                    q7_r[g]  <= q7_w;                            //stage4 寄存
                    y_r[g]   <= act4_r ? lut_dout : q7_r[g];     //stage5 出
                end
            end

            assign y_o[g] = y_r[g];
        end
    endgenerate

    assign y_valid_o = v5_r;
    assign y_last_o  = v5_r & last5_r;

endmodule
