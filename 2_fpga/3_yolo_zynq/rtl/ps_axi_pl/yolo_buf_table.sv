/************************************************************************
 * File Name       : yolo_buf_table.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_buf_table
 * Description     : Buffer table: 128 items x 8 words = 1024 x 32 BRAM,
 *                   implemented with a Block Memory Generator IP
 *                   (yolo_buf_bram, true dual port, byte write enable,
 *                   output registers DISABLED -> read latency 1 cycle).
 *                   Port A = AXI aperture, port B unused.
 * Dependencies    : ip/yolo_buf_bram (BMG v8.4 XCI)
 * Revision History:
 *   - V1.1 (2026-09-18) by LSL : Coding-standards refactor: EES-331
 *                                header, _i/_o port suffixes.
 *   - V1.0 (2026-09-18) by LSL : Initial release
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_buf_table (
    input  wire        clk_i     ,
    // port A: AXI aperture, write & read time-shared
    input  wire        a_we_i    ,
    input  wire [3:0]  a_wstrb_i ,
    input  wire [9:0]  a_waddr_i ,
    input  wire [31:0] a_wdata_i ,
    input  wire [9:0]  a_raddr_i ,
    output wire [31:0] a_rdata_o    // 1-cycle latency
);

    yolo_buf_bram u_bram (
        .clka (clk_i),
        .ena  (1'b1),
        .wea  (a_we_i ? a_wstrb_i : 4'h0),
        .addra(a_we_i ? a_waddr_i : a_raddr_i),
        .dina (a_wdata_i),
        .douta(a_rdata_o),
        .clkb (clk_i),
        .enb  (1'b0),
        .web  (4'h0),
        .addrb(10'h0),
        .dinb (32'h0),
        .doutb()
    );

endmodule
