/************************************************************************
 * File Name       : tb_yolo_pe_pack.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_pe_pack
 * Description     : M1 gate testbench for yolo_pe_pack (DSP48E1 dual
 *                   int8 packing PE). Drives every vector from the
 *                   pe_pack stimulus set (directed corners + random),
 *                   compares both lanes against the Python bit-model
 *                   expectations, first mismatch decoded.
 *                   Usage (from sim/xsim, V1.1 primitive flow):
 *                     xvlog ../../rtl/yolo_pe_pack.v ../tb_yolo_pe_pack.v \
 *                           <vivado>/data/verilog/src/glbl.v
 *                     xelab tb_yolo_pe_pack glbl -s snap_m1 \
 *                           -L unisim -L unisims_ver -timescale 1ns/1ps
 *                     xsim snap_m1 -R
 *                   (V1.0 ModelSim flow: from sim/msim,
 *                     vsim -c -novopt +STIM=../stim/pe_pack +WDT_MS=100
 *                          -do "run -all; quit -f" work.tb_yolo_pe_pack)
 *                   Gate token: TB_PE_PACK_PASS / TB_PE_PACK_FAIL.
 * Dependencies    : rtl/yolo_pe_pack.v, sim/pe_pack_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M1)
 *   - V1.1 (2026-09-16) by LSL : DUT V1.1 DSP48E1 primitive -- added
 *     clk_i to the instance and a 2us warm-up before the first compare
 *     (unisim model OPMODE mux gate during the first 100ns); xsim is
 *     the primary simulator from this run on (official unisim lib).
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_pe_pack;

    localparam NV = 10216;        // 216 directed + 10000 random (vecgen)

    reg clk = 1'b0;
    integer n_err = 0;
    integer first_idx = 0;
    integer i;

    reg signed [7:0]  mem_x0 [0:NV-1];
    reg signed [7:0]  mem_x1 [0:NV-1];
    reg signed [7:0]  mem_w  [0:NV-1];
    reg signed [16:0] mem_p0 [0:NV-1];
    reg signed [16:0] mem_p1 [0:NV-1];

    reg  signed [7:0]  x0 = 8'sd0;
    reg  signed [7:0]  x1 = 8'sd0;
    reg  signed [7:0]  w  = 8'sd0;
    reg                rst_n = 1'b0;
    wire signed [16:0] p0;
    wire signed [16:0] p1;
    integer            j;

    yolo_pe_pack dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .x0_i(x0),
        .x1_i(x1),
        .w_i(w),
        .p0_o(p0),
        .p1_o(p1)
    );

    always #5 clk = ~clk;

    reg [1023:0] stim = "../stim/pe_pack";
    integer      wdt_ms = 100;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        $display("[tb] pe_pack stim=%0s vectors=%0d", stim, NV);
        $readmemh({stim, "/x0_i8.hex"},      mem_x0);
        $readmemh({stim, "/x1_i8.hex"},      mem_x1);
        $readmemh({stim, "/w_i8.hex"},       mem_w);
        $readmemh({stim, "/p0_exp_i17.hex"}, mem_p0);
        $readmemh({stim, "/p1_exp_i17.hex"}, mem_p1);
        // V1.1: unisim DSP48E1 model warm-up -- its OPMODE muxes are
        // gated for the first 100ns of simulation; compare nothing
        // before the warm-up so the primitive is settled (see pe_pack
        // V1.1). V1.2: DUT is 3-cycle pipelined (A2/B2 -> M -> P):
        // stream one vector per clock, vector i's output appears in
        // iteration i+3 -- compare i-3 against the golden there. Reset
        // (V1.2 rst_n_i) held low through warm-up cycle 0..3.
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        repeat (200) @(negedge clk);          // 2us settle (>> 100ns gate)
        for (i = 0; i < NV + 3; i = i + 1) begin
            @(negedge clk);
            if (i < NV) begin
                x0 = mem_x0[i];
                x1 = mem_x1[i];
                w  = mem_w[i];
            end else begin
                x0 = 8'sd0;                   // drain cycles: inputs 0
                x1 = 8'sd0;
                w  = 8'sd0;
            end
            #1;                               // away from the edge
            if (i >= 3) begin
                j = i - 3;                    // output of vector j
                if (p0 !== mem_p0[j] || p1 !== mem_p1[j]) begin
                    n_err = n_err + 1;
                    if (n_err == 1) begin
                        first_idx = j;
                        $display("[tb] first mismatch @vec=%0d x0=%0d x1=%0d w=%0d lane0 got=%0d exp=%0d lane1 got=%0d exp=%0d",
                                 j, mem_x0[j], mem_x1[j], mem_w[j],
                                 p0, mem_p0[j], p1, mem_p1[j]);
                    end
                end
            end
        end
        if (n_err == 0) begin
            $display("TB_PE_PACK_PASS compared=%0d/%0d", NV, NV);
        end else begin
            $display("TB_PE_PACK_FAIL compared=%0d/%0d errors=%0d first_vec=%0d",
                     NV, NV, n_err, first_idx);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_PE_PACK_FAIL (timeout)");
        $finish;
    end

endmodule
