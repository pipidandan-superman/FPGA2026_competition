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
 *   - V1.1 (2026-09-17) by LSL : B0 v20 ooc（用户授权 dma 增量寻址批）：
 *                 4KB 边界拍数改增量维护寄存器 bnd_r（命令接受沿
 *                 512−cmd_addr[11:3] 装载；AR 发火沿 −beats，吃掉边界
 *                 则回装 512）——原每拍 (4096−addr_r[11:0])>>3 重算的
 *                 12 位减法+比较级联嵌在 addr_r/last_burst_r 全部更新
 *                 路径里（v20 owner addr_r→last_burst_r −0.862、
 *                 addr_r→addr_r[31] −0.783）。addr_r 变纯累加器，
 *                 beats_w 不再读 addr_r。突发序列/地址逐拍不变（同一
 *                 计算的纯重定时），AXI 行为零变化。门重跑：M9 + M10
 *                 + B0 v21。
 *   - V1.2 (2026-09-17) by LSL : B0 v21 ooc——bnd 结算沿从 AR 发火挪到
 *                 突发末拍：AR 发火时装 blen_r（本突发拍数 ≤16，5 位），
 *                 末拍（r_fire && beats_r==1 && 非命令末字）读 blen_r 与
 *                 bnd_r 作 10 位等值/减法结算。原 V1.1 的发火沿更新读
 *                 words_r→beats_w 最小值级联（words_r>16 折叠→32 位
 *                 min→零扩展比较→10 位减法→回装 mux），v21 dma_wr 同源
 *                 owner words_r→bnd_r −0.634。突发序列/地址逐拍不变
 *                 （同一算术、结算时刻不同——bnd_r 在下一 AR 可见前已
 *                 更新完毕），AXI 行为零变化。门重跑：M9 + M10 + B0 v22。
 *   - V1.3 (2026-09-17) by LSL : B0 v22 ooc dma_wr 同源 owner（dma_wr
 *                 words_r→addr_r −0.581 / words_r→words_r −0.496，读侧
 *                 同构路径预防性同批修复）——AR 突发参数预计算拆沿：
 *                 want2_r=min(words_r,16) 与 addr_r 推进（+blen_r<<3）均
 *                 改在上一突发末拍装载/结算（words_r 自上次 AR 发火起
 *                 稳定 ≥1 拍，addr_r/blen_r 全突发稳定）；AR 发火沿只剩
 *                 min(bnd_r,want2_r) 10 位比较 + 一次 32 位减法，addr_r
 *                 发火沿纯寄存器搬运。araddr_o 仅在 S_AR 被采样，提前
 *                 推进不可见。突发序列/地址/周期行为逐拍不变（同一算术
 *                 的纯重定时）。命令接受沿的 want2_r 由 cmd 总线直算
 *                 （OOC 输入端口无输入延迟约束，B1 整合时按真实 input
 *                 delay 复核）。门重跑：M9 + M10 + B0 v23。
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
    reg [9:0]         bnd_r;               // V1.1: beats to the 4KB line
                                          // end, maintained INCREMENTALLY
                                          // (was recomputed per cycle from
                                          // addr_r[11:0]: the 12-bit
                                          // subtract + compare cascade sat
                                          // inside every addr_r/last_burst
                                          // update -- v20 ooc dma owner
                                          // addr_r->last_burst_r -0.862,
                                          // addr_r->addr_r[31] -0.783)
    reg [4:0]         blen_r;              // V1.2: current burst's beat
                                          // count (<= MAX_BURST=16, 5b),
                                          // loaded at AR fire -- lets the
                                          // bnd settlement run at the
                                          // burst's LAST R BEAT off this
                                          // 5b register instead of the
                                          // words_r->beats_w min cascade
                                          // (v21 dma_wr-tier owner
                                          // words_r->bnd_r -0.634)
    reg [31:0]        want2_r;             // V1.3: min(words_r, MAX_BURST)
                                          // for the NEXT burst, preloaded at
                                          // the previous burst's LAST R BEAT
                                          // (words_r stable since the last AR
                                          // fire) or at command accept (off
                                          // the cmd bus) -- the AR fire edge
                                          // then only resolves
                                          // min(bnd_r, want2_r) (10b) + one
                                          // 32b subtract (v22 dma_wr-tier
                                          // owner words_r->addr_r -0.581)

    // AR sizing: min(words left, max burst, beats to the 4KB line end).
    // V1.1: bnd is a REGISTER -- loaded at command accept (addr is
    // 8-byte aligned by contract, so bnd = 512 - addr[11:3]); V1.2: the
    // decrement/re-arm settles at each burst's LAST R BEAT off blen_r
    // (the burst's registered beat count), so the bnd update chain reads
    // registers only -- words_r exits it entirely. Burst sequence
    // identical to the per-cycle recompute (pure retiming of the same
    // computation); addr_r is a plain accumulator.
    // V1.3: min(words_r, MAX_BURST) is likewise a REGISTER (want2_r,
    // loaded at burst end / accept) and the addr_r advance (+blen_r<<3)
    // settles at burst end -- the fire edge reads registers through one
    // 10b compare + one 32b subtract only.
    wire [31:0] cmd_words_w  = (cmd_len_i + 32'd7) >> 3;
    wire [31:0] beats_w     = ({22'd0, bnd_r} < want2_r) ? {22'd0, bnd_r}
                                                        : want2_r;
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
            bnd_r         <= 10'd512;
            blen_r        <= 5'd0;
            want2_r       <= 32'd0;   // primed at command accept
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
                words_r      <= cmd_words_w[LEN_W-1:0];
                // V1.3: 首突发 want2 由 cmd 总线直算（OOC 输入端口无
                // 输入延迟约束；B1 整合时按真实 input delay 复核）
                want2_r      <= (cmd_words_w > MAX_BURST) ? MAX_BURST
                                                          : cmd_words_w;
                bytes_r      <= cmd_len_i;
                tail_r       <= (cmd_len_i[2:0] == 3'd0) ?
                                 4'd8 : {1'b0, cmd_len_i[2:0]};
                last_burst_r <= 1'b0;
                bcnt_r       <= 4'd0;
                bnd_r        <= 10'd512 - {1'b0, cmd_addr_i[11:3]};
                state_r      <= S_AR;
            end
            // ---- AR 发起 ----
            if ((state_r == S_AR) && arready_i) begin
                beats_r      <= beats_w[7:0];
                blen_r       <= beats_w[4:0];   // V1.2: 供突发末拍结算
                // V1.3: addr_r 推进移至突发末拍（+blen_r<<3，读两个全
                // 突发稳定的寄存器）——发火沿不再串 min 级联+32 位加法
                words_r      <= words_next_w[LEN_W-1:0];
                last_burst_r <= (words_next_w == 32'd0);
                // V1.2: 边界结算移至本突发末拍（见 R 接受块）——AR 发火
                // 沿不再读 words_r->beats_w 级联更新 bnd_r
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
                        // V1.2: 本突发吃掉的边界拍数在末拍结算——读
                        // blen_r（5b 寄存）与 bnd_r 作 10 位等值/减法，
                        // words_r 完全退出 bnd 更新链
                        bnd_r  <= (bnd_r == {5'd0, blen_r}) ? 10'd512
                                 : (bnd_r - {5'd0, blen_r});
                        // V1.3: 下一突发 AR 参数末拍预计算——words_r 自
                        // 上次 AR 发火起稳定（≥1 拍），addr_r/blen_r 全
                        // 突发稳定：单 24 位比较 + 单 32 位进位链
                        addr_r  <= addr_r + {24'd0, blen_r, 3'b000};
                        want2_r <= (words_r > MAX_BURST) ? MAX_BURST : words_r;
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
