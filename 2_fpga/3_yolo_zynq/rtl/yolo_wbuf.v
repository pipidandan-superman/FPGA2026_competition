/************************************************************************
 * File Name       : yolo_wbuf.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_wbuf
 * Description     : M3 W-tile double-buffered row store (architecture
 *                   baseline section 3.3): N_ROWS (=OC_EDGE) independent
 *                   K-deep byte memories per bank, plus per-row requant
 *                   parameters (bias_eff / m / shift) loaded with the
 *                   tile. Read side broadcasts one byte per row at a
 *                   shared k address every cycle (the array's W row
 *                   broadcast); parameters are read out sequentially by
 *                   the requant tail (single reader, flat memories).
 *
 *                   Double buffering: writes target wr_bank_i (the
 *                   inactive bank during a tile), reads follow rd_bank_i
 *                   (ctrl switches it at tile boundaries) -- concurrent
 *                   write/read on opposite banks must not interact.
 *
 *                   Write decode (we_i):
 *                     wr_sel 00: data byte  mem[row][waddr] <= wdata[7:0]
 *                     wr_sel 01: bias_eff   par_b[bank][row] <= wdata (i32)
 *                     wr_sel 10: m          par_m[bank][row] <= wdata (i32)
 *                     wr_sel 11: shift      par_s[bank][row] <= wdata[7:0]
 *                   Read: 1-cycle synchronous; dout_vld_o = ren_i delayed;
 *                   param read 1-cycle, psel selects the field.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M3).
 ************************************************************************/

module yolo_wbuf #(
    parameter N_ROWS = 16,                  // OC_EDGE rows
    parameter K_MAX  = 2304,                // deepest K tier
    parameter AW     = 12,                  // ceil(log2 2304)
    parameter ROW_AW = 5                    // ceil(log2 N_ROWS)
) (
    input  wire              clk_i,
    input  wire              rst_n,
    // DMA write side (targets the inactive bank)
    input  wire              we_i,
    input  wire              wr_bank_i,
    input  wire [1:0]        wr_sel_i,
    input  wire [ROW_AW-1:0] wrow_i,
    input  wire [AW-1:0]     waddr_i,       // k index (data writes)
    input  wire [31:0]       wdata_i,
    // array read side (active bank)
    input  wire              rd_bank_i,
    input  wire              ren_i,
    input  wire [AW-1:0]     raddr_i,       // k index
    output reg  [N_ROWS*8-1:0] dout_o,      // one byte per row
    output reg               dout_vld_o,
    // requant-tail parameter read (active bank)
    input  wire              pren_i,
    input  wire [1:0]        psel_i,        // 01 bias / 10 m / 11 shift
    input  wire [ROW_AW-1:0] prow_i,
    output reg  [31:0]       pdata_o,
    output reg               pdata_vld_o
);

    localparam SEL_DATA  = 2'd0;
    localparam SEL_BIAS  = 2'd1;
    localparam SEL_M     = 2'd2;
    localparam SEL_SHIFT = 2'd3;

    // ---- per-row byte memories (parallel read = row broadcast) ----
    genvar r;
    generate
        for (r = 0; r < N_ROWS; r = r + 1) begin : g_row
            reg [7:0] mem0 [0:K_MAX-1];
            reg [7:0] mem1 [0:K_MAX-1];

            always @(posedge clk_i) begin
                if (we_i && wr_sel_i == SEL_DATA && wrow_i == r[ROW_AW-1:0]) begin
                    if (wr_bank_i == 1'b0) begin
                        mem0[waddr_i] <= wdata_i[7:0];
                    end else begin
                        mem1[waddr_i] <= wdata_i[7:0];
                    end
                end
            end

            always @(posedge clk_i or negedge rst_n) begin
                if (!rst_n) begin
                    dout_o[r*8 +: 8] <= 8'd0;
                end else if (ren_i) begin
                    if (rd_bank_i == 1'b0) begin
                        dout_o[r*8 +: 8] <= mem0[raddr_i];
                    end else begin
                        dout_o[r*8 +: 8] <= mem1[raddr_i];
                    end
                end
            end
        end
    endgenerate

    // ---- per-row requant parameters (flat memories, single reader) ----
    reg [31:0] par_b0 [0:N_ROWS-1];
    reg [31:0] par_b1 [0:N_ROWS-1];
    reg [31:0] par_m0 [0:N_ROWS-1];
    reg [31:0] par_m1 [0:N_ROWS-1];
    reg [7:0]  par_s0 [0:N_ROWS-1];
    reg [7:0]  par_s1 [0:N_ROWS-1];

    always @(posedge clk_i) begin
        if (we_i && wr_sel_i != SEL_DATA) begin
            if (wr_bank_i == 1'b0) begin
                if (wr_sel_i == SEL_BIAS) begin
                    par_b0[wrow_i] <= wdata_i;
                end else if (wr_sel_i == SEL_M) begin
                    par_m0[wrow_i] <= wdata_i;
                end else if (wr_sel_i == SEL_SHIFT) begin
                    par_s0[wrow_i] <= wdata_i[7:0];
                end
            end else begin
                if (wr_sel_i == SEL_BIAS) begin
                    par_b1[wrow_i] <= wdata_i;
                end else if (wr_sel_i == SEL_M) begin
                    par_m1[wrow_i] <= wdata_i;
                end else if (wr_sel_i == SEL_SHIFT) begin
                    par_s1[wrow_i] <= wdata_i[7:0];
                end
            end
        end
    end

    // param read: (row, field) sampled at pren_i, 1-cycle registered
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            dout_vld_o  <= 1'b0;
            pdata_o     <= 32'd0;
            pdata_vld_o <= 1'b0;
        end else begin
            dout_vld_o <= ren_i;
            if (pren_i) begin
                pdata_vld_o <= 1'b1;
                if (psel_i == SEL_BIAS) begin
                    if (rd_bank_i == 1'b0) begin
                        pdata_o <= par_b0[prow_i];
                    end else begin
                        pdata_o <= par_b1[prow_i];
                    end
                end else if (psel_i == SEL_M) begin
                    if (rd_bank_i == 1'b0) begin
                        pdata_o <= par_m0[prow_i];
                    end else begin
                        pdata_o <= par_m1[prow_i];
                    end
                end else if (psel_i == SEL_SHIFT) begin
                    if (rd_bank_i == 1'b0) begin
                        pdata_o <= {24'd0, par_s0[prow_i]};
                    end else begin
                        pdata_o <= {24'd0, par_s1[prow_i]};
                    end
                end else begin
                    pdata_o <= 32'd0;
                end
            end else begin
                pdata_vld_o <= 1'b0;
            end
        end
    end

endmodule
