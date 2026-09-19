/************************************************************************
 * File Name     : yolo_gemm_core.sv
 * Developer     : LSL
 * Date          : 2026-09-19
 * Module Name   : yolo_gemm_core
 * Description   : G2 计算核心 V4：yolo_gemm_bank + yolo_gemm_feeder +
 *                 yolo_gemm_array 三体封装（P1.3 run10a 合并门已验证的
 *                 连线，一比一转录，零新增逻辑）。
 *
 *   对外三类口：
 *   - 64b 流式装载写口（+组选择/装载状态）——PS/DMA 侧灌 W/X；
 *   - feeder 作业口（块粒度：len/first/last/组）——调度方（G4 CSR/TB）；
 *   - 阵列 tile 常量/参数/LUT 口与 y 读出口——逐拍出结果。
 *
 *   内部唯一互连：feeder 的 rd_busy→bank ld_ok 硬门控（TDP 同址冲突
 *   结构排除）、feeder↔bank 读侧（组 MUX 在 feeder 出口级）、
 *   feeder→阵列块头+宽字流（word_ready 回握）。
 *
 *   本模块用途：run16 OOC 综合顶层；后续 G4 CSR 接入时作为计算子
 *   系统例化单元。V1.1：bank BMG 化（用户 IP 硬指标重做，2026-09-19）
 *   ——bank 定宽 8×16/物理深度 1024、参数全退役，本封装随之只支持
 *   8×16（P_KC 泛型删除：Kc 为纯逻辑档，由装载长度自证）。
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : run10a 连线封装（仿真证据：
 *     4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run10a_merge/）。
 *   - V1.1 (2026-09-19) by LSL : BMG IP 重做接线（run15/run16 证据）。
 ************************************************************************/

`timescale 1ns/1ps

module yolo_gemm_core #(
    parameter integer P_TO = 8,     //仅支持 8（bank BMG 定宽守卫）
    parameter integer P_TN = 16     //仅支持 16（bank BMG 定宽守卫）
)(
    input  wire               clk_i,
    input  wire               rst_i,        //同步复位（RAM 内容不清）
    // ---- 64b 流式装载写口（PS/DMA 侧）----
    input  wire               wr_valid_i,
    output wire               wr_ready_o,
    input  wire        [63:0] wr_data_i,
    input  wire               wr_is_x_i,
    input  wire               wr_x_hi_i,
    input  wire        [7:0]  wr_be_i,
    input  wire               wr_first_i,
    input  wire               wr_last_i,
    input  wire               ld_w_grp_i,
    input  wire               ld_x_grp_i,
    // ---- 装载状态 ----
    output wire        [1:0]  w_ld_ok_o,
    output wire        [1:0]  x_ld_ok_o,
    output wire        [1:0]  w_loaded_o,
    output wire        [1:0]  x_loaded_o,
    output wire        [12:0] ld_w_len_o,
    output wire        [12:0] ld_x_len_o,
    output wire               ld_done_o,
    output wire               bank_err_o,
    // ---- feeder 作业口（调度方）----
    input  wire               job_valid_i,
    output wire               job_ready_o,
    input  wire        [12:0] job_len_i,
    input  wire               job_first_i,
    input  wire               job_last_i,
    input  wire               job_w_grp_i,
    input  wire               job_x_grp_i,
    // ---- 阵列 tile 常量/参数/LUT ----
    input  wire [P_TO-1:0]    row_valid_i,
    input  wire [P_TN-1:0]    n_mask_i,
    input  wire               act_en_i,
    input  wire               p_we_i,
    input  wire [$clog2(P_TO)-1:0] p_row_i,
    input  wire signed [31:0] p_bias_i,
    input  wire signed [31:0] p_m_i,
    input  wire        [5:0]  p_sh_i,
    input  wire               lut_we_i,
    input  wire        [7:0]  lut_wa_i,
    input  wire        [7:0]  lut_wd_i,
    // ---- 结果/状态 ----
    output wire               blk_done_o,
    output wire               tile_done_o,
    output wire               busy_o,
    output wire               proto_err_o,
    output wire               y_valid_o,
    output wire signed [7:0]  y_o,
    output wire [$clog2(P_TO)-1:0] y_row_o,
    output wire [$clog2(P_TN)-1:0] y_col_o
);

    // ---- feeder↔bank 真线 ----
    wire        w_rgrp, w_ren, x_rgrp, x_ren;
    wire [12:0] w_raddr, x_raddr;
    wire [8*P_TO-1:0] w_dg0, w_dg1;
    wire [8*P_TN-1:0] x_dg0, x_dg1;
    wire        rd_busy;

    // ---- feeder→阵列块头+宽字流 ----
    wire        blk_valid_w;
    wire [12:0] blk_len_w;
    wire        blk_first_w, blk_last_w;
    wire [8*P_TO-1:0] w_word_w;
    wire [8*P_TN-1:0] x_word_w;
    wire        word_valid_w, word_first_w, word_last_w, word_ready_w;

    yolo_gemm_bank u_bank (
        .clk_i(clk_i), .rst_i(rst_i),
        .wr_valid_i(wr_valid_i), .wr_ready_o(wr_ready_o),
        .wr_data_i(wr_data_i),
        .wr_is_x_i(wr_is_x_i), .wr_x_hi_i(wr_x_hi_i), .wr_be_i(wr_be_i),
        .wr_first_i(wr_first_i), .wr_last_i(wr_last_i),
        .ld_w_grp_i(ld_w_grp_i), .ld_x_grp_i(ld_x_grp_i), .rd_busy_i(rd_busy),
        .w_ld_ok_o(w_ld_ok_o), .x_ld_ok_o(x_ld_ok_o),
        .w_loaded_o(w_loaded_o), .x_loaded_o(x_loaded_o),
        .ld_w_len_o(ld_w_len_o), .ld_x_len_o(ld_x_len_o), .ld_done_o(ld_done_o),
        .w_rgrp_i(w_rgrp), .w_raddr_i(w_raddr), .w_ren_i(w_ren),
        .w_dout_g0_o(w_dg0), .w_dout_g1_o(w_dg1),
        .x_rgrp_i(x_rgrp), .x_raddr_i(x_raddr), .x_ren_i(x_ren),
        .x_dout_g0_o(x_dg0), .x_dout_g1_o(x_dg1),
        .bank_err_o(bank_err_o)
    );

    yolo_gemm_feeder #(.P_TO(P_TO), .P_TN(P_TN)) u_feeder (
        .clk_i(clk_i), .rst_i(rst_i),
        .job_valid_i(job_valid_i), .job_ready_o(job_ready_o),
        .job_len_i(job_len_i), .job_first_i(job_first_i), .job_last_i(job_last_i),
        .job_w_grp_i(job_w_grp_i), .job_x_grp_i(job_x_grp_i),
        .w_rgrp_o(w_rgrp), .w_raddr_o(w_raddr), .w_ren_o(w_ren),
        .w_dout_g0_i(w_dg0), .w_dout_g1_i(w_dg1),
        .x_rgrp_o(x_rgrp), .x_raddr_o(x_raddr), .x_ren_o(x_ren),
        .x_dout_g0_i(x_dg0), .x_dout_g1_i(x_dg1),
        .w_grp_ld_i(w_loaded_o), .x_grp_ld_i(x_loaded_o),
        .rd_busy_o(rd_busy),
        .blk_valid_o(blk_valid_w), .blk_len_o(blk_len_w),
        .blk_first_o(blk_first_w), .blk_last_o(blk_last_w),
        .w_word_o(w_word_w), .x_word_o(x_word_w),
        .word_valid_o(word_valid_w), .word_first_o(word_first_w),
        .word_last_o(word_last_w), .word_ready_i(word_ready_w)
    );

    yolo_gemm_array #(.P_TO(P_TO), .P_TN(P_TN)) u_array (
        .clk_i(clk_i), .rst_i(rst_i),
        .blk_valid_i(blk_valid_w), .blk_len_i(blk_len_w),
        .blk_first_i(blk_first_w), .blk_last_i(blk_last_w),
        .row_valid_i(row_valid_i), .n_mask_i(n_mask_i), .act_en_i(act_en_i),
        .w_word_i(w_word_w), .x_word_i(x_word_w),
        .word_valid_i(word_valid_w), .word_first_i(word_first_w),
        .word_last_i(word_last_w), .word_ready_o(word_ready_w),
        .p_we_i(p_we_i), .p_row_i(p_row_i),
        .p_bias_i(p_bias_i), .p_m_i(p_m_i), .p_sh_i(p_sh_i),
        .lut_we_i(lut_we_i), .lut_wa_i(lut_wa_i), .lut_wd_i(lut_wd_i),
        .blk_done_o(blk_done_o), .tile_done_o(tile_done_o), .busy_o(busy_o),
        .proto_err_o(proto_err_o),
        .y_valid_o(y_valid_o), .y_o(y_o),
        .y_row_o(y_row_o), .y_col_o(y_col_o)
    );

endmodule
