/************************************************************************
 * File Name     : tb_yolo_gemm_array.sv
 * Developer     : LSL
 * Date          : 2026-09-18
 * Module Name   : tb_yolo_gemm_array
 * Description   : 手册③b/④ 阵列门仿真（run06）。参数化 P_TO×P_TN，
 *                 经薄包装分别跑 4×4 / 8×16 / 16×16 三档（同一 TB）。
 *
 *   DUT: rtl/GEMM/yolo_gemm_array.sv（MAC 网格 + §5 分块 FSM + 共享尾）。
 *
 *   期望值来源（GEMM 手册 §14：更宽独立 oracle，永不取自被测公式）：
 *   - INT64 逐元素累加 Σ w[r][k]·x[n][k]（TB 独立乘加，8 位激励域）；
 *   - requant：截断除 + floor 修正 + RNE（与 DUT 移位/掩码法不同构）
 *     + SiLU LUT 图样 A(i^A5) 镜像；
 *   - 输出按 oc 主序/n 次序逐拍对拍（值+坐标+顺序）。
 *
 *   覆盖（§14 阵列档）：K=1/27/32/576/2304、[576×4]/[1152,576,576]/
 *   [1,1,27,1,34] 分块续累、行/列掩码尾（TO−1 行、奇偶 lane）、
 *   issue 停顿、rst 在飞击杀、背靠背 tile、首层大 bias、随机 tile。
 *
 *   继承纪律：每 negedge 驱动、$random 无符号模、X 绷线、
 *   done 事件即消费、守恒 started = done + aborted。
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release.
 ************************************************************************/

`timescale 1ns/1ps

module tb_yolo_gemm_array #(
    parameter integer P_TO = 4,
    parameter integer P_TN = 4
);

    localparam integer KMAX = 2304;
    //随机 tile 数按规模缩放（先声明后使用）
    localparam integer NRAND = (P_TO * P_TN >= 256) ? 8 :
                               ((P_TO * P_TN >= 128) ? 15 : 40);

    // ---- DUT 信号 ----
    reg  clk, rst;
    reg  blk_valid;
    reg  [12:0] blk_len;
    reg  blk_first, blk_last;
    reg  [P_TO-1:0] row_valid;
    reg  [P_TN-1:0] n_mask;
    reg  act_en;
    reg  w_we, x_we;
    reg  [$clog2(P_TO)-1:0] w_row;
    reg  [$clog2(P_TN)-1:0] x_col;
    reg  [11:0] w_k, x_k;
    reg  signed [7:0] w_wd, x_wd;
    reg  p_we;
    reg  [$clog2(P_TO)-1:0] p_row;
    reg  signed [31:0] p_bias, p_m;
    reg  [5:0] p_sh;
    reg  lut_we;
    reg  [7:0] lut_wa, lut_wd;
    reg  stall;
    wire blk_done, tile_done, busy, y_valid;
    wire signed [7:0] y;
    wire [$clog2(P_TO)-1:0] y_row;
    wire [$clog2(P_TN)-1:0] y_col;

    yolo_gemm_array #(.P_TO(P_TO), .P_TN(P_TN), .P_KMAX(KMAX)) dut (
        .clk_i(clk), .rst_i(rst),
        .blk_valid_i(blk_valid), .blk_len_i(blk_len),
        .blk_first_i(blk_first), .blk_last_i(blk_last),
        .row_valid_i(row_valid), .n_mask_i(n_mask), .act_en_i(act_en),
        .w_we_i(w_we), .w_row_i(w_row), .w_k_i(w_k), .w_wd_i(w_wd),
        .x_we_i(x_we), .x_col_i(x_col), .x_k_i(x_k), .x_wd_i(x_wd),
        .p_we_i(p_we), .p_row_i(p_row),
        .p_bias_i(p_bias), .p_m_i(p_m), .p_sh_i(p_sh),
        .lut_we_i(lut_we), .lut_wa_i(lut_wa), .lut_wd_i(lut_wd),
        .stall_i(stall),
        .blk_done_o(blk_done), .tile_done_o(tile_done), .busy_o(busy),
        .y_valid_o(y_valid), .y_o(y),
        .y_row_o(y_row), .y_col_o(y_col)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_d;
    always @(posedge clk) rst_d <= rst;

    // ---- 记账 ----
    integer checks, errors;
    integer tiles_started, tiles_done, tiles_aborted;
    integer exp_blk_done, blk_done_seen;
    integer y_cnt;
    integer stall_en;
    integer eq_wp, eq_rp;
    reg signed [7:0]          eq_y [0:65535];
    reg [$clog2(P_TO)-1:0]    eq_r [0:65535];
    reg [$clog2(P_TN)-1:0]    eq_n [0:65535];
    integer rs1, rs2, rs3, rs4, rs5;
    integer cyc;
    integer blocks_fed;
    integer i, t;
    reg act_exp;            //当前 tile 的 act 镜像（期望 LUT/旁路）
    always @(negedge clk) cyc = cyc + 1;

    // ---- TB 侧镜像（oracle 数据源，永不读 DUT）----
    reg signed [7:0]  Wm [0:P_TO-1][0:KMAX-1];
    reg signed [7:0]  Xm [0:P_TN-1][0:KMAX-1];
    reg signed [31:0] PB [0:P_TO-1];
    reg signed [31:0] PM [0:P_TO-1];
    reg        [5:0]  PS [0:P_TO-1];
    reg        [7:0]  lut_exp [0:255];

    // ---- 独立 requant 模型（截断除 + floor 修正 + RNE，与 DUT 不同构）----
    function [7:0] requant_model(input signed [63:0] a64, input signed [63:0] b64,
                                 input signed [63:0] m64, input [5:0] s);
        reg signed [63:0] p, fl, rr, qn, qs;
        reg        [63:0] mod_u, hh;
        begin
            p = (a64 + b64) * m64;
            if (s == 6'd0) begin
                fl = p; rr = 64'd0;
            end else begin
                mod_u = 64'd1 << s;
                hh   = mod_u >> 1;
                fl = p / $signed(mod_u);
                if ((p < 0) && ((p % $signed(mod_u)) != 0))
                    fl = fl - 1;
                rr = p - fl * $signed(mod_u);
            end
            qn = fl + (((rr > hh) || ((rr == hh) && fl[0])) ? 64'sd1 : 64'sd0);
            qs = (qn > 64'sd127)  ? 64'sd127
               : ((qn < -64'sd128) ? -64'sd128 : qn);
            requant_model = qs[7:0];
        end
    endfunction

    function [7:0] sat_addr(input signed [7:0] q7);
        sat_addr = {~q7[7], q7[6:0]};
    endfunction

    // ---- 检查器：每 negedge 全覆盖（唯一 stall 驱动者）----
    reg signed [7:0] eqt;
    reg [7:0] eadt;
    reg signed [7:0] eexp;
    always @(negedge clk) begin
        stall = stall_en ? ({$random(rs5)} % 4 == 0) : 1'b0;
        if (rst_d) begin
            if (y_valid || blk_done || tile_done) begin
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] done/y during rst", $time);
            end
        end else begin
            if (y_valid) begin
                if (eq_rp >= eq_wp) begin
                    errors = errors + 1;
                    $display("EES_ARR_ERR [%0t] y_valid without expectation", $time);
                end else begin
                    eqt  = eq_y[eq_rp];
                    eadt = sat_addr(eqt);
                    eexp = act_exp ? $signed(lut_exp[eadt]) : eqt;
                    if (^y === 1'bx) begin
                        errors = errors + 1;
                        $display("EES_ARR_ERR [%0t] X on y", $time);
                    end else if (y !== eexp) begin
                        errors = errors + 1;
                        $display("EES_ARR_ERR [%0t] y=%0d want=%0d @(r=%0d n=%0d)",
                                 $time, y, eexp, eq_r[eq_rp], eq_n[eq_rp]);
                    end else if ((y_row !== eq_r[eq_rp]) || (y_col !== eq_n[eq_rp])) begin
                        errors = errors + 1;
                        $display("EES_ARR_ERR [%0t] coord (%0d,%0d) want (%0d,%0d)",
                                 $time, y_row, y_col, eq_r[eq_rp], eq_n[eq_rp]);
                    end else begin
                        checks = checks + 1;
                    end
                    y_cnt = y_cnt + 1;
                    eq_rp = eq_rp + 1;
                end
            end
            if (blk_done)  blk_done_seen = blk_done_seen + 1;
            if (tile_done) begin
                tiles_done = tiles_done + 1;
                if (eq_rp != eq_wp) begin
                    errors = errors + 1;
                    $display("EES_ARR_ERR [%0t] tile_done with %0d unsent expectations",
                             $time, eq_wp - eq_rp);
                end
            end
        end
    end

    // ---- 驱动任务 ----
    task gapn(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    task lut_load_a;        //图样 A：i ^ A5
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                lut_we = 1'b1; lut_wa = i[7:0];
                lut_wd = i[7:0] ^ 8'hA5;
                lut_exp[i] = i[7:0] ^ 8'hA5;
                @(negedge clk);
            end
            lut_we = 1'b0;
        end
    endtask

    reg signed [7:0] cb [0:5];      //角点池
    task fill_wx(input integer K);
        integer kk, ii;
        reg signed [7:0] wv, xv;
        begin
            for (kk = 0; kk < K; kk = kk + 1) begin
                for (ii = 0; ii < ((P_TO > P_TN) ? P_TO : P_TN); ii = ii + 1) begin
                    w_we = 1'b0; x_we = 1'b0;
                    if (ii < P_TO) begin
                    wv = ({$random(rs1)} % 16 == 0) ? cb[{$random(rs2)} % 6]
                        : $signed({$random(rs3)} % 256) - 128;
                        w_wd = wv; w_row = ii[$clog2(P_TO)-1:0]; w_k = kk[11:0];
                        w_we = 1'b1;
                        Wm[ii][kk] = wv;
                    end
                    if (ii < P_TN) begin
                        xv = ({$random(rs2)} % 16 == 0) ? cb[{$random(rs1)} % 6]
                            : $signed({$random(rs4)} % 256) - 128;
                        x_wd = xv; x_col = ii[$clog2(P_TN)-1:0]; x_k = kk[11:0];
                        x_we = 1'b1;
                        Xm[ii][kk] = xv;
                    end
                    @(negedge clk);
                end
            end
            w_we = 1'b0; x_we = 1'b0;
        end
    endtask

    task load_params(input integer big_bias);
        integer r;
        begin
            for (r = 0; r < P_TO; r = r + 1) begin
                p_we = 1'b1; p_row = r[$clog2(P_TO)-1:0];
                if (big_bias) begin
                    p_bias = ({$random(rs1)} % 2) ? 32'sd100000000 : -32'sd100000000;
                    p_m    = 32'sd1;
                    p_sh   = 6'd20;
                end else begin
                    p_bias = $signed({$random(rs2)} % 32'h08000000) - 32'sh04000000;
                    p_m    = ({$random(rs3)} % 4 == 0) ? -32'sh40000000 : 32'sh40000000;
                    if ({$random(rs4)} % 8 == 0) p_m = 32'sd1;
                    p_sh   = {$random(rs1)} % 63;
                end
                PB[r] = p_bias; PM[r] = p_m; PS[r] = p_sh;
                @(negedge clk);
            end
            p_we = 1'b0;
        end
    endtask

    // 计算期望并入队（oc 主序/n 次序，仅有效元素）
    task push_expected(input integer K,
                       input [P_TO-1:0] rvm, input [P_TN-1:0] nmm);
        integer r, n, kk;
        reg signed [63:0] oacc;
        reg signed [7:0] q7;
        begin
            for (r = 0; r < P_TO; r = r + 1) begin
                if (rvm[r]) begin
                    for (n = 0; n < P_TN; n = n + 1) begin
                        if (nmm[n]) begin
                            oacc = 64'sd0;
                            for (kk = 0; kk < K; kk = kk + 1)
                                oacc = oacc + Wm[r][kk] * Xm[n][kk];
                            q7 = requant_model(oacc, PB[r], PM[r], PS[r]);
                            eq_y[eq_wp] = q7;
                            eq_r[eq_wp] = r[$clog2(P_TO)-1:0];
                            eq_n[eq_wp] = n[$clog2(P_TN)-1:0];
                            eq_wp = eq_wp + 1;
                        end
                    end
                end
            end
        end
    endtask

    // 发一块并等对应 done（末块等 tile_done，其余等 blk_done）
    task do_block(input integer len, input first, input last);
        integer wt;
        begin
            blocks_fed = blocks_fed + 1;
            blk_len   = len[12:0];
            blk_first = first;
            blk_last  = last;
            blk_valid = 1'b1;
            @(negedge clk);
            blk_valid = 1'b0; blk_len = 13'd0;
            if (!last) exp_blk_done = exp_blk_done + 1;
            wt = 0;
            while (!rst) begin
                if (last ? tile_done : blk_done)
                    break;
                @(negedge clk);
                wt = wt + 1;
                if (wt > len + 8 * P_TO * P_TN + 4096) begin
                    errors = errors + 1;
                    $display("EES_ARR_ERR [%0t] do_block timeout (len=%0d last=%b)",
                             $time, len, last);
                    break;
                end
            end
        end
    endtask

    // 完整跑一个 tile（填数/参数/期望 + 全部分块）
    task run_tile(input integer K,
                  input [P_TO-1:0] rvm, input [P_TN-1:0] nmm,
                  input act, input integer big_bias,
                  input integer nb, input integer b0, input integer b1,
                  input integer b2, input integer b3, input integer b4);
        integer b;
        begin
            fill_wx(K);
            load_params(big_bias);
            act_exp = act; act_en = act;
            row_valid = rvm; n_mask = nmm;
            eq_wp = 0; eq_rp = 0;
            push_expected(K, rvm, nmm);
            tiles_started = tiles_started + 1;
            for (b = 0; b < nb; b = b + 1) begin
                case (b)
                    0: do_block(b0, (b == 0), (b == nb-1));
                    1: do_block(b1, (b == 0), (b == nb-1));
                    2: do_block(b2, (b == 0), (b == nb-1));
                    3: do_block(b3, (b == 0), (b == nb-1));
                    4: do_block(b4, (b == 0), (b == nb-1));
                endcase
            end
            gapn(2);
            if (eq_rp != eq_wp) begin
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] tile end with %0d unsent expectations",
                         $time, eq_wp - eq_rp);
            end
        end
    endtask

    initial begin        checks = 0; errors = 0;
        tiles_started = 0; tiles_done = 0; tiles_aborted = 0;
        exp_blk_done = 0; blk_done_seen = 0; y_cnt = 0;
        blocks_fed = 0; stall_en = 0;
        eq_wp = 0; eq_rp = 0;
        rs1 = 11; rs2 = 12; rs3 = 13; rs4 = 14; rs5 = 15;
        cyc = 0; act_exp = 1'b0;
        cb[0] = -8'sd128; cb[1] = -8'sd127; cb[2] = 8'sd127;
        cb[3] = 8'sd0;    cb[4] = 8'sd1;    cb[5] = -8'sd1;
        blk_valid = 0; blk_len = 0; blk_first = 0; blk_last = 0;
        row_valid = {P_TO{1'b1}}; n_mask = {P_TN{1'b1}}; act_en = 0;
        w_we = 0; x_we = 0; w_row = 0; x_col = 0; w_k = 0; x_k = 0;
        w_wd = 0; x_wd = 0;
        p_we = 0; p_row = 0; p_bias = 0; p_m = 0; p_sh = 0;
        lut_we = 0; lut_wa = 0; lut_wd = 0;
        stall = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        gapn(2);
        lut_load_a();
        gapn(2);

        // ===== G1 K_SWEEP：单块 K=1/27/32/576 =====
        run_tile(1,   {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 0, 1, 1,0,0,0,0);
        run_tile(27,  {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 0, 1, 27,0,0,0,0);
        run_tile(32,  {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 0, 1, 32,0,0,0,0);
        run_tile(576, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 0, 1, 576,0,0,0,0);
        $display("EES_ARR_INFO G1_K_SWEEP done (%0dx%0d)", P_TO, P_TN);

        // ===== G2 BLOCKING：2304=[576×4]/[1152,576,576]、1152=[576,576] =====
        run_tile(2304, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 0, 4, 576,576,576,576,0);
        run_tile(2304, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 0, 3, 1152,576,576,0,0);
        run_tile(1152, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 0, 2, 576,576,0,0,0);
        $display("EES_ARR_INFO G2_BLOCKING done");

        // ===== G3 IRREG：[1,1,27,1,34] =====
        run_tile(64, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 0, 5, 1,1,27,1,34);
        $display("EES_ARR_INFO G3_IRREG done");

        // ===== G4 MASK_TAILS：行/列掩码尾 =====
        run_tile(27, {P_TO{1'b1}} >> 1, {P_TN{1'b1}}, 1'b0, 0, 1, 27,0,0,0,0);       //TO−1 行
        run_tile(27, {P_TO{1'b1}}, {P_TN{1'b1}} >> 1, 1'b1, 0, 1, 27,0,0,0,0);       //TN−1 lane
        run_tile(32, {(P_TO)/2{2'b01}}, {(P_TN)/2{2'b01}}, 1'b0, 0, 1, 32,0,0,0,0);  //奇行奇列
        $display("EES_ARR_INFO G4_MASK_TAILS done");

        // ===== G5 STALL：issue 随机停顿 =====
        stall_en = 1;
        run_tile(576, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 0, 1, 576,0,0,0,0);
        run_tile(64,  {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 0, 2, 32,32,0,0,0);
        stall_en = 0;
        $display("EES_ARR_INFO G5_STALL done");

        // ===== G6 RST_MID：在飞击杀 ×2（手动脉冲块，不走 do_block 等待） =====
        for (t = 0; t < 2; t = t + 1) begin
            fill_wx(1000);
            load_params(0);
            act_exp = 1'b0; act_en = 0;
            row_valid = {P_TO{1'b1}}; n_mask = {P_TN{1'b1}};
            eq_wp = 0; eq_rp = 0;
            tiles_started = tiles_started + 1;
            blk_len = 13'd1000; blk_first = 1'b1; blk_last = 1'b0;
            blk_valid = 1'b1;
            @(negedge clk);
            blk_valid = 1'b0;
            repeat (30 + {$random(rs1)} % 60) @(negedge clk);   //ISSUE 中途
            rst = 1'b1;
            repeat (2) @(negedge clk);
            rst = 1'b0;
            eq_rp = eq_wp;              //在飞期望作废
            tiles_aborted = tiles_aborted + 1;
            gapn(6);                     //残影观察窗
            run_tile(27, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 0, 1, 27,0,0,0,0);
        end
        $display("EES_ARR_INFO G6_RST_MID done");

        // ===== G7 BACKTOBACK：tile_done 后零间隙连发 =====
        run_tile(1,  {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 0, 1, 1,0,0,0,0);
        run_tile(27, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 0, 1, 27,0,0,0,0);
        run_tile(32, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 0, 1, 32,0,0,0,0);
        $display("EES_ARR_INFO G7_BACKTOBACK done");

        // ===== G8 FIRSTLAYER：大 bias_eff 量级类 =====
        run_tile(32, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 1, 1, 32,0,0,0,0);
        run_tile(576, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 1, 2, 288,288,0,0,0);
        $display("EES_ARR_INFO G8_FIRSTLAYER done");

        // ===== G9 RANDOM：随机 tile =====
        for (t = 0; t < NRAND; t = t + 1) begin
            i = ({$random(rs1)} % 4 == 0) ? 576 :
                (({$random(rs2)} % 6 == 0) ? 64 :
                 (({$random(rs3)} % 5 == 0) ? 32 : 27));
            run_tile(i,
                     ({$random(rs2)} % 3 == 0) ? ({P_TO{1'b1}} >> 1) : {P_TO{1'b1}},
                     ({$random(rs3)} % 3 == 0) ? ({P_TN{1'b1}} >> 1) : {P_TN{1'b1}},
                     {$random(rs4)} % 2,
                     ({$random(rs1)} % 8 == 0) ? 1 : 0,
                     1, i, 0, 0, 0, 0);
        end
        $display("EES_ARR_INFO G9_RANDOM done (%0d tiles)", NRAND);

        // ===== 收尾 =====
        gapn(8);
        if (tiles_done != tiles_started - tiles_aborted) begin
            errors = errors + 1;
            $display("EES_ARR_ERR conservation started=%0d done=%0d aborted=%0d",
                     tiles_started, tiles_done, tiles_aborted);
        end
        if (blk_done_seen != exp_blk_done) begin
            errors = errors + 1;
            $display("EES_ARR_ERR blk_done seen=%0d want=%0d",
                     blk_done_seen, exp_blk_done);
        end
        $display("EES_SUMMARY checks=%0d errors=%0d", checks, errors);
        $display("EES_ARR_INFO config=%0dx%0d tiles started=%0d done=%0d aborted=%0d y=%0d",
                 P_TO, P_TN, tiles_started, tiles_done, tiles_aborted, y_cnt);
        $display("EES_ARR_INFO blocks_fed=%0d blk_done=%0d", blocks_fed, blk_done_seen);
        if (errors == 0)
            $display("EES_VIVADO_RESULT PASS");
        else
            $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

    //看门狗
    initial begin
        #100_000_000;
        $display("EES_ARR_ERR watchdog timeout");
        $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

endmodule

// ---- 薄包装：三档规模（④）----
module tb_gemm_array_4x4;
    tb_yolo_gemm_array #(.P_TO(4), .P_TN(4)) u ();
endmodule

module tb_gemm_array_8x16;
    tb_yolo_gemm_array #(.P_TO(8), .P_TN(16)) u ();
endmodule

module tb_gemm_array_16x16;
    tb_yolo_gemm_array #(.P_TO(16), .P_TN(16)) u ();
endmodule
