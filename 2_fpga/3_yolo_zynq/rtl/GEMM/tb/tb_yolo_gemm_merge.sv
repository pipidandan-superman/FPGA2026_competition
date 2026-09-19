/************************************************************************
 * File Name     : tb_yolo_gemm_merge.sv
 * Developer     : LSL
 * Date          : 2026-09-19
 * Module Name   : tb_yolo_gemm_merge
 * Description   : run10a / P1.3【V4】三体合并门：yolo_gemm_bank +
 *                 yolo_gemm_feeder + yolo_gemm_array 一体，复跑 run06
 *                 全矩阵（G1-G9 tile 清单逐字保留，随机流与 run08 一致
 *                 ——数据逐字相同，y 对拍即跨实现对照）。
 *
 *   供数机制变化（相对 run08 直驱）：TB 只做块粒度调度——按块把 Wm/Xm
 *   镜像切片经 64b 流式写口装入 bank 双组（组交替 g=b%2），递交 feeder
 *   作业；feeder↔阵列的块头/宽字流/word_ready 全部真线直连，TB 不再
 *   接触字流。阵列 tile 常量/参数/LUT 口仍由 TB 驱动。
 *
 *   档位：4×4（单元）与 8×16（G2 基线）。16×16 不跑——W 字 128b 无
 *   64b 写口通路（G2 收敛架构 §2 定 8×16 基线），其阵列级等价覆盖已由
 *   run08 冻结（6881 checks）。P_KC=1152 = 矩阵最深层块（[1152,576,576]）
 *   ——功能门参数，生产 Kc 定档是 P1.4 综合问题。
 *
 *   相对 run08 的激励差异（如实声明）：G5 生产者抖动退役——合并系统的
 *   生产者是 feeder（无 valid 抖动；消费侧停拍已由 run09 R4 覆盖），
 *   G5 两 tile 保留以维持检查数对齐；G6 击杀改为 job 递交后定时杀
 *   （字流由 feeder 驱动，TB 无法逐字截断）。
 *
 *   继承纪律：每 negedge 驱动、$random 无符号模且上限预计算、
 *   内层循环禁用外层变量、done 事件即消费、守恒 started=done+aborted、
 *   TB 不制造 TDP 冲突访问（装载只在读侧排空后进行——顺序调度）。
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : run10a 三体合并门初版。
 ************************************************************************/

`timescale 1ns/1ps

module tb_yolo_gemm_merge #(
    parameter integer P_TO = 4,
    parameter integer P_TN = 4,
    parameter integer P_KC = 1152    //矩阵最深层块 1152；生产定档见 P1.4
);

    localparam integer KMAX = 2304;
    localparam integer NRAND = (P_TO * P_TN >= 256) ? 8 :
                               ((P_TO * P_TN >= 128) ? 15 : 40);

    // ---- 时钟/复位（三 DUT 共享）----
    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_d;
    always @(posedge clk) rst_d <= rst;

    // ---- bank 装载写口（TB 驱动）----
    reg         wr_valid, wr_is_x, wr_x_hi, wr_first, wr_last;
    reg  [63:0] wr_data;
    reg  [7:0]  wr_be;
    reg         ld_w_grp, ld_x_grp;
    wire        wr_ready;
    wire [1:0]  w_ld_ok, x_ld_ok, w_loaded, x_loaded;
    wire [12:0] ld_w_len, ld_x_len;
    wire        ld_done;

    // ---- feeder 作业口（TB 驱动）----
    reg         job_valid, job_first, job_last, job_w_grp, job_x_grp;
    reg  [12:0] job_len;
    wire        job_ready;

    // ---- feeder↔bank 真线 ----
    wire        w_rgrp, w_ren, x_rgrp, x_ren;
    wire [12:0] w_raddr, x_raddr;
    wire [8*P_TO-1:0] w_dg0, w_dg1;
    wire [8*P_TN-1:0] x_dg0, x_dg1;
    wire        rd_busy;

    // ---- feeder→阵列字流（真线，TB 不接触）----
    wire        blk_valid_w;
    wire [12:0] blk_len_w;
    wire        blk_first_w, blk_last_w;
    wire [8*P_TO-1:0] w_word_w;
    wire [8*P_TN-1:0] x_word_w;
    wire        word_valid_w, word_first_w, word_last_w, word_ready_w;

    // ---- 阵列 tile 常量/参数/LUT（TB 驱动）----
    reg  [P_TO-1:0] row_valid;
    reg  [P_TN-1:0] n_mask;
    reg  act_en;
    reg  p_we;
    reg  [$clog2(P_TO)-1:0] p_row;
    reg  signed [31:0] p_bias, p_m;
    reg  [5:0] p_sh;
    reg  lut_we;
    reg  [7:0] lut_wa, lut_wd;
    wire blk_done, tile_done, busy, proto_err, y_valid;
    wire signed [7:0] y;
    wire [$clog2(P_TO)-1:0] y_row;
    wire [$clog2(P_TN)-1:0] y_col;
    wire bank_err;   //前置声明（10-3380 教训：勿在声明前引用）

    // ---- 三体例化 ----
    yolo_gemm_bank #(.P_TO(P_TO), .P_TN(P_TN), .P_KC(P_KC)) u_bank (
        .clk_i(clk), .rst_i(rst),
        .wr_valid_i(wr_valid), .wr_ready_o(wr_ready), .wr_data_i(wr_data),
        .wr_is_x_i(wr_is_x), .wr_x_hi_i(wr_x_hi), .wr_be_i(wr_be),
        .wr_first_i(wr_first), .wr_last_i(wr_last),
        .ld_w_grp_i(ld_w_grp), .ld_x_grp_i(ld_x_grp), .rd_busy_i(rd_busy),
        .w_ld_ok_o(w_ld_ok), .x_ld_ok_o(x_ld_ok),
        .w_loaded_o(w_loaded), .x_loaded_o(x_loaded),
        .ld_w_len_o(ld_w_len), .ld_x_len_o(ld_x_len), .ld_done_o(ld_done),
        .w_rgrp_i(w_rgrp), .w_raddr_i(w_raddr), .w_ren_i(w_ren),
        .w_dout_g0_o(w_dg0), .w_dout_g1_o(w_dg1),
        .x_rgrp_i(x_rgrp), .x_raddr_i(x_raddr), .x_ren_i(x_ren),
        .x_dout_g0_o(x_dg0), .x_dout_g1_o(x_dg1),
        .bank_err_o(bank_err)
    );

    yolo_gemm_feeder #(.P_TO(P_TO), .P_TN(P_TN)) u_feeder (
        .clk_i(clk), .rst_i(rst),
        .job_valid_i(job_valid), .job_ready_o(job_ready),
        .job_len_i(job_len), .job_first_i(job_first), .job_last_i(job_last),
        .job_w_grp_i(job_w_grp), .job_x_grp_i(job_x_grp),
        .w_rgrp_o(w_rgrp), .w_raddr_o(w_raddr), .w_ren_o(w_ren),
        .w_dout_g0_i(w_dg0), .w_dout_g1_i(w_dg1),
        .x_rgrp_o(x_rgrp), .x_raddr_o(x_raddr), .x_ren_o(x_ren),
        .x_dout_g0_i(x_dg0), .x_dout_g1_i(x_dg1),
        .w_grp_ld_i(w_loaded), .x_grp_ld_i(x_loaded),
        .rd_busy_o(rd_busy),
        .blk_valid_o(blk_valid_w), .blk_len_o(blk_len_w),
        .blk_first_o(blk_first_w), .blk_last_o(blk_last_w),
        .w_word_o(w_word_w), .x_word_o(x_word_w),
        .word_valid_o(word_valid_w), .word_first_o(word_first_w),
        .word_last_o(word_last_w), .word_ready_i(word_ready_w)
    );

    yolo_gemm_array #(.P_TO(P_TO), .P_TN(P_TN)) dut (
        .clk_i(clk), .rst_i(rst),
        .blk_valid_i(blk_valid_w), .blk_len_i(blk_len_w),
        .blk_first_i(blk_first_w), .blk_last_i(blk_last_w),
        .row_valid_i(row_valid), .n_mask_i(n_mask), .act_en_i(act_en),
        .w_word_i(w_word_w), .x_word_i(x_word_w),
        .word_valid_i(word_valid_w), .word_first_i(word_first_w),
        .word_last_i(word_last_w), .word_ready_o(word_ready_w),
        .p_we_i(p_we), .p_row_i(p_row),
        .p_bias_i(p_bias), .p_m_i(p_m), .p_sh_i(p_sh),
        .lut_we_i(lut_we), .lut_wa_i(lut_wa), .lut_wd_i(lut_wd),
        .blk_done_o(blk_done), .tile_done_o(tile_done), .busy_o(busy),
        .proto_err_o(proto_err),
        .y_valid_o(y_valid), .y_o(y),
        .y_row_o(y_row), .y_col_o(y_col)
    );

    // ---- 记账（与 run08 同名同义，便于逐数对齐）----
    integer checks, errors;
    integer tiles_started, tiles_done, tiles_aborted;
    integer exp_blk_done, blk_done_seen;
    integer y_cnt;
    integer proto_cnt;
    reg    proto_prev, bank_err_prev;
    integer ld_done_seen;
    integer eq_wp, eq_rp;
    reg signed [7:0]          eq_y [0:65535];
    reg [$clog2(P_TO)-1:0]    eq_r [0:65535];
    reg [$clog2(P_TN)-1:0]    eq_n [0:65535];
    integer rs1, rs2, rs3, rs4, rs5;
    integer cyc;
    integer blocks_fed;
    integer i, t, q;
    reg act_exp;
    reg [63:0] rbeat;
    always @(negedge clk) cyc = cyc + 1;

    // ---- bank_err 上升沿计错（合并层新增仪器）----
    always @(posedge clk) begin
        if (bank_err && !bank_err_prev && !rst) begin
            errors = errors + 1;
            $display("EES_ARR_ERR [%0t] bank_err raised", $time);
        end
        bank_err_prev <= bank_err;
    end

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

    // ---- 检查器：每 negedge 全覆盖（run08 逐字）----
    reg signed [7:0] eqt;
    reg [7:0] eadt;
    reg signed [7:0] eexp;
    always @(negedge clk) begin
        if (rst_d) begin
            if (y_valid || blk_done || tile_done) begin
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] done/y during rst", $time);
            end
        end else begin
            if (proto_err && !proto_prev) begin
                proto_cnt = proto_cnt + 1;
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] proto_err (stream flags vs blk_len)",
                         $time);
            end
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
        proto_prev = proto_err;
    end

    // ---- 基础任务 ----
    task gapn(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    task lut_load_a;        //图样 A：i ^ A5
        integer li;
        begin
            for (li = 0; li < 256; li = li + 1) begin
                lut_we = 1'b1; lut_wa = li[7:0];
                lut_wd = li[7:0] ^ 8'hA5;
                lut_exp[li] = li[7:0] ^ 8'hA5;
                @(negedge clk);
            end
            lut_we = 1'b0;
        end
    endtask

    reg signed [7:0] cb [0:5];      //角点池
    task fill_wx(input integer K);  //镜像填充（随机流与 run08 完全一致）
        integer kk, ii;
        reg signed [7:0] wv, xv;
        begin
            for (kk = 0; kk < K; kk = kk + 1) begin
                for (ii = 0; ii < ((P_TO > P_TN) ? P_TO : P_TN); ii = ii + 1) begin
                    if (ii < P_TO) begin
                    wv = ({$random(rs1)} % 16 == 0) ? cb[{$random(rs2)} % 6]
                        : $signed({$random(rs3)} % 256) - 128;
                        Wm[ii][kk] = wv;
                    end
                    if (ii < P_TN) begin
                        xv = ({$random(rs2)} % 16 == 0) ? cb[{$random(rs1)} % 6]
                            : $signed({$random(rs4)} % 256) - 128;
                        Xm[ii][kk] = xv;
                    end
                end
            end
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

    // ---- bank 装载拍（negedge 驱动 / posedge 判收 / 未收保持）----
    task wr_beat(input integer isx, input integer xhi,
                 input integer firstb, input integer lastb);
        integer guard;
        begin
            @(negedge clk);
            wr_valid = 1'b1; wr_is_x = isx[0]; wr_x_hi = xhi[0];
            wr_first = firstb[0]; wr_last = lastb[0];
            wr_be = 8'hFF; wr_data = rbeat;
            guard = 0;
            @(posedge clk);
            while (!wr_ready && guard < 256) begin
                guard = guard + 1;
                @(posedge clk);
            end
            if (!wr_ready) begin
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] bank wr beat stuck not-ready", $time);
            end
            @(negedge clk);
            wr_valid = 1'b0; wr_first = 1'b0; wr_last = 1'b0;
        end
    endtask

    // ---- 装一块入 bank：k0=块首在 tile 内的绝对位置，grp=目标组 ----
    // （V2 无 k0 契约：bank 每块从组地址 0 起——块基址活在装载顺序）
    task bank_load(input integer len, input integer k0, input integer grp);
        integer kk, j;
        begin
            ld_w_grp = grp[0]; ld_x_grp = grp[0];
            for (kk = 0; kk < len; kk = kk + 1) begin
                // W 整字拍（lane r = Wm[r][k0+kk]）
                rbeat = 64'd0;
                for (j = 0; j < P_TO; j = j + 1)
                    rbeat[8*j +: 8] = Wm[j][k0+kk];
                wr_beat(0, 0, (kk == 0), 1'b0);
                // X lo 半字（lane 0..7）
                rbeat = 64'd0;
                for (j = 0; j < 8; j = j + 1)
                    if (j < P_TN) rbeat[8*j +: 8] = Xm[j][k0+kk];
                wr_beat(1, 0, 1'b0, 1'b0);
                // X hi 半字（lane 8..15；P_TN<9 时数据空拍但仍是整字完成拍）
                rbeat = 64'd0;
                for (j = 0; j < 8; j = j + 1)
                    if (j + 8 < P_TN) rbeat[8*j +: 8] = Xm[j+8][k0+kk];
                wr_beat(1, 1, 1'b0, (kk == len-1));
            end
            //采样纪律：ld_done_r 在 wr_last 接收拍(P0) NBA 置 1、P1 NBA 清零。
            //末拍 wr_beat 返回点=N0(P0/P1 间)=脉冲窗正中——本处同拍直读，
            //无沿竞态（@posedge 读旧值虽也可行但依赖活动区时序，不取）。
            if (!ld_done) begin
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] ld_done missing after bank load len=%0d",
                         $time, len);
            end
            if (ld_w_len != len[12:0]) begin
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] ld_w_len=%0d exp=%0d",
                         $time, ld_w_len, len);
            end
            if (ld_x_len != len[12:0]) begin
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] ld_x_len=%0d exp=%0d",
                         $time, ld_x_len, len);
            end
            ld_done_seen = ld_done_seen + 1;
            gapn(1);
        end
    endtask

    // ---- 递交 feeder 作业（块头经 feeder 呈现，阵列 IDLE/WAIT 接受）----
    task job_feed(input integer len, input integer first, input integer last,
                  input integer grp);
        integer guard;
        begin
            blocks_fed = blocks_fed + 1;
            if (!last[0]) exp_blk_done = exp_blk_done + 1;
            @(negedge clk);
            job_len = len[12:0]; job_first = first[0]; job_last = last[0];
            job_w_grp = grp[0]; job_x_grp = grp[0];
            job_valid = 1'b1;
            guard = 0;
            @(posedge clk);
            while (!job_ready && guard < 256) begin
                guard = guard + 1;
                @(posedge clk);
            end
            if (!job_ready) begin
                errors = errors + 1;
                $display("EES_ARR_ERR [%0t] job handshake timeout", $time);
            end
            @(negedge clk);
            job_valid = 1'b0;
        end
    endtask

    // ---- 等本块收口：非末块等 blk_done，末块等 tile_done ----
    task wait_done(input integer last, input integer len);
        integer wt;
        begin
            wt = 0;
            while (!rst) begin
                if (last[0] ? tile_done : blk_done)
                    break;
                @(negedge clk);
                wt = wt + 1;
                if (wt > len + 8 * P_TO * P_TN + 4096) begin
                    errors = errors + 1;
                    $display("EES_ARR_ERR [%0t] wait_done timeout (len=%0d last=%0d)",
                             $time, len, last);
                    break;
                end
            end
        end
    endtask

    // ---- 发一块（合并路径：装载→递交→等收口）----
    task do_block_m(input integer len, input integer first, input integer last,
                    input integer k0, input integer grp);
        begin
            bank_load(len, k0, grp);
            job_feed(len, first, last, grp);
            wait_done(last, len);
        end
    endtask

    // ---- 完整跑一个 tile（G 清单与随机流与 run08 逐字一致）----
    task run_tile(input integer K,
                  input [P_TO-1:0] rvm, input [P_TN-1:0] nmm,
                  input act, input integer big_bias,
                  input integer nb, input integer b0, input integer b1,
                  input integer b2, input integer b3, input integer b4);
        integer b, kbase;
        begin
            fill_wx(K);
            load_params(big_bias);
            act_exp = act; act_en = act;
            row_valid = rvm; n_mask = nmm;
            eq_wp = 0; eq_rp = 0;
            push_expected(K, rvm, nmm);
            tiles_started = tiles_started + 1;
            kbase = 0;
            for (b = 0; b < nb; b = b + 1) begin
                case (b)
                    0: do_block_m(b0, (b == 0), (b == nb-1), kbase, b & 1);
                    1: do_block_m(b1, (b == 0), (b == nb-1), kbase, b & 1);
                    2: do_block_m(b2, (b == 0), (b == nb-1), kbase, b & 1);
                    3: do_block_m(b3, (b == 0), (b == nb-1), kbase, b & 1);
                    4: do_block_m(b4, (b == 0), (b == nb-1), kbase, b & 1);
                endcase
                case (b)
                    0: kbase = kbase + b0;
                    1: kbase = kbase + b1;
                    2: kbase = kbase + b2;
                    3: kbase = kbase + b3;
                    4: kbase = kbase + b4;
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
        blocks_fed = 0;
        proto_cnt = 0; proto_prev = 0;
        bank_err_prev = 0; ld_done_seen = 0;
        eq_wp = 0; eq_rp = 0;
        rs1 = 11; rs2 = 12; rs3 = 13; rs4 = 14; rs5 = 15;
        cyc = 0; act_exp = 1'b0;
        cb[0] = -8'sd128; cb[1] = -8'sd127; cb[2] = 8'sd127;
        cb[3] = 8'sd0;    cb[4] = 8'sd1;    cb[5] = -8'sd1;
        wr_valid = 0; wr_is_x = 0; wr_x_hi = 0; wr_first = 0; wr_last = 0;
        wr_data = 64'd0; wr_be = 8'hFF; ld_w_grp = 0; ld_x_grp = 0;
        job_valid = 0; job_len = 0; job_first = 0; job_last = 0;
        job_w_grp = 0; job_x_grp = 0;
        row_valid = {P_TO{1'b1}}; n_mask = {P_TN{1'b1}}; act_en = 0;
        p_we = 0; p_row = 0; p_bias = 0; p_m = 0; p_sh = 0;
        lut_we = 0; lut_wa = 0; lut_wd = 0;
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

        // ===== G5：生产者抖动已随直驱退役（feeder 为生产者，无抖动源；
        //           消费侧停拍覆盖在 run09 R4）——tile 保留维持矩阵对齐 =====
        run_tile(576, {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b1, 0, 1, 576,0,0,0,0);
        run_tile(64,  {P_TO{1'b1}}, {P_TN{1'b1}}, 1'b0, 0, 2, 32,32,0,0,0);
        $display("EES_ARR_INFO G5 done");

        // ===== G6 RST_MID：流中击杀 ×2（job 递交后定时杀，字流在 feeder）=====
        for (t = 0; t < 2; t = t + 1) begin
            fill_wx(1000);
            load_params(0);
            act_exp = 1'b0; act_en = 0;
            row_valid = {P_TO{1'b1}}; n_mask = {P_TN{1'b1}};
            eq_wp = 0; eq_rp = 0;
            tiles_started = tiles_started + 1;
            bank_load(1000, 0, 0);            //整块入 g0（手动路，不计 blocks_fed）
            @(negedge clk);
            job_len = 13'd1000; job_first = 1'b1; job_last = 1'b0;
            job_w_grp = 1'b0; job_x_grp = 1'b0;
            job_valid = 1'b1;
            @(negedge clk);
            job_valid = 1'b0;
            //随机流对齐（run08 G6 逐字）：此处抽 rs1 一次/中止 tile，
            //固定拍数会少抽 2 次使 G7 起数据漂移、破坏跨实现对照声明
            i = 20 + {$random(rs1)} % 40;
            repeat (i) @(negedge clk);  //ISSUE 中段（~i-1 字已入阵列，<1000 无 word_last）
            rst = 1'b1;
            repeat (2) @(negedge clk);
            rst = 1'b0;
            eq_rp = eq_wp;                    //在飞期望作废
            tiles_aborted = tiles_aborted + 1;
            gapn(6);                          //残影观察窗
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
        if (ld_done_seen != blocks_fed + 2) begin
            errors = errors + 1;
            $display("EES_ARR_ERR ld_done seen=%0d want=%0d (blocks+2 manual)",
                     ld_done_seen, blocks_fed + 2);
        end
        $display("EES_SUMMARY checks=%0d errors=%0d proto_err=%0d",
                 checks, errors, proto_cnt);
        $display("EES_ARR_INFO config=%0dx%0d tiles started=%0d done=%0d aborted=%0d y=%0d",
                 P_TO, P_TN, tiles_started, tiles_done, tiles_aborted, y_cnt);
        $display("EES_ARR_INFO blocks_fed=%0d blk_done=%0d ld_done=%0d KC=%0d",
                 blocks_fed, blk_done_seen, ld_done_seen, P_KC);
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

// ---- 薄包装：合并门两档（16×16 无 64b 写口通路，见文件头说明）----
module tb_gemm_merge_4x4;
    tb_yolo_gemm_merge #(.P_TO(4), .P_TN(4),  .P_KC(1152)) u ();
endmodule

module tb_gemm_merge_8x16;
    tb_yolo_gemm_merge #(.P_TO(8), .P_TN(16), .P_KC(1152)) u ();
endmodule
