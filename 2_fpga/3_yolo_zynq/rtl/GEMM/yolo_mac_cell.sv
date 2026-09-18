/************************************************************************
 * File Name       : yolo_mac_cell.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_mac_cell
 * Description     : MAC cell = dual-product PE + two independent INT32
 *                   accumulators (PE manual section 1: this IS the MAC
 *                   definition; level-2 joint of manual steps 1+2).
 *
 *                   Composition only -- both halves are the already
 *                   gated blocks, byte-identical:
 *                     - yolo_pe_core (step 1, run02 GATE + 256^3):
 *                       real DSP48E1 products, in_valid/lane_mask ride
 *                       a 3-stage sideband pipeline, presented during
 *                       cycle D+3 (E3 sampling language);
 *                     - yolo_acc_dual (step 2, run03 GATE): first_k
 *                       executes acc=p, masked lanes hold, last_k ->
 *                       done pulse the cycle after the accumulation
 *                       edge, INT32 natural wrap (contract domain
 *                       2304*128*128 << 2^31).
 *
 *                   The ONE thing this wrapper adds: first_k/last_k
 *                   cross the same three edges as the PE sideband, so
 *                   the array issues tile tags in the E0 domain
 *                   together with the operands (GEMM manual section 5:
 *                   counters live at array level, one issue domain)
 *                   and the accumulator sees them aligned with the
 *                   products at E3.
 *
 *   Timing contract (extends the PE latency contract by one edge):
 *     issue (w,x0,x1,fk,lk,mask,valid) during cycle D
 *       -> products + sideband presented during D+3
 *       -> accumulator samples at the E3 edge (end of D+3)
 *       -> acc0/acc1 updated and acc_done_o pulsed during D+4.
 *     A K=1 tile (fk=lk on the same beat) still pulses done at D+4.
 *
 *   clr_i passes straight to the accumulator (tile-restart clear).
 *   ARRAY CONTRACT, unchanged from step 2: stop issuing AND let the
 *   3-stage product pipeline drain (>= 4 idle beats) before asserting
 *   clr_i -- this cell tracks no upstream in-flight state.
 * Dependencies    : yolo_pe_core.sv, yolo_acc_dual.sv
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release (level-2 joint).
 ************************************************************************/

module yolo_mac_cell (
    input  wire               clk_i,       // DSP/acc 共用运算时钟
    input  wire               rst_i,       //同步复位，高有效（清 PE valids + fk/lk 流水 + acc）
    input  wire               clr_i,       //tile 级同步清零（排空后置位，透传 acc）
    // ---- E0 issue side (array domain) ----
    input  wire               in_valid_i,  //本拍有 (w,x0,x1) 三元组
    input  wire signed [7:0]  w_i,         //广播权重（OC 行）
    input  wire signed [7:0]  x0_i,        //激活，N 列 n
    input  wire signed [7:0]  x1_i,        //激活，N 列 n+1
    input  wire [1:0]         lane_mask_i, //tile 常量结构掩码（OC/N 尾）
    input  wire               first_k_i,   //本拍为 tile 首个被接受乘积
    input  wire               last_k_i,    //本拍为最后一个被接受乘积
    // ---- accumulator outputs (D+4 domain) ----
    output wire signed [31:0] acc0_o,      //lane0 INT32 部分和
    output wire signed [31:0] acc1_o,      //lane1 INT32 部分和
    output wire               acc_done_o   //单拍脉冲：末乘积已落账
);

    // ---- step-1 PE: real DSP48E1 products + valid/mask at D+3 ----
    wire               pe_v;
    wire signed [16:0] pe_p0, pe_p1;
    wire [1:0]         pe_m;

    yolo_pe_core u_pe (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .in_valid_i   (in_valid_i),
        .w_i          (w_i),
        .x0_i         (x0_i),
        .x1_i         (x1_i),
        .lane_mask_i  (lane_mask_i),
        .out_valid_o  (pe_v),
        .p0_o         (pe_p0),
        .p1_o         (pe_p1),
        .lane_mask_o  (pe_m)
    );

    // ---- first_k/last_k: same three edges as the PE sideband ----
    // pure delay line (NOT gated by in_valid): the accumulator filters
    // by its own in_valid_i, so a raw tag on an invalid beat (level-2
    // negative probe) stays side-effect free, exactly like the PE's
    // own in_valid/lane_mask pipeline.
    reg fk1_r, fk2_r, fk3_r;
    reg lk1_r, lk2_r, lk3_r;

    always @(posedge clk_i) begin
        if (rst_i) begin
            fk1_r <= 1'b0; fk2_r <= 1'b0; fk3_r <= 1'b0;
            lk1_r <= 1'b0; lk2_r <= 1'b0; lk3_r <= 1'b0;
        end else begin
            fk1_r <= first_k_i;
            fk2_r <= fk1_r;
            fk3_r <= fk2_r;
            lk1_r <= last_k_i;
            lk2_r <= lk1_r;
            lk3_r <= lk2_r;
        end
    end

    // ---- step-2 accumulator: samples the E3 presentation ----
    yolo_acc_dual u_acc (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .clr_i       (clr_i),
        .in_valid_i  (pe_v),
        .p0_i        (pe_p0),
        .p1_i        (pe_p1),
        .lane_mask_i (pe_m),
        .first_k_i   (fk3_r),
        .last_k_i    (lk3_r),
        .acc0_o      (acc0_o),
        .acc1_o      (acc1_o),
        .acc_done_o  (acc_done_o)
    );

endmodule
