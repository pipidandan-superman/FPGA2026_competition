/************************************************************************
 * File Name       : yolo_dma_wr.v
 * Developer       : LSL
 * Date            : 2026-09-16
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_dma_wr
 * Description     : M9b linear-block AXI4 write-master channel
 *                   (mirror of yolo_dma, architecture baseline section
 *                   3.5 Y data port). Accepts cmd_len bytes for a
 *                   contiguous run starting at cmd_addr, pulls them
 *                   from a byte source (one byte per cycle, source
 *                   holds until accepted), and writes them to the AXI
 *                   slave as INCR bursts on a 64-bit W channel.
 *
 *                   Burst sizing per AW: beats = min(words left,
 *                   MAX_BURST, beats_to_4KB_boundary) -- a burst never
 *                   crosses a 4KB line (AXI rule), identical sizing
 *                   law to the read channel. Word assembly: source
 *                   byte k of a word lands in lane [8k+:8] (indexed
 *                   byte-lane write, not a shifter); a word is sendable
 *                   at 8/8 bytes, or any time when the command's byte
 *                   count has drained (tail word, wstrb = low bcnt
 *                   bits). Byte order little-endian, words ascending --
 *                   the exact inverse of the read serdes: the word
 *                   written at address A reproduces the read channel's
 *                   rdata for A verbatim.
 *
 *                   Channel order: one outstanding AW (awid 0) at a
 *                   time. Every burst's final beat carries WLAST; the
 *                   next AW issues only after the previous burst's
 *                   WLAST handshake (burst chaining: each burst end
 *                   returns to S_AW until words_r is exhausted, then
 *                   S_DR drains B). B responses are accepted
 *                   whenever presented (bready held high -- single id
 *                   guarantees in-order responses) and counted by an
 *                   independent process (M9 discipline: response
 *                   handling never gates the AW/W engine); done fires
 *                   only when the last beat is sent AND every issued
 *                   AW has its B collected. W beats may have gaps
 *                   (assembly paced by the source) -- legal AXI,
 *                   slaves must tolerate.
 *
 *                   Command contract: cmd_addr any byte alignment, cmd_len
 *                   >= 1 byte (V1.2). Unaligned starts: the first AW address
 *                   rounds DOWN to the 8-byte line (awaddr must be
 *                   awsize-aligned per AXI), the assembler starts at lane
 *                   cmd_addr[2:0] (source byte 0 -> lane head, byte k ->
 *                   lane head+k in the first word), and the first word's
 *                   wstrb masks the head lanes. Every strobed byte lands at
 *                   exactly cmd_addr + k -- the DDR-side view is
 *                   alignment-independent (Y rows start at oc*n_total +
 *                   n_tile*N_EDGE, only 4-byte aligned for the N=100 layers,
 *                   arbitrary for synthetic gates). done_o: 1-cycle pulse
 *                   once the last beat is sent and every issued AW has
 *                   its B collected (bresp not checked here; the
 *                   unit gate's BFM asserts OKAY).
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-16) by LSL : Initial release (M12 A1, M9b gate).
 *   - V1.1 (2026-09-16) by LSL : M9b run01 失败链两处 AXI 缺陷修复：
 *                 ① WLAST 只在命令末字置起 -> 改为每突发末拍（beats_r==1）
 *                   置起（AXI 要求，读通道 rlast 的镜像）；② 突发链化缺失：
 *                   状态转移挂在 final_word（命令末字）-> 改为挂 burst 末拍，
 *                   words_r==0 选 S_DR、否则回 S_AW 发下一突发（原实现非末
 *                   突发打完停在 S_W，beats_r 下溢继续发无 AW 的 beat）。
 *                   last_burst_r 冗余删除。
 *   - V1.2 (2026-09-16) by LSL : 非对齐起始支持（M12 A1 阵列 Y 行段化）：
 *                 命令地址任意字节对齐——内部 awaddr 下对齐 8B、装配计数
 *                 从 head 起、首字 wstrb 掩 head lanes、覆盖字数 =
 *                 ceil((head+len)/8)。head=0 时与 V1.1 逐位等价（回归）。
 *                 门重跑：M9b run03。
 *   - V1.3 (2026-09-17) by LSL : B0 v20 ooc（用户授权 dma 增量寻址批，
 *                 dma V1.1 镜像）：4KB 边界拍数改增量维护寄存器 bnd_r——
 *                 命令接受沿 512−cmd_addr[11:3] 装载（awaddr 本就下对齐
 *                 8B，[11:3] 与 [2:0] 无关），AW 发火沿 −beats、吃掉边界
 *                 则回装 512；删除每拍 (4096−addr_r[11:0])>>3 重算的
 *                 bnd_beats_w（12 位减法+比较级联嵌在 addr_r 更新路径，
 *                 v20 ooc dma_wr 同源 owner），addr_r 变纯累加器。突发
 *                 序列/地址逐拍不变（同一计算的纯重定时），AXI 行为零变
 *                 化；head=0 时与 V1.2 逐位等价的回归路径不变。门重跑：
 *                 M9b + M10 + B0 v21。
 *   - V1.4 (2026-09-17) by LSL : B0 v21 ooc（words_r→bnd_r −0.634 owner
 *                 本体）——bnd 结算沿从 AW 发火挪到突发末拍：AW 发火装
 *                 blen_r（本突发拍数 ≤16，5 位），末拍（w_fire &&
 *                 burst_last）读 blen_r 与 bnd_r 作 10 位等值/减法结算，
 *                 words_r 退出 bnd 更新链（原 V1.3 发火沿更新读
 *                 words_r→beats_w 最小值级联）。转 S_DR 末拍的结算是哑
 *                 写（下一命令接受沿重装）。突发序列/地址逐拍不变，AXI
 *                 行为零变化。门重跑：M9b + M10 + B0 v22。
 *   - V1.5 (2026-09-17) by LSL : B0 v22 ooc（top10 全体 words_r→addr_r
 *                 −0.581 / words_r→words_r −0.496——发火沿串行本体：
 *                 min(words_r,16) 24 位比较 → min(bnd_r,·) → 32 位减法
 *                 回装，加法侧再串 32 位 addr 进位链）。突发参数预计算
 *                 拆沿：want2_r=min(words_r,16) 与 addr_r 推进（+blen_r<<3）
 *                 均改在上一突发末拍装载/结算（words_r 自上次 AW 发火起
 *                 稳定 ≥1 拍，addr_r/blen_r 全突发稳定——末拍只剩单 24 位
 *                 比较与单 32 位进位链）；AW 发火沿只剩 min(bnd_r,want2_r)
 *                 10 位比较 + 一次 32 位减法，addr_r 发火沿纯寄存器搬运。
 *                 awaddr_o 仅在 S_AW 被采样，提前推进不可见。突发序列/
 *                 地址/周期行为逐拍不变（同一算术的纯重定时）。转 S_DR
 *                 末拍的推进/装载为哑写（命令接受沿重装；命令接受沿的
 *                 want2_r 由 cmd 总线直算——OOC 输入端口无输入延迟约束，
 *                 B1 整合时按真实 input delay 复核）。门重跑：M9b + M10
 *                 + B0 v23。
 ************************************************************************/

module yolo_dma_wr #(
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
    // byte source (pulled; source holds data until accepted)
    input  wire               src_valid_i,
    input  wire [7:0]         src_data_i,
    output wire               src_ready_o,
    // AXI4 write master (single id, INCR, 8-byte)
    output wire [ADDR_W-1:0]  awaddr_o,
    output wire [7:0]         awlen_o,     // beats - 1
    output wire [2:0]         awsize_o,    // 3 = 8 bytes
    output wire [1:0]         awburst_o,   // 01 = INCR
    output wire               awvalid_o,
    input  wire               awready_i,
    output wire [63:0]        wdata_o,
    output wire [7:0]         wstrb_o,
    output wire               wlast_o,
    output wire               wvalid_o,
    input  wire               wready_i,
    input  wire               bvalid_i,
    input  wire [1:0]         bresp_i,
    output wire               bready_o
);

    localparam S_IDLE  = 3'd0;
    localparam S_AW    = 3'd1;
    localparam S_W     = 3'd2;
    localparam S_DR    = 3'd3;              // W done, drain pending B
    localparam S_DONE  = 3'd4;

    localparam BURST_INCR = 2'd1;

    reg [2:0]         state_r;
    reg [ADDR_W-1:0]  addr_r;              // next write address
    reg [LEN_W-1:0]   words_r;             // whole words left to write
    reg [LEN_W-1:0]   bytes_r;             // bytes left to pull from src
    reg [7:0]         beats_r;             // W beats left this burst
    reg [63:0]        wbuf_r;              // word assembly shifter
    reg [3:0]         bcnt_r;              // valid bytes in wbuf (0..8)
    reg [3:0]         lo_r;                // first word's low lane bound
                                          // (= head; 0 after/for no head)
    reg [LEN_W-1:0]   aw_cnt_r;            // AW handshakes this command
    reg [LEN_W-1:0]   b_cnt_r;             // B handshakes this command
    reg [9:0]         bnd_r;               // V1.3: beats to the 4KB line
                                          // end, maintained INCREMENTALLY
                                          // (V1.2 recomputed it per cycle
                                          // from addr_r[11:0]; the dma V1.1
                                          // analysis applies identically --
                                          // v20 ooc dma_wr tier owner)
    reg [4:0]         blen_r;              // V1.4: current burst's beat
                                          // count (<= MAX_BURST=16, 5b),
                                          // loaded at AW fire -- the bnd
                                          // settlement runs at the burst's
                                          // LAST W BEAT off this register
                                          // instead of the words_r->beats_w
                                          // min cascade (v21 owner
                                          // words_r->bnd_r -0.634)
    reg [31:0]        want2_r;             // V1.5: min(words_r, MAX_BURST)
                                          // for the NEXT burst, preloaded at
                                          // the previous burst's LAST W BEAT
                                          // (words_r stable since the last AW
                                          // fire) or at command accept (off
                                          // the cmd bus) -- the AW fire edge
                                          // then only resolves
                                          // min(bnd_r, want2_r) (10b) + one
                                          // 32b subtract (v22 owner
                                          // words_r->addr_r -0.581)

    // AW sizing: min(words left, max burst, beats to the 4KB line end).
    // V1.3: bnd is a REGISTER (dma V1.1 mirror) -- loaded at command
    // accept (awaddr is down-aligned to 8B, so bnd = 512 - addr[11:3]);
    // V1.4: the decrement/re-arm settles at each burst's LAST W BEAT off
    // blen_r (the burst's registered beat count), so the bnd update chain
    // reads registers only -- words_r exits it entirely. Burst sequence
    // identical (pure retiming); addr_r plain accumulator.
    // V1.5: min(words_r, MAX_BURST) is likewise a REGISTER (want2_r,
    // loaded at burst end / accept) and the addr_r advance (+blen_r<<3)
    // settles at burst end -- the fire edge reads registers through one
    // 10b compare + one 32b subtract only.
    wire [31:0] cmd_words_w  = ({8'd0, cmd_len_i} + {29'd0, cmd_addr_i[2:0]}
                                + 32'd7) >> 3;
    wire [31:0] beats_w     = ({22'd0, bnd_r} < want2_r) ? {22'd0, bnd_r}
                                                        : want2_r;
    wire        aw_fire_w   = (state_r == S_AW) && awready_i;
    wire [31:0] words_next_w = words_r - beats_w;

    // word sendable: full word, or command-drained tail (any state's
    // bytes_r==0 with a partial word staged); W fire only in S_W
    wire       word_full_w  = (bcnt_r == 4'd8);
    wire       tail_word_w  = (bytes_r == {LEN_W{1'b0}}) && (bcnt_r != 4'd0);
    wire       w_fire_w     = (state_r == S_W) && wready_i
                              && (word_full_w || tail_word_w);
    wire       burst_last_w = (beats_r == 8'd1);   // this beat ends the burst
    // source accept: room in wbuf AND bytes owed. Mutually exclusive
    // with w_fire by construction (w_fire needs bcnt==8 or bytes_r==0;
    // both block src) -- no same-cycle write/clear conflict exists.
    wire       src_fire_w   = src_valid_i && src_ready_o;

    // 单时钟块：FSM + 字节装配器合并。装配与状态无关地吸收源字节
    // （S_AW/S_W/S_DR 期间预装下一字，W 通道按字粒度推进）；发送与
    // 装配同拍互斥（见上），末字发完后仅在 S_DR 等发一收一的 B 计数
    // 对齐（B 接受为状态无关独立计数，不挡 AW/W 引擎）。
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state_r       <= S_IDLE;
            addr_r        <= {ADDR_W{1'b0}};
            words_r       <= {LEN_W{1'b0}};
            bytes_r       <= {LEN_W{1'b0}};
            beats_r       <= 8'd0;
            wbuf_r        <= 64'd0;
            bcnt_r        <= 4'd0;
            lo_r          <= 4'd0;
            aw_cnt_r      <= {LEN_W{1'b0}};
            b_cnt_r       <= {LEN_W{1'b0}};
            bnd_r         <= 10'd512;
            blen_r        <= 5'd0;
            want2_r       <= 32'd0;   // primed at command accept
        end else begin
            // ---- 字节装配器（所有状态）：源字节 k -> lane k（小端） ----
            if (src_fire_w) begin
                bytes_r <= bytes_r - 1;
                wbuf_r[{bcnt_r[2:0], 3'b000} +: 8] <= src_data_i;
                bcnt_r  <= bcnt_r + 4'd1;
            end
            // ---- W 发送（与装配互斥） ----
            if (w_fire_w) begin
                bcnt_r  <= 4'd0;           // word consumed
                lo_r    <= 4'd0;           // head lanes only in word 0
                beats_r <= beats_r - 8'd1;
                if (burst_last_w) begin
                    // 本突发末拍（必带 WLAST）：命令未尽 -> 下一 AW；
                    // 尽 -> 排空 B
                    if (words_r == {LEN_W{1'b0}}) begin
                        state_r <= S_DR;
                    end else begin
                        state_r <= S_AW;
                    end
                    // V1.4: 边界结算移至突发末拍——读 blen_r（5b 寄存）
                    // 与 bnd_r 作 10 位等值/减法，words_r 完全退出 bnd
                    // 更新链（转 S_DR 时的结算是哑写，下一命令接受沿
                    // 重装，无影响）
                    bnd_r  <= (bnd_r == {5'd0, blen_r}) ? 10'd512
                             : (bnd_r - {5'd0, blen_r});
                    // V1.5: 下一突发 AW 参数末拍预计算——words_r 自上次
                    // AW 发火起稳定（≥1 拍），addr_r/blen_r 全突发稳定：
                    // 单 24 位比较 + 单 32 位进位链。转 S_DR 时为哑写
                    // （命令接受沿重装）。
                    addr_r  <= addr_r + {24'd0, blen_r, 3'b000};
                    want2_r <= (words_r > MAX_BURST) ? MAX_BURST : words_r;
                end
            end
            // ---- done 单拍脉冲返回空闲 ----
            if (state_r == S_DONE) begin
                state_r <= S_IDLE;
            end
            // ---- 命令接受（清装配器与收发计数：上一命令必已拉空且 B 已收齐） ----
            // V1.2: cmd_addr 任意字节对齐——awaddr 下对齐 8B，装配从 head
            // lane 起（源字节 k -> 首 word lane head+k），首字 wstrb 掩 head；
            // 覆盖字数 = ceil((head+len)/8)。head=0 时与 V1.1 逐位等价。
            if ((state_r == S_IDLE) && cmd_valid_i) begin
                addr_r       <= {cmd_addr_i[ADDR_W-1:3], 3'b000};
                words_r      <= cmd_words_w[LEN_W-1:0];
                // V1.5: 首突发 want2 由 cmd 总线直算（OOC 输入端口无
                // 输入延迟约束；B1 整合时按真实 input delay 复核）
                want2_r      <= (cmd_words_w > MAX_BURST) ? MAX_BURST
                                                          : cmd_words_w;
                bytes_r      <= cmd_len_i;
                bcnt_r       <= {1'b0, cmd_addr_i[2:0]};
                lo_r         <= {1'b0, cmd_addr_i[2:0]};
                aw_cnt_r     <= {LEN_W{1'b0}};
                b_cnt_r      <= {LEN_W{1'b0}};
                // V1.3: awaddr 下对齐 8B，[11:3] 即线内 beat 序号
                bnd_r        <= 10'd512 - {1'b0, cmd_addr_i[11:3]};
                state_r      <= S_AW;
            end
            // ---- AW 发起 ----
            if (aw_fire_w) begin
                beats_r      <= beats_w[7:0];
                blen_r       <= beats_w[4:0];   // V1.4: 供突发末拍结算
                // V1.5: addr_r 推进移至突发末拍（+blen_r<<3，读两个全
                // 突发稳定的寄存器）——发火沿不再串 min 级联+32 位加法
                words_r      <= words_next_w[LEN_W-1:0];
                aw_cnt_r     <= aw_cnt_r + 1'b1;
                // V1.4: 边界结算移至本突发末拍（见 W 发送块）——AW 发火
                // 沿不再读 words_r->beats_w 级联更新 bnd_r
                state_r      <= S_W;
            end
            // ---- B 接受（状态无关独立计数：发一收一；多突发命令的
            //      B 与后续 AW/W 重叠到达也不丢——与 S_DR 对齐判定解耦） ----
            if (bvalid_i && bready_o) begin
                b_cnt_r <= b_cnt_r + 1'b1;
            end
            // ---- S_DR：W 已发完，等 B 计数对齐（末 B 握手次拍生效） ----
            if ((state_r == S_DR) && (b_cnt_r == aw_cnt_r)) begin
                state_r <= S_DONE;
            end
        end
    end

    // outputs: combinational on registered state only
    assign cmd_ready_o = (state_r == S_IDLE);
    assign done_o      = (state_r == S_DONE);
    assign src_ready_o = (bytes_r != {LEN_W{1'b0}}) && (bcnt_r != 4'd8);
    assign awaddr_o    = addr_r;
    assign awlen_o     = beats_w[7:0] - 8'd1;
    assign awsize_o    = 3'd3;
    assign awburst_o   = BURST_INCR;
    assign awvalid_o   = (state_r == S_AW);
    // wstrb: lanes [lo_r, bcnt) valid. lo_r = head lanes of word 0 only
    // (cleared at the first w_fire); 9-bit intermediate so bcnt=8 masks
    // cleanly. lo=0 reproduces the V1.1 expression exactly.
    wire [8:0] strb_w = ((bcnt_r == 4'd8) ? 9'h1FF
                        : ((9'd1 << bcnt_r) - 9'd1))
                        & ~((9'd1 << lo_r) - 9'd1);
    assign wdata_o     = wbuf_r;
    assign wstrb_o     = strb_w[7:0];
    assign wlast_o     = (state_r == S_W) && burst_last_w;
    assign wvalid_o    = (state_r == S_W) && (word_full_w || tail_word_w);
    assign bready_o    = 1'b1;   // single id, in-order: accept B whenever offered

    // bresp_i unused: the gate BFM asserts OKAY; slaves that error would
    // be a board-level integration concern (M13), tracked there.

endmodule
