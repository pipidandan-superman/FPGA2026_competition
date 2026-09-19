/************************************************************************
 * File Name       : tb_gemm_bank_tiers_bmg.sv
 * Description     : run12 tier wrappers (BMG IP bank, 8x16 fixed shape).
 *   Small-shape control coverage moved from the run09 4x4 tier to a
 *   SMALL LOGICAL Kc at 8x16 (bank widths are IP-fixed at generation):
 *   8x16 KC=8   -- small logical-Kc tier, dense off-by-one edges
 *   8x16 KC=64  -- baseline shape (synthesis Kc decided at P1.4: 576/1024)
 *   8x16 KC=576 -- depth-real tier, top-address edge at manual v1 depth
 *   Kc is purely logical (proven by load length; physical depth 1024).
 ************************************************************************/
`timescale 1ns/1ps
module tb_gemm_bank_8x16_kc8;
    tb_yolo_gemm_bankfeeder_bmg #(.P_TO(8), .P_TN(16), .P_KC(8))   u_tier();
endmodule

module tb_gemm_bank_8x16_kc64;
    tb_yolo_gemm_bankfeeder_bmg #(.P_TO(8), .P_TN(16), .P_KC(64))  u_tier();
endmodule

module tb_gemm_bank_8x16_kc576;
    tb_yolo_gemm_bankfeeder_bmg #(.P_TO(8), .P_TN(16), .P_KC(576)) u_tier();
endmodule
