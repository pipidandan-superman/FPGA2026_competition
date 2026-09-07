`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/05 14:52:54
// Design Name: 
// Module Name: data_gen
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module data_gen(
    input [23:0]  data_i        ,
    input         de            ,
    output [7:0]  data_r_o     ,
    output [7:0]  data_g_o     ,
    output [7:0]  data_b_o     
    );
// G_B_R -> RGB 转换
// DDR中存储的是G_B_R格式: data_i[23:16]=G, [15:8]=B, [7:0]=R
// HDMI期望RGB格式输出
assign data_r_o = (de) ? data_i[23:16]   : 'd0;  // R <- �?8�?
assign data_g_o = (de) ? data_i[15:8]    : 'd0;  // G <- �?8�?
assign data_b_o = (de) ? data_i[7:0]     : 'd0;  // B <- �?8�?
endmodule
