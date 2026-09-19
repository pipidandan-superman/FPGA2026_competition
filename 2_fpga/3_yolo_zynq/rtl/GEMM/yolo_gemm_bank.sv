/************************************************************************
 * File Name       : yolo_gemm_bank.sv
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_gemm_bank
 * Description     : G2/V3 dual-group wide-word operand bank -- Block
 *                   Memory Generator IP storage (2026-09-19 hard IP
 *                   mandate: all memory is real Vivado IP, no
 *                   internal parameterized memory expression).
 *
 *   Organization (manual section 6 / board plan section 2, converged
 *   2026-09-19): one wide word per k -- W word 64 bits (one byte per
 *   OC row, row-broadcast source), X word 128 bits (one byte per N
 *   column). TWO independent physical groups per operand, block-
 *   granular ping-pong: while one group is loaded the other is read.
 *
 *   WIDTHS ARE FIXED at the approved G2 baseline 8x16 (W 64b / X
 *   128b) because a generated IP is fixed at generation time; the
 *   former P_TO/P_TN width generics are hereby retired in this
 *   module (array/feeder stay parametric; small-shape control
 *   coverage moves to small logical-Kc runs at 8x16). Physical depth
 *   1024 (BMG generation depth); the logical Kc of a block is proven
 *   by its load length (<= 1024) and lives in the load order.
 *
 *   Load port (streaming, 64b per beat -- the HP beat width):
 *     - W beat  : one full W word, writes group ld_w_grp at wk_cnt;
 *     - X beat  : HALF an X word (wr_x_hi_i picks the 64b half); the lo
 *       half is captured, the hi half completes the 128b word -> one
 *       128b write at xk_cnt with per-byte enables (hi lanes from the
 *       current beat, lo lanes from the captured half -- lane-disjoint
 *       byte-enable merge, R6). The merge regs are control logic, the
 *       128b storage access itself is one BMG write;
 *     - 8x8b lane write enables per beat (wr_be_i): disabled lanes keep
 *       old content (merge semantics, R6);
 *     - wr_first/wr_last delimit one load block; per-operand word
 *       counts are latched (ld_w_len/ld_x_len, ld_done pulse) and the
 *       per-group "loaded" flags update (cleared at the operand's first
 *       beat of a block, set at wr_last if that operand saw words).
 *
 *   Read side (driven by yolo_gemm_feeder): ONE address+ren per operand;
 *   the bank ROUTS it internally to the rgrp-selected group only -- the
 *   deselected group's port-B never issues a read, and the loader only
 *   ever targets ld_ok groups (= not read-selected), so a given
 *   physical BMG never sees a port-A write and a port-B read in the
 *   same window: the TDP same-address collision is structurally
 *   excluded (project rule; TB is under the same discipline). Both
 *   groups' dout are exposed un-muxed -- the exit-stage group MUX
 *   lives in the feeder. Read latency is ONE cycle (BMG primitive
 *   output register disabled): address/ren in cycle C -> dout valid in
 *   C+1, dout HOLDS while en is low -- identical to the V1 register
 *   array, so the feeder contract (address leads two beats) is
 *   untouched.
 *
 *   Instrumentation: sticky bank_err_o (never gates the datapath) on
 *   (1) X hi-half beat with no pending lo half, (2) a read enable issued
 *   to a group whose load block is in flight (defensive -- unreachable
 *   through the feeder's loaded-gating, kept as a G4 integration trip).
 * Dependencies    : blk_mem_gen IP gemm_bm_w_g0/g1 (TDP 64x1024),
 *                   gemm_bm_x_g0/g1 (TDP 128x1024)
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : run09 register-array version.
 *   - V1.1 (2026-09-19) by LSL : wr_first first-beat write-address
 *     combinational bypass (w_wa) -- run09 v2 lesson.
 *   - V2.0 (2026-09-19) by LSL : storage -> 4 BMG IP instances, widths
 *     fixed at G2 baseline (64/128 x 1024), width/depth generics
 *     retired. User IP mandate redo -- gate evidence run11/run12.
 *   - V2.0.1 (2026-09-19) by LSL : x_final first-beat combinational
 *     bypass (x_wa, symmetric to w_wa) -- W-only len=1 block close
 *     read stale xk_cnt from the previous block; caught by run11
 *     Phase B random (ld_x_len=stale, expected 0).
 ************************************************************************/
module yolo_gemm_bank (
    input  wire               clk_i,
    input  wire               rst_i,        //同步复位：计数/标志/仪器清零（RAM 内容不清）
    // ---- 流式装载写口（64b/拍）----
    input  wire               wr_valid_i,
    output wire               wr_ready_o,   //目标组安全（非读选中）即收
    input  wire        [63:0] wr_data_i,
    input  wire               wr_is_x_i,    //0=W 整字拍 / 1=X 半字拍
    input  wire               wr_x_hi_i,    //X 半字选择：0=lane0..7 / 1=lane8..15
    input  wire        [7:0]  wr_be_i,      //本拍 64b 内 8×8b lane 写使能
    input  wire               wr_first_i,   //装载块首拍（计数清零）
    input  wire               wr_last_i,    //装载块末拍（块长收口+组 loaded）
    input  wire               ld_w_grp_i,   //W 装载目标组（块级准静态）
    input  wire               ld_x_grp_i,   //X 装载目标组
    input  wire               rd_busy_i,    //feeder 读侧在飞（流未排空：S_STREAM∥v1∥v2）
    // ---- 装载状态出口 ----
    output wire        [1:0]  w_ld_ok_o,    //W 组可装载 = 非读选组，或读侧已完全排空
    output wire        [1:0]  x_ld_ok_o,
    output wire        [1:0]  w_loaded_o,   //组已装载（最近一次装载块收口且该算子有字）
    output wire        [1:0]  x_loaded_o,
    output wire        [12:0] ld_w_len_o,   //wr_last 收口的 W 字数
    output wire        [12:0] ld_x_len_o,   //wr_last 收口的 X 字数
    output wire               ld_done_o,    //脉冲：装载块收口拍
    // ---- 读侧（feeder 驱动；组内路由，未选组 B 口静止）----
    input  wire               w_rgrp_i,
    input  wire        [12:0] w_raddr_i,
    input  wire               w_ren_i,
    output wire        [63:0] w_dout_g0_o,  //两组 dout 都露出（出口级组 MUX 在 feeder）
    output wire        [63:0] w_dout_g1_o,
    input  wire               x_rgrp_i,
    input  wire        [12:0] x_raddr_i,
    input  wire               x_ren_i,
    output wire       [127:0] x_dout_g0_o,
    output wire       [127:0] x_dout_g1_o,
    // ---- 仪器 ----
    output wire               bank_err_o    //粘滞：协议/纪律违约（只报警不门控）
);

    // ---- 装载块状态 ----
    reg [12:0] wk_cnt, xk_cnt;          //块内已写完整字数（W 整拍即计；X hi 拍才计）
    reg        x_lo_pend;               //X lo 半字已捕获待 hi
    reg [63:0] x_lo_tmp;                //X lo 半字数据（原始，不施加 be）
    reg [7:0]  x_be_tmp;                //X lo 半字 be
    reg        blk_lding;               //装载块在飞（wr_first 后未收口）
    reg [1:0]  w_loaded, x_loaded;
    reg [12:0] ld_w_len_r, ld_x_len_r;
    reg        ld_done_r;
    reg        bank_err_r;

    // ---- 写口流控：组安全 = 非读选组，或读侧在飞已完全排空 ----
    // （busy 覆盖整个字流窗口含停拍：停拍时 ren 已冷但 v1/v2/流未收，
    //   此时放行会在恢复读时与装载写形成同址 TDP 冲突——结构性禁止）
    assign w_ld_ok_o[0] = w_rgrp_i ? 1'b1 : ~rd_busy_i;
    assign w_ld_ok_o[1] = w_rgrp_i ? ~rd_busy_i : 1'b1;
    assign x_ld_ok_o[0] = x_rgrp_i ? 1'b1 : ~rd_busy_i;
    assign x_ld_ok_o[1] = x_rgrp_i ? ~rd_busy_i : 1'b1;
    assign wr_ready_o = wr_valid_i
                        ? (wr_is_x_i ? x_ld_ok_o[ld_x_grp_i] : w_ld_ok_o[ld_w_grp_i])
                        : 1'b1;
    wire wr_acc = wr_valid_i && wr_ready_o;

    // 收口字数（组合终值：本拍若是整字完成拍则 +1）
    // 首拍写地址旁路（run09 v2 教训）：wr_first 拍对计数器的清零是 NBA，
    // 本拍的写访问与长度收口必须组合取 0 —— 否则首字写到上一块的终址、
    // len=1 的 W-only 块（first=last 同拍）会锁出 stale+1 的错长度。
    // X 侧旁路（run11 教训，V2.0.1）：X 写址确实不需要（hi 半字写总在
    // 本块首拍之后 >=1 拍），但 W-only len=1 块（first=last 同拍）的收口
    // 读 xk_cnt —— 本块无 X 字、首拍清零未落地，会锁出上一块的残留 X
    // 计数。与 w_wa 同构，收口组合取 0。
    wire [12:0] w_wa = wr_first_i ? 13'd0 : wk_cnt;
    wire [13:0] w_final = w_wa + ((wr_acc && !wr_is_x_i) ? 14'd1 : 14'd0);
    wire [12:0] x_wa = wr_first_i ? 13'd0 : xk_cnt;
    wire [13:0] x_final = x_wa +
                          ((wr_acc && wr_is_x_i && wr_x_hi_i) ? 14'd1 : 14'd0);

    // ---- 装载写 + 块状态 + 仪器（存储访问全部经 BMG 端口）----
    always @(posedge clk_i) begin
        if (rst_i) begin
            wk_cnt      <= 13'd0;
            xk_cnt      <= 13'd0;
            x_lo_pend   <= 1'b0;
            blk_lding   <= 1'b0;
            w_loaded    <= 2'b00;
            x_loaded    <= 2'b00;
            ld_w_len_r  <= 13'd0;
            ld_x_len_r  <= 13'd0;
            ld_done_r   <= 1'b0;
            bank_err_r  <= 1'b0;
        end else begin
            ld_done_r <= 1'b0;          //单拍脉冲
            if (wr_acc) begin
                if (wr_first_i) begin
                    wk_cnt    <= 13'd0;
                    xk_cnt    <= 13'd0;
                    x_lo_pend <= 1'b0;
                    blk_lding <= 1'b1;
                    //已接受的 first 打到未收口块上=流协议违约
                    //（仅被反压等待的 first 合法：握手挂起，未发生访问）
                    if (blk_lding)
                        bank_err_r <= 1'b1;
                end
                if (!wr_is_x_i) begin
                    // ---- W 整字拍：BMG 64b 字节 WE 写 ----
                    if (wr_first_i)
                        w_loaded[ld_w_grp_i] <= 1'b0;  //数据换血，先失效
                    wk_cnt <= w_wa + 13'd1;   //首拍=0+1，其余=计数值+1
                end else if (!wr_x_hi_i) begin
                    // ---- X lo 半字拍：捕获 ----
                    if (wr_first_i)
                        x_loaded[ld_x_grp_i] <= 1'b0;
                    x_lo_tmp   <= wr_data_i;
                    x_be_tmp   <= wr_be_i;
                    x_lo_pend  <= 1'b1;
                end else begin
                    // ---- X hi 半字拍：两半合并成一次 128b 字节 WE 写 ----
                    x_lo_pend <= 1'b0;
                    xk_cnt    <= wr_first_i ? 13'd1 : xk_cnt + 13'd1;
                    // 协议：hi 必须紧跟自己的 lo
                    if (!x_lo_pend)
                        bank_err_r <= 1'b1;
                end
                if (wr_last_i) begin
                    blk_lding  <= 1'b0;
                    ld_w_len_r <= w_final[12:0];
                    ld_x_len_r <= x_final[12:0];
                    if (w_final != 14'd0)
                        w_loaded[ld_w_grp_i] <= 1'b1;
                    if (x_final != 14'd0)
                        x_loaded[ld_x_grp_i] <= 1'b1;
                    ld_done_r  <= 1'b1;
                end
            end
            // 防御（经 feeder 门控结构性不可达）：装载中的组被读使能
            if (blk_lding && w_ren_i && (w_rgrp_i == ld_w_grp_i))
                bank_err_r <= 1'b1;
            if (blk_lding && x_ren_i && (x_rgrp_i == ld_x_grp_i))
                bank_err_r <= 1'b1;
        end
    end

    // ---- 存储：4×BMG IP（TDP，读延迟 1=关 Primitive 输出寄存器）----
    //   例化逐端口对生成 .veo 模板核对（gemm_bm_w_g0/g1.veo：wea[7:0]/
    //   dina[63:0]；gemm_bm_x_g0/g1.veo：wea[15:0]/dina[127:0]）。
    //   写侧组路由：ena 仅目标组点亮（未选组 A 口静止）；
    //   读侧组路由：enb 仅 rgrp 组点亮（未选组 B 口静止，dout 保持）。
    //   单实例因此永不见 A 写/B 读同窗激活——结构性无冲突逐实例成立。
    //   W：A 口 64b 写（字节 WE=wr_be）；X：A 口 128b 写（hi 拍一次，
    //   字节 WE={wr_be, x_be_tmp}，数据={wr_data, x_lo_tmp}）。
    wire [63:0]  wdo0, wdo1;
    wire [127:0] xdo0, xdo1;

    gemm_bm_w_g0 u_w_g0 (
        .clka  (clk_i),
        .ena   (wr_acc && !wr_is_x_i && !ld_w_grp_i),
        .wea   (wr_be_i),
        .addra (w_wa[9:0]),
        .dina  (wr_data_i),
        .douta (),
        .clkb  (clk_i),
        .enb   (w_ren_i && !w_rgrp_i),
        .web   (8'd0),
        .addrb (w_raddr_i[9:0]),
        .dinb  (64'd0),
        .doutb (wdo0)
    );
    gemm_bm_w_g1 u_w_g1 (
        .clka  (clk_i),
        .ena   (wr_acc && !wr_is_x_i &&  ld_w_grp_i),
        .wea   (wr_be_i),
        .addra (w_wa[9:0]),
        .dina  (wr_data_i),
        .douta (),
        .clkb  (clk_i),
        .enb   (w_ren_i &&  w_rgrp_i),
        .web   (8'd0),
        .addrb (w_raddr_i[9:0]),
        .dinb  (64'd0),
        .doutb (wdo1)
    );
    // X 128b 合并写：hi 拍一次（wea 高半=本拍 hi 字节，低半=捕获 lo 字节）
    wire [15:0] x_we = {wr_be_i, x_be_tmp};
    wire [127:0] x_di = {wr_data_i, x_lo_tmp};
    wire x_wr = wr_acc && wr_is_x_i && wr_x_hi_i;

    gemm_bm_x_g0 u_x_g0 (
        .clka  (clk_i),
        .ena   (x_wr && !ld_x_grp_i),
        .wea   (x_we),
        .addra (xk_cnt[9:0]),
        .dina  (x_di),
        .douta (),
        .clkb  (clk_i),
        .enb   (x_ren_i && !x_rgrp_i),
        .web   (16'd0),
        .addrb (x_raddr_i[9:0]),
        .dinb  (128'd0),
        .doutb (xdo0)
    );
    gemm_bm_x_g1 u_x_g1 (
        .clka  (clk_i),
        .ena   (x_wr &&  ld_x_grp_i),
        .wea   (x_we),
        .addra (xk_cnt[9:0]),
        .dina  (x_di),
        .douta (),
        .clkb  (clk_i),
        .enb   (x_ren_i &&  x_rgrp_i),
        .web   (16'd0),
        .addrb (x_raddr_i[9:0]),
        .dinb  (128'd0),
        .doutb (xdo1)
    );

    assign w_dout_g0_o = wdo0;
    assign w_dout_g1_o = wdo1;
    assign x_dout_g0_o = xdo0;
    assign x_dout_g1_o = xdo1;
    assign ld_w_len_o  = ld_w_len_r;
    assign ld_x_len_o  = ld_x_len_r;
    assign ld_done_o   = ld_done_r;
    assign w_loaded_o  = w_loaded;
    assign x_loaded_o  = x_loaded;
    assign bank_err_o  = bank_err_r;

endmodule
