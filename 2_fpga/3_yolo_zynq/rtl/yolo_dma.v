/************************************************************************
 * File Name       : yolo_dma.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_dma
 * Description     : M9 linear-block AXI4 read-master channel
 *                   (architecture baseline section 3.5 data ports).
 *                   Fetches cmd_len bytes starting at cmd_addr as INCR
 *                   bursts on a 64-bit AXI read channel and delivers
 *                   them as an ordered byte stream to a sink interface
 *                   (one byte per cycle, backpressured).
 *
 *                   Burst sizing per AR: beats = min(words_left,
 *                   MAX_BURST, beats_to_4KB_boundary) -- a burst never
 *                   crosses a 4KB line (AXI rule). Word count drives
 *                   fetching (final partial word fetched whole), byte
 *                   count drives delivery (tail delivers cmd_len mod 8
 *                   bytes). Byte order: little-endian, words ascending.
 *
 *                   Stall tolerance: AR accepted whenever the slave
 *                   asserts arready; R beats taken when the byte serdes
 *                   can hold a word (rready = beats pending and buffer
 *                   empty, or last byte leaving this cycle); the serdes
 *                   drains in EVERY state (delivery never gates on the
 *                   fetch FSM); sink backpressure halts the serdes
 *                   only. Single outstanding AR (arid 0), no
 *                   out-of-order exposure.
 *
 *                   Command contract: cmd_addr 8-byte aligned,
 *                   cmd_len >= 1 byte.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M9).
 ************************************************************************/

module yolo_dma #(
    parameter ADDR_W   = 32,
    parameter LEN_W    = 24,              // bytes per command (<= 16MB)
    parameter MAX_BURST = 16              // beats per burst (AXI3-style)
) (
    input  wire               clk_i,
    input  wire               rst_n,
    // command
    input  wire               cmd_valid_i,
    output wire               cmd_ready_o,
    input  wire [ADDR_W-1:0]  cmd_addr_i,
    input  wire [LEN_W-1:0]   cmd_len_i,
    output wire               done_o,      // 1-cycle pulse per command
    // AXI4 read master (single id, INCR, 8-byte)
    output wire [ADDR_W-1:0]  araddr_o,
    output wire [7:0]         arlen_o,     // beats - 1
    output wire [2:0]         arsize_o,    // 3 = 8 bytes
    output wire [1:0]         arburst_o,   // 01 = INCR
    output wire               arvalid_o,
    input  wire               arready_i,
    input  wire [63:0]        rdata_i,
    input  wire               rlast_i,
    input  wire               rvalid_i,
    output wire               rready_o,
    // byte sink (e.g. wbuf/xbuf write side)
    output wire               out_valid_o,
    output wire [7:0]         out_data_o,
    input  wire               out_ready_i
);

    localparam S_IDLE  = 3'd0;
    localparam S_AR    = 3'd1;
    localparam S_R     = 3'd2;
    localparam S_DONE  = 3'd3;

    localparam BURST_INCR = 2'd1;

    reg [2:0]         state_r;
    reg [ADDR_W-1:0]  addr_r;              // next fetch address
    reg [LEN_W-1:0]   words_r;             // whole words left to fetch
    reg [LEN_W-1:0]   bytes_r;             // bytes left to deliver
    reg [3:0]         tail_r;              // valid bytes of the final word
    reg [7:0]         beats_r;             // R beats left this burst
    reg               last_burst_r;        // this burst ends the command
    reg [63:0]        wbuf_r;              // serdes word buffer
    reg [3:0]         bcnt_r;              // valid bytes in wbuf (0..8)

    // AR sizing: min(words left, max burst, beats to the 4KB line end)
    wire [31:0] bnd_beats_w = (32'd4096 - {19'd0, addr_r[11:0]}) >> 3;
    wire [31:0] want_w      = (words_r > MAX_BURST) ? MAX_BURST : words_r;
    wire [31:0] beats_w     = (bnd_beats_w < want_w) ? bnd_beats_w : want_w;
    wire        ar_fire_w   = (state_r == S_AR) && arready_i;
    wire [31:0] words_next_w = words_r - beats_w;
    // R acceptance: serdes can take a word now (or as its last byte leaves)
    wire        r_fire_w    = (state_r == S_R) && rvalid_i
                              && ((bcnt_r == 4'd0)
                                  || (bcnt_r == 4'd1 && out_ready_i));
    wire        final_word_w = last_burst_r && (beats_r == 8'd1);
    wire        byte_fire_w  = (bcnt_r != 4'd0) && out_ready_i;

    // 单时钟块：FSM + 字节串行器合并。串行器与状态无关地排空
    // （在 S_AR/S_R/S_DONE 任何状态，bcnt!=0 且 sink ready 就交付/
    // 移位）；R 接受对 wbuf/bcnt 的写入优先于移位（同拍仅发生在
    // bcnt==1：旧字最后字节交付的同时装入新字）。命令末字节
    // （bytes_r==1）触发 S_DONE。
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state_r       <= S_IDLE;
            addr_r        <= {ADDR_W{1'b0}};
            words_r       <= {LEN_W{1'b0}};
            bytes_r       <= {LEN_W{1'b0}};
            tail_r        <= 4'd0;
            beats_r       <= 8'd0;
            last_burst_r  <= 1'b0;
            wbuf_r        <= 64'd0;
            bcnt_r        <= 4'd0;
        end else begin
            // ---- 字节串行器（所有状态） ----
            if (byte_fire_w) begin
                bytes_r <= bytes_r - 1;
                if (!r_fire_w) begin
                    wbuf_r <= wbuf_r >> 8;
                    bcnt_r <= bcnt_r - 4'd1;
                end
                if (bytes_r == 1) begin
                    state_r <= S_DONE;     // 命令末字节交付
                end
            end
            // ---- done 单拍脉冲返回空闲 ----
            // （进入 S_DONE 的那拍 bcnt 已归零，串行器不会再发火）
            if (state_r == S_DONE) begin
                state_r <= S_IDLE;
            end
            // ---- 命令接受 ----
            if ((state_r == S_IDLE) && cmd_valid_i) begin
                addr_r       <= cmd_addr_i;
                words_r      <= (cmd_len_i + 7) >> 3;
                bytes_r      <= cmd_len_i;
                tail_r       <= (cmd_len_i[2:0] == 3'd0) ?
                                 4'd8 : {1'b0, cmd_len_i[2:0]};
                last_burst_r <= 1'b0;
                bcnt_r       <= 4'd0;
                state_r      <= S_AR;
            end
            // ---- AR 发起 ----
            if ((state_r == S_AR) && arready_i) begin
                beats_r      <= beats_w[7:0];
                addr_r       <= addr_r + {beats_w[ADDR_W-3:0], 3'b000};
                words_r      <= words_next_w[LEN_W-1:0];
                last_burst_r <= (words_next_w == 32'd0);
                state_r      <= S_R;
            end
            // ---- R 接受 ----
            if (r_fire_w) begin
                wbuf_r <= rdata_i;
                if (final_word_w) begin
                    bcnt_r <= tail_r;       // 静态尾长（含 8）
                end else begin
                    bcnt_r <= 4'd8;
                    if (beats_r == 8'd1) begin
                        state_r <= S_AR;    // 取下一突发
                    end
                end
                beats_r <= beats_r - 8'd1;
            end
        end
    end

    // outputs: combinational on registered state only
    assign cmd_ready_o = (state_r == S_IDLE);
    assign done_o      = (state_r == S_DONE);
    assign araddr_o    = addr_r;
    assign arlen_o     = beats_w[7:0] - 8'd1;
    assign arsize_o    = 3'd3;
    assign arburst_o   = BURST_INCR;
    assign arvalid_o   = (state_r == S_AR);
    assign rready_o    = (state_r == S_R) && (beats_r != 8'd0)
                         && ((bcnt_r == 4'd0)
                             || (bcnt_r == 4'd1 && out_ready_i));
    assign out_valid_o = (bcnt_r != 4'd0);
    assign out_data_o  = wbuf_r[7:0];

    // rlast_i unused: burst end tracked from arlen (monitor checks rlast)

endmodule
