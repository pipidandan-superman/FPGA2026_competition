//====================================================================
// File name   : vtc_480p_1ppc.v
// Author      : LSL
// Create date : 2026-09-04
// Description : 640x480@60 video timing controller, one pixel/clk
// Target      : Xilinx 7-series
// Revision    : V1.0
//====================================================================

module vtc_480p_1ppc (
    input  wire        clk_i       ,
    input  wire        rst_n_i     ,
    output wire        active_o    ,
    output wire        hsync_o     ,
    output wire        vsync_o     ,
    output wire [ 9:0] pixel_x_o   ,
    output wire [ 9:0] pixel_y_o
);

    localparam [9:0] H_VISIBLE = 10'd640;
    localparam [9:0] H_FRONT   = 10'd16 ;
    localparam [9:0] H_SYNC    = 10'd96 ;
    localparam [9:0] H_BACK    = 10'd48 ;
    localparam [9:0] H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;

    localparam [9:0] V_VISIBLE = 10'd480;
    localparam [9:0] V_FRONT   = 10'd10 ;
    localparam [9:0] V_SYNC    = 10'd2  ;
    localparam [9:0] V_BACK    = 10'd33 ;
    localparam [9:0] V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    reg [9:0] h_count;
    reg [9:0] v_count;

    wire h_active = (h_count < H_VISIBLE);
    wire v_active = (v_count < V_VISIBLE);
    wire hsync    = (h_count >= (H_VISIBLE + H_FRONT)) &&
                    (h_count <  (H_VISIBLE + H_FRONT + H_SYNC));
    wire vsync    = (v_count >= (V_VISIBLE + V_FRONT)) &&
                    (v_count <  (V_VISIBLE + V_FRONT + V_SYNC));

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            h_count  <= 10'd0;
            v_count  <= 10'd0;
        end else begin
            if (h_count == (H_TOTAL - 10'd1)) begin
                h_count <= 10'd0;
                if (v_count == (V_TOTAL - 10'd1)) begin
                    v_count <= 10'd0;
                end else begin
                    v_count <= v_count + 10'd1;
                end
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    assign active_o = h_active & v_active;
    assign hsync_o  = ~hsync;
    assign vsync_o  = ~vsync;
    assign pixel_x_o = h_count;
    assign pixel_y_o = v_count;

endmodule
