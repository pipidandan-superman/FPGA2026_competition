/************************************************************************
 * File Name       : yolo_pe_core.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_pe_core
 * Description     : Single-PE wrapper for the new PE/GEMM line
 *                   (PE design manual 2026-09-18, section 5 interface).
 *
 *                   The multiply core is the PROVEN V1.2 yolo_pe_pack
 *                   (read-only reuse -- its DSP48E1 primitive config is
 *                   copied byte-for-byte by instantiation, not retyped):
 *                   AREG=BREG=MREG=PREG=1, ACASCREG=BCASCREG=1, C/D
 *                   tied per UG479 Table 2-2 note 1, controls flow
 *                   through, OPMODE=7'b0000101, one DSP per PE, latency
 *                   contract "inputs in cycle D -> products in D+3".
 *
 *                   This wrapper adds exactly the manual section-5
 *                   sideband contract on top:
 *                     - in_valid_i / lane_mask_i ride a 3-stage
 *                       pipeline so out_valid_o / lane_mask_o are
 *                       aligned with p0_o/p1_o presentation (E0->E3,
 *                       manual section 4 sampling-event language).
 *                     - Fixed running pipeline: the DSP computes every
 *                       cycle regardless of in_valid (manual section 4
 *                       recommendation); invalid beats are filtered by
 *                       the valid bit only, and masking/accumulation
 *                       belongs to the downstream MAC stage, not here.
 *                     - rst_i is synchronous active-high in this clock
 *                       domain (manual section 5); it clears the valid
 *                       bits (manual section 7 "reset clears valids"),
 *                       and drives the core's rst_n_i.
 *
 *                   No out_ready: upstream admits by array credit;
 *                   elastic FIFOs live outside the core (manual
 *                   section 5).
 * Dependencies    : rtl/yolo_pe_pack.v (V1.2, read-only reference)
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release. Gate run
 *     2026-09-18_yolo_pe_gemm_dev_run02_singlepe (directed golden
 *     golden_pe.hex + independent-multiply random/corner streams +
 *     256^3 exhaustive + reset/mask/latency scoreboard).
 ************************************************************************/

module yolo_pe_core (
    input  wire               clk_i,       // DSP48E1 CLK, common to all
                                            // pipeline registers
    input  wire               rst_i,       // synchronous, active high
    input  wire               in_valid_i,  // a (w,x0,x1) triple this cycle
    input  wire signed [7:0]  w_i,         // broadcast weight (OC row)
    input  wire signed [7:0]  x0_i,        // activation, N column n
    input  wire signed [7:0]  x1_i,        // activation, N column n+1
    input  wire [1:0]         lane_mask_i, // lane0/lane1 position valid
    output wire               out_valid_o, // products valid (D+3)
    output wire signed [16:0] p0_o,        // w*x0 exact (D+3)
    output wire signed [16:0] p1_o,        // w*x1 exact (D+3)
    output wire [1:0]         lane_mask_o  // mask delayed to products
);

    // ---- proven V1.2 packing core, instantiated NOT retyped ----
    yolo_pe_pack u_pack (
        .clk_i   (clk_i),
        .rst_n_i (~rst_i),
        .x0_i    (x0_i),
        .x1_i    (x1_i),
        .w_i     (w_i),
        .p0_o    (p0_o),
        .p1_o    (p1_o)
    );

    // ---- sideband pipeline: in_valid/lane_mask must cross the same
    //      three edges (E0 A/B regs, E1 M, E2 P) as the products so
    //      they are presented together during cycle D+3 and sampled
    //      by the downstream accumulator at E3. Sync reset clears the
    //      valids -> no stale transaction can be published after a
    //      reset (manual section 7). ----
    reg        v1_r, v2_r, v3_r;
    reg  [1:0] m1_r, m2_r, m3_r;

    always @(posedge clk_i) begin
        if (rst_i) begin
            v1_r <= 1'b0;
            v2_r <= 1'b0;
            v3_r <= 1'b0;
            m1_r <= 2'b00;
            m2_r <= 2'b00;
            m3_r <= 2'b00;
        end else begin
            v1_r <= in_valid_i;
            v2_r <= v1_r;
            v3_r <= v2_r;
            m1_r <= lane_mask_i;
            m2_r <= m1_r;
            m3_r <= m2_r;
        end
    end

    assign out_valid_o = v3_r;
    assign lane_mask_o = m3_r;

endmodule
