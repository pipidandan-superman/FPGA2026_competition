/************************************************************************
 * File Name       : oddr_sim_model.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : oddr_sim_model
 * Description     : Local simulation-only ODDR behavior used when Xilinx
 *                   UNISIM libraries are unavailable to ModelSim.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

module ODDR #(
    parameter string DDR_CLK_EDGE = "SAME_EDGE",
    parameter logic       INIT    = 1'b0       ,
    parameter string SRTYPE      = "SYNC"
) (
    input  wire C ,
    input  wire CE,
    input  wire D1,
    input  wire D2,
    input  wire R ,
    input  wire S ,
    output reg  Q
);

    initial begin
        Q = INIT;
    end

    always @(posedge C or posedge R) begin
        if (R == 1'b1) begin
            Q <= 1'b0;
        end else if (CE == 1'b1) begin
            Q <= D1;
        end
    end

    always @(negedge C) begin
        if ((R == 1'b0) && (CE == 1'b1)) begin
            Q <= D2;
        end
    end

endmodule
