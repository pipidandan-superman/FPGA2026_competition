/************************************************************************
 * File Name       : tb_gemm_bank_tiers.sv
 * Description     : run09 tier wrappers (unit / baseline / depth-real).
 *   4x4 KC=8   -- unit tier, dense off-by-one edges at tiny depth
 *   8x16 KC=64 -- baseline shape (synthesis Kc decided at P1.4: 576/1024)
 *   8x16 KC=576-- depth-real tier, top-address edge at manual v1 depth
 ************************************************************************/
`timescale 1ns/1ps
module tb_gemm_bank_4x4_kc8;
    tb_yolo_gemm_bankfeeder #(.P_TO(4), .P_TN(4),  .P_KC(8))  u_tier();
endmodule

module tb_gemm_bank_8x16_kc64;
    tb_yolo_gemm_bankfeeder #(.P_TO(8), .P_TN(16), .P_KC(64)) u_tier();
endmodule

module tb_gemm_bank_8x16_kc576;
    tb_yolo_gemm_bankfeeder #(.P_TO(8), .P_TN(16), .P_KC(576)) u_tier();
endmodule
