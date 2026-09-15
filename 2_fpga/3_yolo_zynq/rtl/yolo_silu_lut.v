/************************************************************************
 * File Name       : yolo_silu_lut.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_silu_lut
 * Description     : M6 activation LUT for the GEMM PE array tail
 *                   (architecture baseline section 3.2 numeric contract):
 *                     y = LUT[(y_pre + 128) & 0xFF]   when act_i = 1
 *                     y = y_pre                        when act_i = 0
 *                   The 256-entry int8 table is per-layer shared by all
 *                   output channels (real model lut shape [256]); it is
 *                   reloaded at layer switch through the write port.
 *
 *                   Index fold: (y_pre + 128) & 0xFF is the natural
 *                   8-bit wrap of the unsigned add (0x80 + 0x80 -> 0x00,
 *                   0x7F + 0x80 -> 0xFF), so no sign handling is needed.
 *
 *                   Timing: synchronous write (we_i); 1-cycle registered
 *                   read with en_i hold (en_i=0 holds y_o). Write and
 *                   read ports are never expected active in the same
 *                   cycle by the array scheduler (load phase is
 *                   exclusive); read-during-write same-address returns
 *                   the OLD entry (write-last in this RTL).
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M6).
 ************************************************************************/

module yolo_silu_lut #(
    parameter DW = 8,                        // entry / y_pre width
    parameter AW = 8                         // 256 entries
) (
    input  wire              clk_i,
    input  wire              rst_n,
    input  wire              we_i,           // table write strobe
    input  wire [AW-1:0]     waddr_i,        // table write index
    input  wire [DW-1:0]     wdata_i,        // table entry (int8 bits)
    input  wire              en_i,           // 0 = hold y_o
    input  wire              act_i,          // 1 = LUT, 0 = bypass
    input  wire signed [DW-1:0] y_pre_i,     // requant output
    output reg  [DW-1:0]     y_o,            // activation output (int8 bits)
    output reg               vld_o
);

    localparam N_ENT  = 1 << AW;
    localparam ZP_OFF = 8'h80;               // zero-point fold +128

    reg [DW-1:0] lut [0:N_ENT-1];
    integer e;

    wire [AW-1:0] zp_off = ZP_OFF;           // 参数不可位选，经 wire 中转
    wire [AW-1:0] ridx   = y_pre_i[DW-1:0] + zp_off;

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            y_o   <= {DW{1'b0}};
            vld_o <= 1'b0;
            for (e = 0; e < N_ENT; e = e + 1) begin
                lut[e] <= {DW{1'b0}};
            end
        end else begin
            vld_o <= en_i;
            if (we_i) begin
                lut[waddr_i] <= wdata_i;
            end
            if (en_i) begin
                if (act_i) begin
                    y_o <= lut[ridx];
                end else begin
                    y_o <= y_pre_i[DW-1:0];
                end
            end
        end
    end

endmodule
