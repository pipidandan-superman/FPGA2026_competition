/************************************************************************
 * File Name       : yolo_addrgen.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_addrgen
 * Description     : M7 im2col address generator for the X-tile fill
 *                   path (architecture baseline sections 3.1/3.5).
 *                   Walks one N_EDGE-wide output tile of the im2col
 *                   matrix: n (tile-local column) outer, k inner,
 *                   one beat per cycle:
 *                     k   = ic*(KH*KW) + kh*KW + kw   (K-order contract,
 *                           same decomposition as yolo_conv_core V1.1)
 *                     ih  = oy*SH + kh - PH ;  iw = ox*SW + kw - PW
 *                     pad = !(0<=ih<IH && 0<=iw<IW)
 *                     x_addr = ic*(IH*IW) + ih*IW + iw   (X plane CHW)
 *                   Pad beats bypass memory and supply the zero-point
 *                   fold constant instead (first layer -128, later
 *                   layers 0) -- baseline 3.5 first-layer z-fold.
 *
 *                   Geometry is sampled at the start_i pulse into
 *                   internal registers (descriptor semantics for M8).
 *                   Tail tiles: n_len_i is programmed pre-clamped by
 *                   the controller (addrgen trusts it).
 *                   Plane size contract: IC*IH*IW < 2^31, N < 2^16.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M7).
 ************************************************************************/

module yolo_addrgen #(
    parameter AW = 32                       // X plane byte address width
) (
    input  wire          clk_i,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [15:0]   ih_i,              // input height
    input  wire [15:0]   iw_i,              // input width
    input  wire [15:0]   ow_i,              // output width (n -> oy/ox)
    input  wire [15:0]   ic_i,              // input channels (K2304 -> 256)
    input  wire [7:0]    kh_i,              // kernel height
    input  wire [7:0]    kw_i,              // kernel width
    input  wire [7:0]    sh_i,              // stride h
    input  wire [7:0]    sw_i,              // stride w
    input  wire [7:0]    ph_i,              // pad h
    input  wire [7:0]    pw_i,              // pad w
    input  wire [15:0]   k_len_i,           // K = IC*KH*KW
    input  wire [15:0]   n_start_i,         // tile first output index
    input  wire [15:0]   n_len_i,           // tile width (pre-clamped)
    input  wire          first_i,           // 1: pad=-128 (z fold), 0: pad=0
    output wire          busy_o,
    output reg           done_o,            // 1-cycle pulse with last beat done
    output wire          vld_o,             // 1 beat/cycle while running
    output wire [AW-1:0] x_addr_o,          // X plane byte address (CHW)
    output wire          pad_o,             // 1 = pad beat (bypass memory)
    output wire [7:0]    pad_val_o,         // -128 (first) or 0
    output wire [15:0]   k_o,               // K index (column BRAM depth)
    output wire [15:0]   n_o                // tile-local column index
);

    localparam S_IDLE = 1'b0;
    localparam S_RUN  = 1'b1;
    localparam COORD_W = 18;               // signed window coordinate width

    reg               state;
    reg [15:0]        n_loc;
    reg [15:0]        oy_r;
    reg [15:0]        ox_r;
    reg [15:0]        k_cnt;
    reg [15:0]        ic_r;
    reg [7:0]         kh_r;
    reg [7:0]         kw_r;
    // captured geometry
    reg [15:0]        ih_c;
    reg [15:0]        iw_c;
    reg [15:0]        ow_c;
    reg [7:0]         kw_kh_c;             // KH*KW
    reg [7:0]         sh_c;
    reg [7:0]         sw_c;
    reg [7:0]         ph_c;
    reg [7:0]         pw_c;
    reg [7:0]         kh_c;
    reg [7:0]         kw_c;
    reg [15:0]        k_len_c;
    reg [15:0]        n_len_c;
    reg               first_c;

    // ---- per-beat window decode (counters -> coordinates/address) ----
    // Unsigned arithmetic wraps modulo the reg width; the bit pattern is
    // the true two's-complement value, so the signed comparisons below
    // behave exactly (M0 mixed-sign discipline; in-bounds addr terms are
    // all non-negative so the unsigned address add is exact).
    reg signed [COORD_W-1:0] ih;
    reg signed [COORD_W-1:0] iw;

    always @(*) begin
        ih = oy_r * sh_c + kh_r - ph_c;
        iw = ox_r * sw_c + kw_r - pw_c;
    end

    wire in_b = (ih >= 0) && (ih < ih_c) && (iw >= 0) && (iw < iw_c);

    wire [AW-1:0] plane_sz = ih_c * iw_c;
    wire [AW-1:0] x_addr_w = ic_r * plane_sz + ih * iw_c + iw;

    assign busy_o    = (state == S_RUN);
    assign vld_o     = (state == S_RUN);
    assign x_addr_o  = in_b ? x_addr_w : {AW{1'b0}};
    assign pad_o     = ~in_b;
    assign pad_val_o = first_c ? 8'h80 : 8'h00;
    assign k_o       = k_cnt;
    assign n_o       = n_loc;

    wire last_k = (k_cnt == k_len_c - 16'd1);
    wire last_n = (n_loc == n_len_c - 16'd1);

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            done_o  <= 1'b0;
            n_loc   <= 16'd0;
            oy_r    <= 16'd0;
            ox_r    <= 16'd0;
            k_cnt   <= 16'd0;
            ic_r    <= 16'd0;
            kh_r    <= 8'd0;
            kw_r    <= 8'd0;
            ih_c    <= 16'd0;
            iw_c    <= 16'd0;
            ow_c    <= 16'd0;
            kw_kh_c <= 8'd0;
            sh_c    <= 8'd0;
            sw_c    <= 8'd0;
            ph_c    <= 8'd0;
            pw_c    <= 8'd0;
            kh_c    <= 8'd0;
            kw_c    <= 8'd0;
            k_len_c <= 16'd0;
            n_len_c <= 16'd0;
            first_c <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (state == S_IDLE) begin
                if (start_i) begin
                    // descriptor capture (geometry sampled once)
                    ih_c    <= ih_i;
                    iw_c    <= iw_i;
                    ow_c    <= ow_i;
                    kh_c    <= kh_i;
                    kw_c    <= kw_i;
                    sh_c    <= sh_i;
                    sw_c    <= sw_i;
                    ph_c    <= ph_i;
                    pw_c    <= pw_i;
                    k_len_c <= k_len_i;
                    n_len_c <= n_len_i;
                    first_c <= first_i;
                    oy_r    <= n_start_i / ow_i;
                    ox_r    <= n_start_i % ow_i;
                    n_loc   <= 16'd0;
                    k_cnt   <= 16'd0;
                    ic_r    <= 16'd0;
                    kh_r    <= 8'd0;
                    kw_r    <= 8'd0;
                    state   <= S_RUN;
                end
            end else begin
                if (last_k) begin
                    k_cnt <= 16'd0;
                    ic_r  <= 16'd0;
                    kh_r  <= 8'd0;
                    kw_r  <= 8'd0;
                    if (last_n) begin
                        state  <= S_IDLE;
                        done_o <= 1'b1;
                    end else begin
                        n_loc <= n_loc + 16'd1;
                        if (ox_r == ow_c - 16'd1) begin
                            ox_r <= 16'd0;
                            oy_r <= oy_r + 16'd1;
                        end else begin
                            ox_r <= ox_r + 16'd1;
                        end
                    end
                end else begin
                    k_cnt <= k_cnt + 16'd1;
                    if (kw_r == kw_c - 8'd1) begin
                        kw_r <= 8'd0;
                        if (kh_r == kh_c - 8'd1) begin
                            kh_r <= 8'd0;
                            ic_r <= ic_r + 16'd1;
                        end else begin
                            kh_r <= kh_r + 8'd1;
                        end
                    end else begin
                        kw_r <= kw_r + 8'd1;
                    end
                end
            end
        end
    end

endmodule
