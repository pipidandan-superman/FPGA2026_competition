/************************************************************************
 * File Name       : yolo_ppu_upsample2.sv
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ppu_upsample2
 * Description     : PPU upsample2 engine core (PPU manual section 5.5):
 *                   nearest-neighbour x2 on H and W.
 *
 *   Contract (manual 2.2, verbatim upsample_nearest2):
 *     out[c, 2y+dy, 2x+dx] = in[c, y, x]  for dy,dx in {0,1}
 *     Output byte address (within out buffer, CHW, row stride 2W):
 *       addr = c*4HW + (2y+dy)*2W + 2x + dx
 *     Pure addressing, no arithmetic on data.
 *
 *   Structure: streaming byte core.  Each accepted input byte is held
 *   and emitted as FOUR output beats (phases dy*dx = 00,01,10,11) on
 *   consecutive cycles; input acceptance is possible only at phase 0
 *   (in_ready_o), so sustained throughput is 1 input / 4 cycles =
 *   exactly the 4x data expansion -- no buffer needed.  Addresses are
 *   produced by INCREMENTAL adds only (plane/rowpair/col bases advance
 *   on x/y/c wraps); the only multiply is the one-time plane size
 *   (2H)*(2W) at task start.  Shape domain: C, H, W latched at start;
 *   C*4HW must fit the 32-bit buffer-offset domain (buffer-table
 *   contract, max buffer 409600 B in the current package).
 *
 *   Timing: start_i latches C/H/W in ST_IDLE -> ST_RUN.  Input byte
 *   accepted at cycle D (in_valid & in_ready) -> outputs registered
 *   at cycles D+1..D+4 (phases 0..3).  out_last_o pulses WITH the
 *   final beat (phase 3 of the C-1,H-1,W-1 byte) and the core returns
 *   ST_IDLE.  start_i during ST_RUN is ignored (sequential task
 *   dispatch is the walker's contract, manual 4.2).
 * Dependencies    : None (pure fabric).
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : Initial release (P2b).
 ************************************************************************/

module yolo_ppu_upsample2 (
    input  wire        clk_i,      //运算时钟
    input  wire        rst_i,      //同步复位，高有效（回 ST_IDLE，清脉冲）
    // ---- task start（ST_IDLE 时采样）----
    input  wire        start_i,    //启动脉冲
    input  wire [15:0] c_i,        //通道数 C
    input  wire [15:0] h_i,        //输入高 H
    input  wire [15:0] w_i,        //输入宽 W
    // ---- input byte stream（CHW 线性序）----
    output wire        in_ready_o, //本拍可收输入字节（RUN 且 phase 0）
    input  wire        in_valid_i,
    input  wire [7:0]  in_data_i,
    // ---- output byte stream（含输出缓冲内字节偏移地址）----
    output reg         out_valid_o,
    output reg  [7:0]  out_data_o,
    output reg  [31:0] out_addr_o, //out 缓冲内偏移（CHW，行距 2W）
    output reg         out_last_o, //末字节（末输入的 phase 3）同拍脉冲
    output wire        busy_o
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;

    reg [1:0]  state_r;
    reg [1:0]  ph_r;                 //输出相位 0..3（00,01,10,11）
    reg [15:0] cw_r, ch_r;           //锁存 W/H（回绕比较用）
    reg [15:0] ctot_r;               //锁存 C（末字节判定用）
    reg [15:0] x_r, y_r, c_r;        //输入字节游标
    reg [31:0] plane_r;              //= (2H)*(2W)，通道平面字节数
    reg [31:0] rowlen_r;             //= 2W，输出行距
    reg [31:0] cbase_r;              //= c * plane（增量维护）
    reg [31:0] rowpair_r;            //= cbase + (2y)*2W（增量维护）
    reg [31:0] base0_r;              //本字节 phase0 地址（ph1..3 相对偏移）
    reg [7:0]  data_r;               //保持的输入字节
    reg        last_r;               //本字节为任务末输入

    // ---- 下一轮坐标/基地址（组合，供顺序块使用）----
    wire        x_end_w = (x_r == cw_r - 16'd1);
    wire        y_end_w = (y_r == ch_r - 16'd1);
    wire        c_end_w = (c_r == ctot_r - 16'd1);
    wire [31:0] col2_w  = {16'd0, x_r} << 1;         //2x
    wire [31:0] nxt_cbase_w   = cbase_r + plane_r;
    wire [31:0] nxt_rowpair_w = rowpair_r + (rowlen_r << 1); //y 前进 2 行距

    assign in_ready_o = (state_r == ST_RUN) && (ph_r == 2'd0);
    assign busy_o     = (state_r != ST_IDLE);

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
                        cw_r      <= w_i;
                        ch_r      <= h_i;
                        ctot_r    <= c_i;
                        x_r       <= 16'd0;
                        y_r       <= 16'd0;
                        c_r       <= 16'd0;
                        plane_r   <= ({1'b0, h_i} << 1) * ({1'b0, w_i} << 1);
                        rowlen_r  <= {16'd0, w_i} << 1;
                        cbase_r   <= 32'd0;
                        rowpair_r <= 32'd0;
                        ph_r      <= 2'd0;
                        last_r    <= 1'b0;
                        state_r   <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (ph_r == 2'd0) begin
                        if (in_valid_i) begin
                            //收字节并发射 phase0（寄存输出，D+1 呈现）
                            base0_r     <= rowpair_r + col2_w;
                            data_r      <= in_data_i;
                            out_valid_o <= 1'b1;
                            out_data_o  <= in_data_i;
                            out_addr_o  <= rowpair_r + col2_w;
                            last_r      <= x_end_w && y_end_w && c_end_w;
                            //游标/基地址推进（x/y/c 回绕）
                            if (x_end_w) begin
                                x_r <= 16'd0;
                                if (y_end_w) begin
                                    y_r       <= 16'd0;
                                    c_r       <= c_r + 16'd1;
                                    cbase_r   <= nxt_cbase_w;
                                    rowpair_r <= nxt_cbase_w;
                                end else begin
                                    y_r       <= y_r + 16'd1;
                                    rowpair_r <= nxt_rowpair_w;
                                end
                            end else begin
                                x_r <= x_r + 16'd1;
                            end
                            ph_r <= 2'd1;
                        end
                    end else begin
                        //发射保持字节的 phase 1..3
                        out_valid_o <= 1'b1;
                        out_data_o  <= data_r;
                        case (ph_r)
                            2'd1: out_addr_o <= base0_r + 32'd1;
                            2'd2: out_addr_o <= base0_r + rowlen_r;
                            default: //2'd3
                                   out_addr_o <= base0_r + rowlen_r + 32'd1;
                        endcase
                        if (ph_r == 2'd3) begin
                            ph_r <= 2'd0;
                            if (last_r) begin
                                out_last_o <= 1'b1;
                                state_r    <= ST_IDLE;
                            end
                        end else begin
                            ph_r <= ph_r + 2'd1;
                        end
                    end
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
