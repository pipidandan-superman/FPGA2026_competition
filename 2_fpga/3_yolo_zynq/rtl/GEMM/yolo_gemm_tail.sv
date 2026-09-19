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
 *   Timing: 4-stage pipeline (V2.0 -- the SiLU LUT is a Block Memory
 *   Generator IP instance per the 2026-09-19 hard IP mandate, and a
 *   BMG read always costs one register, so the former asynchronous
 *   LUTRAM read is gone). Element fed during cycle D (in_valid):
 *     edge1 sum registered; edge2 prod registered;
 *     stage3 RNE+sat+addr combinational on prod/sh regs -> the address
 *     drives the BMG read port directly (en = stage-2 valid): BMG
 *     registers it at edge3, dout valid during D+3;
 *     edge4 y registered from (act ? BMG dout : bypass q7) -> y_valid
 *     during cycle D+4. Back-to-back elements stream with no gaps;
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
    // ---- y stream out (cycle D+4) ----
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
    reg signed [7:0]   q7_r   [0:R-1];   //stage3: RNE+sat 结果（旁路路径暂存）
    reg signed [7:0]   y_r    [0:R-1];   //stage4: LUT/旁路结果

    // ---- sideband pipeline（valid/last/act 与数据同拍走）----
    reg v1_r, v2_r, v3_r, v4_r;
    reg last1_r, last2_r, last3_r, last4_r;
    reg act1_r, act2_r, act3_r;

    integer i;

    // ---- 主管线 ----
    always @(posedge clk_i) begin
        if (rst_i) begin
            v1_r <= 1'b0; v2_r <= 1'b0; v3_r <= 1'b0; v4_r <= 1'b0;
            last1_r <= 1'b0; last2_r <= 1'b0; last3_r <= 1'b0; last4_r <= 1'b0;
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
            // stage 3 valid 传播（q7 在 generate 块内寄存；LUT 地址直接驱
            // BMG 读口，BMG 内部寄存器即第 3 级——见各 lane 实例）
            v3_r    <= v2_r;
            last3_r <= last2_r;
            act3_r  <= act2_r;
            // stage 4: y 在 generate 块内自 BMG dout / q7_r 寄存
            v4_r    <= v3_r;
            last4_r <= last3_r;
        end
    end

    // ---- stage 3: RNE -> sat -> addr（组合；addr 驱 BMG，q7 入暂存）----
    //      stage 4: y = act ? BMG dout : q7_r ----
    genvar g;
    generate
        for (g = 0; g < R; g = g + 1) begin : lane
            // 64 位宽的 floor 移位/余数掩码（规避变宽部分选择）
            wire [63:0] mask_w = (sh2_r[g] == 6'd0) ? 64'd0
                               : ((64'd1 << sh2_r[g]) - 64'd1);
            wire [63:0] half_w = 64'd1 << (sh2_r[g] - 6'd1); //仅 sh>0 有效
            wire signed [63:0] qsh_w = prod_r[g] >>> sh2_r[g]; //floor；s=0 恒等
            wire [63:0] rem_w = prod_r[g] & mask_w;
            wire round_up_w = (sh2_r[g] != 6'd0)
                            && ((rem_w > half_w)
                                || ((rem_w == half_w) && qsh_w[0])); //ties to even
            wire signed [63:0] qn_w = qsh_w + (round_up_w ? 64'sd1 : 64'sd0);
            wire signed [63:0] qs_w = (qn_w > 64'sd127)  ? 64'sd127
                                    : (qn_w < -64'sd128) ? -64'sd128
                                    : qn_w;
            wire signed [7:0] q7_w = qs_w[7:0];
            // LUT 地址 = sat + 128（有符号+128，非补码原字节）
            wire [8:0] addr9_w = {q7_w[7], q7_w} + 9'd128;
            wire [7:0] addr_w = addr9_w[7:0];

            // ---- lane LUT：BMG IP（SDP 8x256，读延迟 1）----
            // 例化逐端口对生成 .veo 模板核对（gemm_bm_lut.veo：wea[0:0]，
            // 无 dinb/web/douta 口）。
            // 写口广播（layer load，阵列空闲窗）；读口=stage3 组合地址，
            // enb=v2_r（无效拍地址冻结保持，与流水推进严格同拍）
            wire [7:0] lut_dout;
            gemm_bm_lut u_lut_bmg (
                .clka  (clk_i),
                .ena   (lut_we_i),
                .wea   (1'b1),
                .addra (lut_wa_i),
                .dina  (lut_wd_i),
                .clkb  (clk_i),
                .enb   (v2_r),
                .addrb (addr_w),
                .doutb (lut_dout)
            );

            always @(posedge clk_i) begin
                if (rst_i) begin
                    q7_r[g] <= 8'sd0;
                    y_r[g]  <= 8'sd0;
                end else begin
                    q7_r[g] <= q7_w;                            //stage3 寄存
                    y_r[g]  <= act3_r ? lut_dout : q7_r[g];     //stage4 出
                end
            end

            assign y_o[g] = y_r[g];
        end
    endgenerate

    assign y_valid_o = v4_r;
    assign y_last_o  = v4_r & last4_r;

endmodule
