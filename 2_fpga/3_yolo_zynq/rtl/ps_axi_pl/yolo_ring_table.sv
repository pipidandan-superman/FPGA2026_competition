/************************************************************************
 * File Name       : yolo_ring_table.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ring_table
 * Description     : Result metadata ring storage: 32 items x 16 words
 *                   = 512 x 32 BRAM, implemented with a Block Memory
 *                   Generator IP (yolo_ring_bram, true dual port, byte
 *                   write enable, output registers DISABLED -> read
 *                   latency 1 cycle).  Port A = AXI aperture (PS read
 *                   only), port B = ring publisher write port.
 * Dependencies    : ip/yolo_ring_bram (BMG v8.4 XCI)
 * Revision History:
 *   - V1.1 (2026-09-18) by LSL : Coding-standards refactor: EES-331
 *                                header, _i/_o port suffixes.
 *   - V1.0 (2026-09-18) by LSL : Initial release
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_ring_table (
    input  wire        clk_i     ,
    // port A: AXI aperture, read only
    input  wire [8:0]  a_raddr_i ,
    output wire [31:0] a_rdata_o ,  // 1-cycle latency
    // port B: publisher write only
    input  wire        b_we_i    ,
    input  wire [3:0]  b_wstrb_i ,
    input  wire [8:0]  b_waddr_i ,
    input  wire [31:0] b_wdata_i
);

    yolo_ring_bram u_bram (
        .clka (clk_i),
        .ena  (1'b1),
        .wea  (4'h0),
        .addra(a_raddr_i),
        .dina (32'h0),
        .douta(a_rdata_o),
        .clkb (clk_i),
        .enb  (1'b1),
        .web  (b_we_i ? b_wstrb_i : 4'h0),
        .addrb(b_waddr_i),
        .dinb (b_wdata_i),
        .doutb()
    );

endmodule
