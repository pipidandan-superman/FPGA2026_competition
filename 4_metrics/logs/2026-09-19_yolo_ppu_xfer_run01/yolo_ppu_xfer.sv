/************************************************************************
 * File Name       : yolo_ppu_xfer.sv
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ppu_xfer
 * Description     : PPU xfer engine core (PPU manual section 5.2):
 *                   segment-sequential byte stream copy (CONCAT/HEADS/
 *                   COPY) with PER-SEGMENT optional requant.  A segment
 *                   whose profile is the identity pair (M=2^30, s=30)
 *                   takes the hardware SHORTCUT -- a plain byte copy,
 *                   bit-exact because x*2^30>>30 RNE == x for all int8 x
 *                   (P0-proven, manual 2.1).  The P2e gate pins this
 *                   equivalence empirically: golden computes the FULL
 *                   requant for EVERY segment (no shortcut), the DUT
 *                   shortcuts identity segments, and DUT==golden.
 *
 *   Core contract: segment table (<= MAXSEG entries: len/M/s) written
 *     via the table port while idle; start latches N_seg; input is ONE
 *     byte stream with segments concatenated in channel order (the P3
 *     DMA wrapper feeds segment buffers back-to-back; heads uses 6
 *     identity segments).  Output is one byte stream, out_last pulses
 *     with the final byte of the final segment.
 *
 *   Pipeline: accept (captures byte + segment profile + identity flag)
 *     -> S2 product (int64) -> S3 RNE + sat_i8, with the identity byte
 *     BYPASSING the arithmetic (S3 mux) -- a structural shortcut, not a
 *     degenerate requant.  D+3 with bubbles; drain=3 ends the task.
 *     RNE wires identical to yolo_ppu_requant / GEMM tail.
 * Dependencies    : None (pure fabric).
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : Initial release (P2e).
 ************************************************************************/

module yolo_ppu_xfer #(
    parameter integer MAXSEG = 8          //内联段表容量（手册 §4：8）
) (
    input  wire        clk_i,      //运算时钟
    input  wire        rst_i,      //同步复位，高有效（回 ST_IDLE，清脉冲）
    // ---- 段表写口（ST_IDLE 时）----
    input  wire        seg_we_i,   //写使能（地址自增 0..MAXSEG-1）
    input  wire [31:0] seg_len_i,  //段字节长度
    input  wire [31:0] seg_m_i,    //段 quant profile M
    input  wire [5:0]  seg_s_i,    //段 quant profile shift
    // ---- task start（ST_IDLE 时采样；段表已写好）----
    input  wire        start_i,    //启动脉冲
    input  wire [3:0]  nseg_i,     //段数 N_seg（1..MAXSEG）
    // ---- 输入字节流（段序拼接）----
    output wire        in_ready_o,
    input  wire        in_valid_i,
    input  wire [7:0]  in_data_i,
    // ---- 输出字节流 ----
    output reg         y_valid_o,
    output reg  [7:0]  y_o,
    output reg         y_last_o,   //全任务末字节同拍脉冲
    output wire        busy_o
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;
    localparam [31:0] IDENT_M = 32'd1 << 30;
    localparam [5:0]  IDENT_S = 6'd30;

    reg [1:0]  state_r;
    reg [31:0] len_r [0:MAXSEG-1];     //段表
    reg [31:0] m_r   [0:MAXSEG-1];
    reg [5:0]  s_r   [0:MAXSEG-1];
    reg [3:0]  wa_r;                   //段表写地址（自增）
    reg [3:0]  nseg_r, seg_r;          //段数 / 当前段
    reg [31:0] bc_r;                   //段内字节计数
    reg [1:0]  drain_r;

    reg        v1_r, v2_r;             //流水有效链（含气泡）
    reg        l1_r, l2_r;             //全任务末字节标志链
    reg [7:0]  x1_r, x2_r;             //字节旁路链（恒等捷径用，与
                                        //pa_r/s2_r 同级——y_o 写拍采样）
    reg [31:0] m1_r;                   //profile 捕获（与 x1_r 同拍配对）
    reg [5:0]  s1_r, s2_r;
    reg        id1_r, id2_r;           //恒等标志链
    reg signed [63:0] pa_r;            //S2 乘积（int64）

    wire run_w     = (state_r == ST_RUN);
    wire more_w    = (seg_r < nseg_r);
    wire aacc_w    = run_w && more_w;
    wire accept_w  = aacc_w && in_valid_i;
    //本拍字节是否为全任务末字节（末段末字节）
    wire lastb_w   = accept_w && (seg_r == nseg_r - 4'd1)
                     && (bc_r == len_r[seg_r] - 32'd1);

    assign in_ready_o = aacc_w;
    assign busy_o     = (state_r != ST_IDLE);

    //段表当前项（接受时捕获入流水）
    wire [31:0] seg_m_w = m_r[seg_r];
    wire [5:0]  seg_s_w = s_r[seg_r];
    wire        seg_id_w = (seg_m_w == IDENT_M) && (seg_s_w == IDENT_S);

    // ---- S3：RNE + sat（同 GEMM 尾/requant 移位+掩码式）----
    function signed [63:0] rne64(input signed [63:0] prod,
                                 input [5:0] sh);
        reg signed [63:0] q;
        reg [63:0] rem, half;
        begin
            if (sh == 6'd0) begin
                rne64 = prod;                       //s=0 旁路
            end else begin
                q    = prod >>> sh;
                rem  = prod & ((64'd1 << sh) - 64'd1);
                half = 64'd1 << (sh - 6'd1);
                rne64 = q + (((rem > half) ||
                              (rem == half && q[0])) ? 64'sd1 : 64'sd0);
            end
        end
    endfunction

    wire signed [63:0] q3_w = rne64(pa_r, s2_r);
    wire [7:0] rq3_w =
        (q3_w > 64'sd127)  ? 8'd127 :
        (q3_w < -64'sd128) ? 8'h80 : q3_w[7:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r   <= ST_IDLE;
            wa_r      <= 4'd0;          //段表写地址归 0（多任务轮转）
            v1_r      <= 1'b0;
            v2_r      <= 1'b0;
            id2_r     <= 1'b0;
            y_valid_o <= 1'b0;
            y_last_o  <= 1'b0;
        end else begin
            //默认单拍脉冲
            y_valid_o <= 1'b0;
            y_last_o  <= 1'b0;

            //流水推进（含气泡）
            v1_r  <= accept_w;
            v2_r  <= v1_r;
            l2_r  <= l1_r;
            s2_r  <= s1_r;
            id2_r <= id1_r;
            x2_r  <= x1_r;
            if (v1_r)
                pa_r <= $signed({{24{x1_r[7]}}, x1_r}) * $signed(m1_r);
            x1_r <= in_data_i;
            m1_r <= seg_m_w;
            s1_r <= seg_s_w;
            id1_r <= seg_id_w;
            l1_r  <= lastb_w;
            if (v2_r) begin
                y_valid_o <= 1'b1;
                y_o       <= id2_r ? x2_r : rq3_w;   //恒等捷径：字节旁路
                y_last_o  <= l2_r;
            end

            case (state_r)
                ST_IDLE: begin
                    if (seg_we_i) begin
                        len_r[wa_r[2:0]] <= seg_len_i;
                        m_r[wa_r[2:0]]   <= seg_m_i;
                        s_r[wa_r[2:0]]   <= seg_s_i;
                        wa_r <= wa_r + 4'd1;
                    end
                    if (start_i) begin
                        nseg_r  <= nseg_i;
                        seg_r   <= 4'd0;
                        bc_r    <= 32'd0;
                        drain_r <= 2'd0;
                        wa_r    <= 4'd0;  //下一任务段表从 0 重写
                        state_r <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (accept_w) begin
                        if (bc_r == len_r[seg_r] - 32'd1) begin
                            bc_r <= 32'd0;
                            seg_r <= seg_r + 4'd1;   //段切换
                        end else begin
                            bc_r <= bc_r + 32'd1;
                        end
                        if (lastb_w)
                            drain_r <= 2'd3;
                    end
                    if (drain_r != 2'd0) begin
                        drain_r <= drain_r - 2'd1;
                        if (drain_r == 2'd1)
                            state_r <= ST_IDLE;
                    end
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
