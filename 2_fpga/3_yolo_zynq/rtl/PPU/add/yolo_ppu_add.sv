/************************************************************************
 * File Name       : yolo_ppu_add.sv
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ppu_add
 * Description     : PPU add engine core (PPU manual section 5.3):
 *                   dual-lane requant (NO per-lane saturation -- A,B stay
 *                   int64, manual 2.2) then ONE int64 sum, int32 contract
 *                   clip, single sat_i8.
 *
 *   Contract (manual 2.2, verbatim add): A=rne_shift(a_q*Ma,sa),
 *     B=rne_shift(b_q*Mb,sb) (int64); out=sat_i8(sat_i32(A+B)).
 *     The int32 clip is contract order only (real ratio domain never
 *     reaches it) but is implemented LITERALLY; the P2d gate constructs
 *     small-s vectors that do reach it (anti-degenerate discipline).
 *
 *   Core contract: both input lanes advance in the SAME linear order;
 *     the join accepts a beat only when BOTH lanes present valid data
 *     in the same cycle (ready never depends combinationally on the
 *     other lane's valid -- upstream FIFOs absorb read desync at P3).
 *     Profiles are PER TASK (latched at start); shapes asserted equal
 *     at descriptor-load time (P3 concern), core takes element count N.
 *
 *   Pipeline mirrors yolo_ppu_requant: accept/join -> S1 capture ->
 *     S2 both products (int64) -> S3 both RNE + sum + clip + sat.
 *     D+3; bubbles when a lane stalls; out_last pulses with beat N-1.
 *     RNE same wires as GEMM tail (shift+mask, ties-to-even incl.
 *     negatives); s=0 lane bypass; M=0 lane yields A=0 (dead channel
 *     retained by contract).
 * Dependencies    : None (pure fabric).
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : Initial release (P2d).
 ************************************************************************/

module yolo_ppu_add (
    input  wire        clk_i,      //运算时钟
    input  wire        rst_i,      //同步复位，高有效（回 ST_IDLE，清脉冲）
    // ---- task start（ST_IDLE 时采样）----
    input  wire        start_i,    //启动脉冲
    input  wire [31:0] n_i,        //元素数 N（a/b/out 同形）
    input  wire [31:0] ma_i,       //lane A profile：M
    input  wire [5:0]  sa_i,       //lane A profile：shift
    input  wire [31:0] mb_i,       //lane B profile：M
    input  wire [5:0]  sb_i,       //lane B profile：shift
    // ---- lane A 输入字节流 ----
    output wire        a_ready_o,
    input  wire        a_valid_i,
    input  wire [7:0]  a_data_i,
    // ---- lane B 输入字节流 ----
    output wire        b_ready_o,
    input  wire        b_valid_i,
    input  wire [7:0]  b_data_i,
    // ---- 输出字节流 ----
    output reg         y_valid_o,
    output reg  [7:0]  y_o,
    output reg         y_last_o,   //末字节同拍脉冲
    output wire        busy_o
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;

    reg [1:0]  state_r;
    reg [31:0] n_r, cnt_r;            //元素计数
    reg [31:0] ma_r, mb_r;            //任务级 profile
    reg [5:0]  sa_r, sb_r;
    reg [1:0]  drain_r;               //末拍接收后的排空计数

    reg        v1_r, v2_r;            //流水有效链（含气泡）
    reg        l1_r, l2_r;            //末元素标志链
    reg [7:0]  x1a_r, x1b_r;          //S1 捕获
    reg signed [63:0] pa_r, pb_r;     //S2 乘积（int64）

    wire run_w    = (state_r == ST_RUN);
    wire aacc_w   = run_w && (cnt_r != n_r);
    wire accept_w = aacc_w && a_valid_i && b_valid_i;   //双流会合

    assign a_ready_o = aacc_w;        //ready 不组合依赖对侧 valid
    assign b_ready_o = aacc_w;
    assign busy_o    = (state_r != ST_IDLE);

    // ---- S3：双路 RNE（不饱和）+ int64 求和 + int32 合同截断 + sat_i8 ----
    function signed [63:0] rne64(input signed [63:0] prod,
                                 input [5:0] sh);
        reg signed [63:0] q;
        reg [63:0] rem, half;
        begin
            if (sh == 6'd0) begin
                rne64 = prod;                       //s=0 旁路直通
            end else begin
                q     = prod >>> sh;                //floor（算术移位）
                rem   = prod & ((64'd1 << sh) - 64'd1);  //∈[0,2^s)
                half  = 64'd1 << (sh - 6'd1);
                rne64 = q + (((rem > half) ||
                              (rem == half && q[0])) ? 64'sd1 : 64'sd0);
            end
        end
    endfunction

    wire signed [63:0] a3_w = rne64(pa_r, sa_r);
    wire signed [63:0] b3_w = rne64(pb_r, sb_r);
    wire signed [63:0] sum_w = a3_w + b3_w;         //int64 求和一次
    //int32 合同截断（字面实现；真实比率域不触界）
    wire signed [63:0] clip_w =
        (sum_w > 64'sd2147483647)   ? 64'sd2147483647 :
        (sum_w < -64'sd2147483648)  ? -64'sd2147483648 : sum_w;
    //sat_i8 一次
    wire [7:0] y3_w =
        (clip_w > 64'sd127)   ? 8'd127 :
        (clip_w < -64'sd128)  ? 8'h80 : clip_w[7:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r    <= ST_IDLE;
            v1_r       <= 1'b0;
            v2_r       <= 1'b0;
            y_valid_o  <= 1'b0;
            y_last_o   <= 1'b0;
        end else begin
            //默认单拍脉冲
            y_valid_o <= 1'b0;
            y_last_o  <= 1'b0;

            //流水推进（含气泡）
            v1_r <= accept_w;
            v2_r <= v1_r;
            l2_r <= l1_r;
            if (v1_r) begin
                pa_r <= $signed({{24{x1a_r[7]}}, x1a_r}) * $signed(ma_r);
                pb_r <= $signed({{24{x1b_r[7]}}, x1b_r}) * $signed(mb_r);
            end
            x1a_r <= a_data_i;
            x1b_r <= b_data_i;
            l1_r  <= accept_w && (cnt_r == n_r - 32'd1);
            if (v2_r) begin
                y_valid_o <= 1'b1;
                y_o       <= y3_w;
                y_last_o  <= l2_r;
            end

            case (state_r)
                ST_IDLE: begin
                    if (start_i) begin
                        n_r      <= n_i;
                        cnt_r    <= 32'd0;
                        ma_r     <= ma_i;
                        sa_r     <= sa_i;
                        mb_r     <= mb_i;
                        sb_r     <= sb_i;
                        drain_r  <= 2'd0;
                        state_r  <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (accept_w) begin
                        cnt_r <= cnt_r + 32'd1;
                        if (cnt_r == n_r - 32'd1)
                            drain_r <= 2'd3;      //末拍接收，3 拍出净
                    end
                    if (drain_r != 2'd0) begin
                        drain_r <= drain_r - 2'd1;
                        if (drain_r == 2'd1)
                            state_r <= ST_IDLE;   //末拍 y_valid 之后回 IDLE
                    end
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
