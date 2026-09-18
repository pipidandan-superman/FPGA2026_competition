/************************************************************************
 * File Name       : yolo_gemm_array.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_gemm_array
 * Description     : Manual step 3b/4 -- parameterized TO x TN GEMM array
 *                   (broadcast outer product, NOT systolic) built from
 *                   the gated yolo_mac_cell grid, plus the ONE shared
 *                   yolo_gemm_tail (per-PE tails forbidden).
 *
 *   Array organization (GEMM manual section 4):
 *     - weight broadcast along the row (one OC per row),
 *       activation pair broadcast down the column pair (two N lanes);
 *     - unit-debug tier TO=4/TN=4 (8 DSP), baseline 8x16 (64 DSP),
 *       parameterized 16x16 (128 DSP) -- same RTL, elaboration only;
 *     - shared K/OC/N counters (section 11): NO per-PE counters.
 *
 *   Tile FSM (section 5): IDLE -> [WAIT] -> ISSUE -> DRAIN_PE ->
 *     TAIL -> DONE. K > Kc arrives as consecutive blocks on the blk
 *     port: first block carries first_k (accumulator init), last
 *     block carries last_k (done + tail); intermediate blocks keep
 *     the accumulator (resume semantics, run03 A2). Bias/M/shift are
 *     applied ONCE in the tail after ALL blocks (section 8).
 *
 *   DRAIN_PE leave: last block waits the AND of acc_done over valid
 *     rows; intermediate blocks have no last_k and therefore no done
 *     pulse -- they leave on the fixed 4-cycle product drain (the
 *     same >=4 idle beats the clr precondition uses).
 *
 *   Tail readout (section 7): single-accumulator tile, outputs
 *     serialized oc-major/n-minor through the shared tail, R=1.
 *     Row-invalid cells never issue; lane-masked outputs never
 *     publish (their accumulator lanes hold stale content which is
 *     never read out). TAILW leaves when the presented-y beat count
 *     reaches the tile's valid-output total: a masked tile's last y
 *     beat can land BEFORE TAILW is entered, so a level wait on
 *     y_last would miss the pulse (run06 dbg).
 *
 *   W/X buffers: FUNCTIONAL ③-tier register arrays with loader write
 *     ports (absolute k index, full P_KMAX depth so multi-block
 *     resume needs no reload). The real bank/ping-pong organization
 *     is gate G2 and replaces these arrays -- the cell/tail/FSM
 *     contract above is what ③④ freeze.
 * Dependencies    : yolo_mac_cell.sv (level-2), yolo_gemm_tail.sv (③a)
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release (manual steps 3b/4).
 *   - V1.1 (2026-09-19) by LSL : TAILW deadlock fix -- exit on y-beat
 *     count (ycnt >= n_valid_cnt) instead of level wait on y_last,
 *     which a masked tile's early tail beat can outrun.
 ************************************************************************/

module yolo_gemm_array #(
    parameter integer P_TO    = 4,     //OC 行数（tile 内）
    parameter integer P_TN    = 4,     //N 列数（偶数，lane 对 = P_TN/2）
    parameter integer P_KMAX  = 2304   //③ 功能缓冲深度（G2 换真 bank 机构）
) (
    input  wire               clk_i,
    input  wire               rst_i,        //同步复位：FSM 回 IDLE，击杀在飞
    // ---- block/tile job（§5：K>Kc 由连续 block 组成）----
    input  wire               blk_valid_i,  //IDLE/WAIT 态接受
    input  wire        [12:0] blk_len_i,    //本块 k 数（>=1，和 <= P_KMAX）
    input  wire               blk_first_i,  //tile 首块（first_k 域）
    input  wire               blk_last_i,   //tile 末块（last_k/done/tail 域）
    // ---- tile 常量（首块锁存）----
    input  wire [P_TO-1:0]    row_valid_i,  //OC 行有效掩码（至少 1 行）
    input  wire [P_TN-1:0]    n_mask_i,     //N lane 掩码（至少 1 lane）
    input  wire               act_en_i,     //1=LUT，0=线性旁路
    // ---- W/X 功能缓冲写口（加载器/TPG 空闲时装载，绝对 k 索引）----
    input  wire               w_we_i,
    input  wire  [$clog2(P_TO)-1:0]   w_row_i,
    input  wire  [11:0]              w_k_i,
    input  wire signed [7:0]         w_wd_i,
    input  wire               x_we_i,
    input  wire  [$clog2(P_TN)-1:0]  x_col_i,
    input  wire  [11:0]              x_k_i,
    input  wire signed [7:0]         x_wd_i,
    // ---- per-OC 参数（tile 锁定：TB 在 tile 间隙写）----
    input  wire               p_we_i,
    input  wire  [$clog2(P_TO)-1:0]  p_row_i,
    input  wire signed [31:0]        p_bias_i,   //bias_eff（含首层修正，尾一次性）
    input  wire signed [31:0]        p_m_i,      //M
    input  wire        [5:0]         p_sh_i,     //shift 0..62
    // ---- SiLU LUT（透传共享尾）----
    input  wire               lut_we_i,
    input  wire        [7:0]  lut_wa_i,
    input  wire        [7:0]  lut_wd_i,
    // ---- issue 控制 ----
    input  wire               stall_i,      //ISSUE 态插空拍（XBUF 抖动模型）
    // ---- 输出 ----
    output wire               blk_done_o,   //脉冲：非末块排空完成（acc 保留）
    output wire               tile_done_o,  //脉冲：末块+尾全部完成
    output wire               busy_o,
    output wire               y_valid_o,
    output wire signed [7:0]  y_o,
    output wire  [$clog2(P_TO)-1:0] y_row_o,
    output wire  [$clog2(P_TN)-1:0] y_col_o
);

    localparam integer P_NPC = P_TN / 2;      //lane 对数

    // ---- FSM（三 always 风格，§5）----
    localparam [2:0] S_IDLE = 3'd0,
                     S_WAIT = 3'd1,   //块间等待下一 block
                     S_ISSUE= 3'd2,
                     S_DRAIN= 3'd3,   //DRAIN_PE
                     S_TAIL = 3'd4,   //尾读出（oc 主序/n 次序）
                     S_TAILW= 3'd5;   //等尾流水排空（y_last 对齐 tile_done）

    reg [2:0]  state, state_nx;
    reg [12:0] blk_len_lat;
    reg        blk_first_lat, blk_last_lat;
    reg [11:0] k_base;
    reg [12:0] k_cnt;
    reg [12:0] dcnt;                        //中间块 4 拍排空计数
    reg [8:0]  ti;                          //尾读出元素指针 (r,n) 展平
    reg [8:0]  fc;                          //已喂尾的有效元素计数
    reg [8:0]  n_valid_cnt;                 //tile 有效输出总数（首块锁存时算）
    reg [8:0]  ycnt;                        //已呈现 y 拍计数（TAILW 离开判据）
    reg [P_TO-1:0] row_valid_lat;
    reg [P_TN-1:0] n_mask_lat;
    reg        act_lat;

    reg        blk_done_r, tile_done_r;
    wire       cells_done;                 //DRAIN_PE 离开条件（末块，后接赋值）
    wire       tail_y_last;                //尾末元素标记（后接端口连接）
    wire       tail_feed_v;                //尾喂使能（后接赋值）
    wire       tail_y_valid;               //尾 y 拍有效（后接端口连接）

    // ---- W/X 功能缓冲（③档；G2 换真 bank）----
    reg signed [7:0] W_buf [0:P_TO-1][0:P_KMAX-1];
    reg signed [7:0] X_buf [0:P_TN-1][0:P_KMAX-1];

    always @(posedge clk_i) begin
        if (w_we_i) W_buf[w_row_i][w_k_i] <= w_wd_i;
        if (x_we_i) X_buf[x_col_i][x_k_i] <= x_wd_i;
    end

    // ---- per-OC 参数 ----
    reg signed [31:0] pb [0:P_TO-1];
    reg signed [31:0] pm [0:P_TO-1];
    reg        [5:0]  ps [0:P_TO-1];
    always @(posedge clk_i)
        if (p_we_i) begin
            pb[p_row_i] <= p_bias_i;
            pm[p_row_i] <= p_m_i;
            ps[p_row_i] <= p_sh_i;
        end

    // ---- 有效输出总数（tile 常量掩码的 popcount，首块锁存）----
    function [8:0] popcnt_masks(input [P_TO-1:0] rv, input [P_TN-1:0] nm);
        integer rr, nn;
        reg [8:0] cnt;
        begin
            cnt = 9'd0;
            for (rr = 0; rr < P_TO; rr = rr + 1)
                if (rv[rr])
                    for (nn = 0; nn < P_TN; nn = nn + 1)
                        if (nm[nn])
                            cnt = cnt + 9'd1;
            popcnt_masks = cnt;
        end
    endfunction

    // ---- 发射门控 ----
    wire issue_v = (state == S_ISSUE) && !stall_i;
    wire [11:0] k_abs = k_base + k_cnt[11:0];

    wire acc_accept = blk_valid_i &&
                      ((state == S_IDLE) || (state == S_WAIT));

    // ---- 次态 ----
    always @* begin
        state_nx = state;
        case (state)
            S_IDLE:   if (acc_accept)          state_nx = S_ISSUE;
            S_WAIT:   if (acc_accept)          state_nx = S_ISSUE;
            S_ISSUE:  if (issue_v && (k_cnt == blk_len_lat - 13'd1))
                                          state_nx = S_DRAIN;
            S_DRAIN:  if (blk_last_lat ? cells_done : (dcnt == 13'd3))
                                          state_nx = blk_last_lat ? S_TAIL : S_WAIT;
            S_TAIL:   if (ti == P_TO*P_TN - 1) state_nx = S_TAILW;
            S_TAILW:  if (ycnt >= n_valid_cnt) state_nx = S_IDLE;
            default:  state_nx = S_IDLE;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            blk_done_r  <= 1'b0;
            tile_done_r <= 1'b0;
        end else begin
            state <= state_nx;
            // 输出脉冲（done 事件即消费，非粘滞）
            blk_done_r  <= (state == S_DRAIN) && (state_nx == S_WAIT);
            tile_done_r <= (state == S_TAILW) && (state_nx == S_IDLE);
            case (state)
                S_IDLE, S_WAIT: if (acc_accept) begin
                    blk_len_lat   <= blk_len_i;
                    blk_first_lat <= blk_first_i;
                    blk_last_lat  <= blk_last_i;
                    k_cnt         <= 13'd0;
                    dcnt          <= 13'd0;
                    if (state == S_IDLE) begin
                        //首块：锁存 tile 常量
                        row_valid_lat <= row_valid_i;
                        n_mask_lat    <= n_mask_i;
                        act_lat       <= act_en_i;
                        k_base        <= 12'd0;
                        n_valid_cnt   <= popcnt_masks(row_valid_i, n_mask_i);
                        fc            <= 9'd0;
                        ti            <= 9'd0;
                        ycnt          <= 9'd0;
                    end else begin
                        //续块：k 基址前移本块长度
                        k_base        <= k_base + blk_len_lat[11:0];
                    end
                end
                S_ISSUE: if (issue_v)
                    k_cnt <= k_cnt + 13'd1;
                S_DRAIN:
                    dcnt <= dcnt + 13'd1;
                S_TAIL: begin
                    ti <= ti + 9'd1;
                    if (tail_feed_v)
                        fc <= fc + 9'd1;
                end
                default: ;
            endcase
            // y 拍计数：任意态都可能呈现（掩码 tile 尾拍早于 TAILW 进入，
            // 电平等待会错过脉冲——改计数值判定，对拍序不敏感）
            if (tail_y_valid)
                ycnt <= ycnt + 9'd1;
        end
    end

    // ---- MAC 网格：行广播 w，列对广播 x ----
    wire signed [P_TO*P_TN-1:0][31:0] acc_flat;  //展平 (r,n) 累加器读出（打包向量）
    wire [P_TO-1:0]    row_done_w;

    genvar r, c;
    generate
        for (r = 0; r < P_TO; r = r + 1) begin : grow
            wire [P_NPC-1:0] cdone;
            for (c = 0; c < P_NPC; c = c + 1) begin : gcol
                yolo_mac_cell u_cell (
                    .clk_i       (clk_i),
                    .rst_i       (rst_i),
                    .clr_i       (1'b0),          //阵列生命周期用 fk 重置 + rst 击杀
                    .in_valid_i  (issue_v & row_valid_lat[r]),
                    .w_i         (W_buf[r][k_abs]),
                    .x0_i        (X_buf[2*c  ][k_abs]),
                    .x1_i        (X_buf[2*c+1][k_abs]),
                    .lane_mask_i (n_mask_lat[2*c +: 2]),
                    .first_k_i   (issue_v & row_valid_lat[r] &&
                                  (k_cnt == 13'd0) && blk_first_lat),
                    .last_k_i    (issue_v & row_valid_lat[r] &&
                                  (k_cnt == blk_len_lat - 13'd1) && blk_last_lat),
                    .acc0_o      (acc_flat[r*P_TN + 2*c    ]),
                    .acc1_o      (acc_flat[r*P_TN + 2*c + 1]),
                    .acc_done_o  (cdone[c])
                );
            end
            assign row_done_w[r] = &cdone;
        end
    endgenerate

    // DRAIN_PE 离开条件（末块）：有效行的 done 全体与
    assign cells_done = &((row_done_w & row_valid_lat) | ~row_valid_lat);

    // ---- 尾读出选路（oc 主序 / n 次序，R=1）----
    wire [8:0] ti_r = ti / P_TN;                   //常除（参数）
    wire [8:0] ti_n = ti - ti_r * P_TN;
    wire       el_valid = row_valid_lat[ti_r[$clog2(P_TO)-1:0]] &&
                          n_mask_lat[ti_n[$clog2(P_TN)-1:0]];
    assign tail_feed_v = (state == S_TAIL) && el_valid;
    wire       tail_in_last = tail_feed_v && (fc == n_valid_cnt - 9'd1);

    // 坐标三拍对齐（捕获于喂拍，与尾 valid 同相呈现）
    reg [$clog2(P_TO)-1:0] yr1, yr2, yr3;
    reg [$clog2(P_TN)-1:0] yn1, yn2, yn3;
    always @(posedge clk_i) begin
        yr1 <= ti_r[$clog2(P_TO)-1:0];
        yn1 <= ti_n[$clog2(P_TN)-1:0];
        yr2 <= yr1; yn2 <= yn1;
        yr3 <= yr2; yn3 <= yn2;
    end

    // ---- 共享尾（每阵列一个，§8 全链）----
    wire signed [31:0] sel_acc  = $signed(acc_flat[ti_r*P_TN + ti_n]);
    wire signed [31:0] sel_bias = pb[ti_r[$clog2(P_TO)-1:0]];
    wire signed [31:0] sel_m    = pm[ti_r[$clog2(P_TO)-1:0]];
    wire        [5:0]  sel_sh  = ps[ti_r[$clog2(P_TO)-1:0]];

    wire signed [7:0]  tail_y;

    yolo_gemm_tail #(.R(1)) u_tail (
        .clk_i      (clk_i),
        .rst_i      (rst_i),
        .in_valid_i (tail_feed_v),
        .in_last_i  (tail_in_last),
        .acc_i      (sel_acc),
        .bias_i     (sel_bias),
        .m_i        (sel_m),
        .sh_i       (sel_sh),
        .act_en_i   (act_lat),
        .y_valid_o  (tail_y_valid),
        .y_last_o   (tail_y_last),
        .y_o        (tail_y),
        .lut_we_i   (lut_we_i),
        .lut_wa_i   (lut_wa_i),
        .lut_wd_i   (lut_wd_i)
    );

    assign y_valid_o = tail_y_valid;
    assign y_o       = tail_y;
    assign y_row_o   = yr3;
    assign y_col_o   = yn3;
    assign blk_done_o  = blk_done_r;
    assign tile_done_o = tile_done_r;
    assign busy_o      = (state != S_IDLE);

endmodule
