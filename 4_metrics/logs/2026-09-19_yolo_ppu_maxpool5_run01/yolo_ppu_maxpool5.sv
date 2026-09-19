/************************************************************************
 * File Name       : yolo_ppu_maxpool5.sv
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ppu_maxpool5
 * Description     : PPU maxpool5 engine core (PPU manual section 5.4):
 *                   5x5 stride-1 SAME pooling with pad -128, implemented
 *                   WITHOUT materialising pad bytes -- valid-position
 *                   masking only (equivalence proven manual 2.2, pinned
 *                   empirically by the P2c gate: python pad-model golden
 *                   vs this masked RTL on adversarial vectors incl.
 *                   all--128 tensors and W/H < 5 shapes).
 *
 *   Contract (manual 2.2, verbatim maxpool5): out[c,y,x] =
 *     max over valid positions of in[c, y-2..y+2, x-2..x+2].
 *     Pad bytes are -128 == int8 minimum, so masked max seeded with
 *     -128 is bit-identical (the seed mirrors the oracle's
 *     o = -128 initialisation; the center tap is always valid).
 *
 *   Structure: processor grid of (H+2) x (W+2) steps per channel
 *     (rows 0..H+1, cols 0..W+1).  Steps with proc-row < H AND
 *     proc-col < W consume one input byte (CHW stream); all other
 *     steps are pad steps that auto-advance.  EVERY step advances a
 *     delay line dl_r: dl_r[i] = the byte entered i steps ago; since
 *     each row takes exactly L = W+2 steps, the byte of window row
 *     (pr-4+r), col (pc-4+t) entered at delay
 *         idx(r,t) = (4-r)*L + (4-t).
 *     Step (pr, pc) emits output (pr-2, pc-2) when pr >= 2 and
 *     pc >= 2 -- exactly H*W emissions per channel, CHW linear order.
 *     Validity masks: window row wr = pr-4+r valid iff 0 <= wr < H;
 *     window col wc = pc-4+t valid iff 0 <= wc < W.  Correct for ALL
 *     H, W >= 1 (incl. H or W < 5).  Valid taps always reference
 *     already-entered bytes, so the delay line needs no clearing
 *     between tasks/channels.
 *
 *   MAXW bounds the delay line (4*(MAXW+2)+5 bytes).  Package-real
 *     W = 10; W > MAXW requires raising the parameter (buffer-table
 *     domain check belongs to the descriptor loader, P3).
 *
 *   Timing: output registered at the step -> out_valid during the
 *     next cycle.  in_ready_o high only on input-consuming steps;
 *     input stalls freeze the grid.  out_last_o pulses with the
 *     final beat.  NOTE the max reads POST-SHIFT delay-line values
 *     (idx-1, and in_data_i at idx 0): the byte accepted THIS step
 *     is the window's right column -- reading pre-shift taps shifts
 *     the whole window one column late (run01 first-run lesson).
 *     Delay-line cells model semantics; RAM/LUTRAM mapping is a
 *     synthesis choice that keeps this interface.
 * Dependencies    : None (pure fabric).
 * Revision History:
 *   - V1.1 (2026-09-19) by LSL : 改延迟线结构；max 读移位后语义。
 *   - V1.0 (2026-09-19) by LSL : Initial release (P2c).
 ************************************************************************/

module yolo_ppu_maxpool5 #(
    parameter integer MAXW = 64          //延迟线容量上界（W 域）
) (
    input  wire        clk_i,      //运算时钟
    input  wire        rst_i,      //同步复位，高有效（回 ST_IDLE，清脉冲）
    // ---- task start（ST_IDLE 时采样）----
    input  wire        start_i,    //启动脉冲
    input  wire [15:0] c_i,        //通道数 C
    input  wire [15:0] h_i,        //输入/输出高 H
    input  wire [15:0] w_i,        //输入/输出宽 W
    // ---- input byte stream（CHW 线性序）----
    output wire        in_ready_o, //本拍可收输入字节（输入步）
    input  wire        in_valid_i,
    input  wire [7:0]  in_data_i,
    // ---- output byte stream（CHW 线性序，同形）----
    output reg         out_valid_o,
    output reg  [7:0]  out_data_o,
    output reg         out_last_o, //末字节同拍脉冲
    output wire        busy_o
);

    localparam [1:0]  ST_IDLE = 2'd0;
    localparam [1:0]  ST_RUN  = 2'd1;
    localparam integer DLN = 4 * (MAXW + 2) + 5;

    reg [1:0]  state_r;
    reg [15:0] cw_r, ch_r;           //锁存 W/H
    reg [15:0] ctot_r;               //锁存 C
    reg [15:0] pr_r, pc_r;           //处理网格游标（行 [0,H+2)，列 [0,W+2)）
    reg [15:0] c_r;                  //通道计数
    reg [7:0]  dl_r [0:DLN-1];       //延迟线：dl_r[i] = i 步前进入的字节

    // ---- 步进条件：输入步需握手，pad 步自走 ----
    wire input_step_w = (pr_r < ch_r) && (pc_r < cw_r);
    wire step_w       = input_step_w ? in_valid_i : 1'b1;
    wire last_step_w  = (c_r == ctot_r - 16'd1)
                      && (pr_r == ch_r + 16'd1)
                      && (pc_r == cw_r + 16'd1);

    assign in_ready_o = (state_r == ST_RUN) && input_step_w;
    assign busy_o     = (state_r != ST_IDLE);

    // ---- 25 抽头有效掩码 + 掩码 max（种子 −128=pad 值，同 oracle）----
    // 读移位后语义：抽头 idx 的移位后值 = (idx==0) ? in_data_i
    // : dl_r[idx-1]（移位前数组）。idx = (4-r)*L + (4-t)。
    function [7:0] wmax_masked(input [15:0] pr, input [15:0] pc,
                               input [15:0] hh, input [15:0] ww);
        integer r, t, idx;
        reg [7:0] m, d;
        begin
            m = 8'h80;
            for (r = 0; r < 5; r = r + 1)
                for (t = 0; t < 5; t = t + 1) begin
                    idx = (4 - r) * (ww + 2) + (4 - t);
                    d = (idx == 0) ? in_data_i : dl_r[idx-1];
                    //窗行 wr = pr-4+r ∈ [0,H)，窗列 wc = pc-4+t ∈ [0,W)
                    if ((pr + r >= 4) && (pr + r < hh + 4)
                        && (pc + t >= 4) && (pc + t < ww + 4)
                        && ($signed(d) > $signed(m)))
                        m = d;
                end
            wmax_masked = m;
        end
    endfunction

    integer i;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r     <= ST_IDLE;
            out_valid_o <= 1'b0;
            out_last_o  <= 1'b0;
        end else begin
            //默认单拍脉冲
            out_valid_o <= 1'b0;
            out_last_o  <= 1'b0;

            case (state_r)
                ST_IDLE: begin
                    if (start_i) begin
                        cw_r   <= w_i;
                        ch_r   <= h_i;
                        ctot_r <= c_i;
                        pr_r   <= 16'd0;
                        pc_r   <= 16'd0;
                        c_r    <= 16'd0;
                        state_r <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (step_w) begin
                        //延迟线整体前移（pad 步也移：同列跨行恒隔 L 步）
                        for (i = DLN - 1; i > 0; i = i - 1)
                            dl_r[i] <= dl_r[i-1];
                        dl_r[0] <= in_data_i;   //pad 步为无效数据（掩码排除）

                        //输出 (pr-2, pc-2)
                        if (pr_r >= 16'd2 && pc_r >= 16'd2) begin
                            out_valid_o <= 1'b1;
                            out_data_o  <= wmax_masked(pr_r, pc_r, ch_r, cw_r);
                            out_last_o  <= last_step_w;
                        end

                        //游标推进：列 [0,W+2)，行 [0,H+2)，通道 [0,C)
                        if (pc_r == cw_r + 16'd1) begin
                            pc_r <= 16'd0;
                            if (pr_r == ch_r + 16'd1) begin
                                pr_r <= 16'd0;
                                c_r  <= c_r + 16'd1;
                                if (last_step_w)
                                    state_r <= ST_IDLE;
                            end else begin
                                pr_r <= pr_r + 16'd1;
                            end
                        end else begin
                            pc_r <= pc_r + 16'd1;
                        end
                    end
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
