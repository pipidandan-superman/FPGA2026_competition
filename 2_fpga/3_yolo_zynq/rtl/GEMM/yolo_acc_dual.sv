/************************************************************************
 * File Name       : yolo_acc_dual.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_acc_dual
 * Description     : MAC-cell dual INT32 accumulator (PE manual step 2).
 *                   PE manual section 1: MAC = dual-product PE + two
 *                   independent accumulator states; section 6 baseline
 *                   is FF + fabric adders because the same state is
 *                   updated every beat (compute state, not a register
 *                   table).
 *
 *   Contract (PE manual sections 2/6/7/8, GEMM manual section 5):
 *     - inputs are UNPACKED, CORRECTED products (the section-5 PE
 *       output side p0/p1). This cell never sees the packed DSP P and
 *       never re-does packing arithmetic -- section 3 forbids
 *       accumulating the packed P across K (cross-lane carry);
 *     - each product is sign-extended 17->32 BEFORE the add;
 *     - a first_k beat executes acc = p (section 7: no clr+en
 *       same-edge first-term loss). K-block boundaries are simply
 *       in_valid=0 beats: state holds, the next block resumes WITHOUT
 *       first_k (breakpoint resume);
 *     - lane_mask gates updates per lane and is TILE-CONSTANT
 *       (structural OC/N tail, generated at array level). A lane
 *       masked for the whole tile keeps stale content and must never
 *       be published downstream;
 *     - last_k tags the last ACCEPTED product beat. acc_done_o pulses
 *       the cycle AFTER that beat's accumulation edge -- the GEMM
 *       section-5 DRAIN_PE leave condition: the last valid product
 *       has ENTERED the accumulator. first_k and last_k on the same
 *       beat is the legal K=1 case;
 *     - int32 two's-complement add with natural wrap. The contract
 *       domain never wraps (section 8: K<=2304 conservative bound
 *       2304*128*128 = 37,748,736 << 2^31); out-of-domain models are
 *       rejected at export, not "fixed" by saturation here;
 *     - clr_i is a synchronous tile-restart clear (priority over
 *       accumulation on the same edge). The ARRAY must stop issuing
 *       and let the PE pipeline drain before asserting clr_i: this
 *       cell tracks no upstream in-flight state (section 5: counters
 *       live at array level, not per PE).
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release (manual step 2).
 ************************************************************************/

module yolo_acc_dual (
    input  wire               clk_i,       //运算时钟
    input  wire               rst_i,       //本时钟域同步复位，高有效
    input  wire               clr_i,       //tile 级同步清零（清零重启），优先于累加
    input  wire               in_valid_i,  //本拍有已解包乘积（E3 采样沿）
    input  wire signed [16:0] p0_i,        //lane0 精确乘积（PE §5 输出侧）
    input  wire signed [16:0] p1_i,        //lane1 精确乘积
    input  wire [1:0]         lane_mask_i, //tile 常量结构掩码（OC/N 尾）
    input  wire               first_k_i,   //本拍为 tile 首个被接受乘积：acc = p
    input  wire               last_k_i,    //本拍为最后一个被接受乘积
    output wire signed [31:0] acc0_o,      //lane0 INT32 部分和（寄存输出）
    output wire signed [31:0] acc1_o,      //lane1 INT32 部分和
    output wire               acc_done_o   //单拍脉冲：末乘积已落账，acc 为终值
);

    // ---- section 2: sign-extend BEFORE the add ----
    wire signed [31:0] p0_ext = {{15{p0_i[16]}}, p0_i};
    wire signed [31:0] p1_ext = {{15{p1_i[16]}}, p1_i};

    reg signed [31:0] acc0_r, acc1_r;
    reg               done_r;

    always @(posedge clk_i) begin
        if (rst_i) begin
            acc0_r <= 32'sd0;
            acc1_r <= 32'sd0;
            done_r <= 1'b0;
        end else if (clr_i) begin
            acc0_r <= 32'sd0;
            acc1_r <= 32'sd0;
            done_r <= 1'b0;
        end else begin
            done_r <= 1'b0;               //脉冲语义：默认单拍
            if (in_valid_i) begin
                if (lane_mask_i[0])
                    acc0_r <= first_k_i ? p0_ext : (acc0_r + p0_ext);
                if (lane_mask_i[1])
                    acc1_r <= first_k_i ? p1_ext : (acc1_r + p1_ext);
                if (last_k_i)
                    done_r <= 1'b1;
            end
        end
    end

    assign acc0_o     = acc0_r;
    assign acc1_o     = acc1_r;
    assign acc_done_o = done_r;

endmodule
