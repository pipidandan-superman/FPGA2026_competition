/************************************************************************
 * File Name       : yolo_xbuf.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_xbuf
 * Description     : M4 X-tile double-buffered column store (architecture
 *                   baseline section 3.3): N_COLS (=N_EDGE) independent
 *                   K-deep byte memories per bank, column organization
 *                   mirroring yolo_wbuf's row organization. Read side
 *                   broadcasts one byte per column at a shared k address
 *                   every cycle (the array's X column broadcast) to pair
 *                   with the W row broadcast in the multiply wall.
 *
 *                   Double buffering: writes target wr_bank_i (the
 *                   inactive bank during a tile), reads follow rd_bank_i
 *                   (ctrl switches it at tile boundaries) -- concurrent
 *                   write/read on opposite banks must not interact.
 *
 *                   No parameters ride with the tile (requant params
 *                   belong to W rows only). Unwritten addresses read
 *                   as x; stimulus must not read them.
 *
 *                   Write:  we_i 1 cycle 1 byte -> mem[wcol][waddr]
 *                   Read:   ren_i/raddr_i 1-cycle synchronous broadcast;
 *                   dout_vld_o = ren_i delayed; en=0 holds outputs.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M4).
 ************************************************************************/

module yolo_xbuf #(
    parameter N_COLS = 16,                  // N_EDGE columns
    parameter K_MAX  = 2304,                // deepest K tier
    parameter AW     = 12,                  // ceil(log2 2304)
    parameter COL_AW = 5                    // ceil(log2 N_COLS)
) (
    input  wire              clk_i,
    input  wire              rst_n,
    // DMA write side (targets the inactive bank)
    input  wire              we_i,
    input  wire              wr_bank_i,
    input  wire [COL_AW-1:0] wcol_i,
    input  wire [AW-1:0]     waddr_i,       // k index
    input  wire [7:0]        wdata_i,
    // array read side (active bank)
    input  wire              rd_bank_i,
    input  wire              ren_i,
    input  wire [AW-1:0]     raddr_i,       // k index
    output reg  [N_COLS*8-1:0] dout_o,      // one byte per column
    output reg               dout_vld_o
);

    // ---- per-column byte memories (parallel read = column broadcast) ----
    genvar col;
    generate
        for (col = 0; col < N_COLS; col = col + 1) begin : g_col
            reg [7:0] mem0 [0:K_MAX-1];
            reg [7:0] mem1 [0:K_MAX-1];

            always @(posedge clk_i) begin
                if (we_i && wcol_i == col[COL_AW-1:0]) begin
                    if (wr_bank_i == 1'b0) begin
                        mem0[waddr_i] <= wdata_i;
                    end else begin
                        mem1[waddr_i] <= wdata_i;
                    end
                end
            end

            always @(posedge clk_i or negedge rst_n) begin
                if (!rst_n) begin
                    dout_o[col*8 +: 8] <= 8'd0;
                end else if (ren_i) begin
                    if (rd_bank_i == 1'b0) begin
                        dout_o[col*8 +: 8] <= mem0[raddr_i];
                    end else begin
                        dout_o[col*8 +: 8] <= mem1[raddr_i];
                    end
                end
            end
        end
    endgenerate

    // read valid: ren_i delayed 1 cycle (hold semantics via output regs)
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            dout_vld_o <= 1'b0;
        end else begin
            dout_vld_o <= ren_i;
        end
    end

endmodule
