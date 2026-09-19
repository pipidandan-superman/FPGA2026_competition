/************************************************************************
 * File Name       : tb_yolo_gemm_bankfeeder.sv
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_gemm_bankfeeder
 * Description     : G2/V2 (run09) bank+feeder one-body gate.
 *
 *   The TB plays BOTH sides: the load producer (streaming 64b write
 *   port, interleaved W / X-lo / X-hi beats) and the array consumer
 *   (V2.0 pure-consumer word contract: header accepted in IDLE/WAIT,
 *   word_ready high in ISSUE, per-beat jitter/stall patterns, DRAIN
 *   >= 4 between blocks). Golden = TB mirror arrays with the SAME
 *   byte-enable merge semantics; every accepted word beat is checked
 *   beat-by-beat (data + word_first/word_last sidebands + k order).
 *
 *   Stage matrix (on top of the run06 discipline):
 *     R1 single blocks, len off-by-one set {1,2,3,top}
 *     R2 ping-pong group swap with REAL load/read overlap (fork/join),
 *         plus g0->g1->g0 stale-data overwrite
 *     R3 load timing: early / just-in-time / LATE (job first, header
 *         held by grp_loaded gating until ld_done)
 *     R4 consumer jitter: random ready gaps + deterministic stalls at
 *         first/mid/last word (address-freeze correctness)
 *     R5 independent w_sel/x_sel: W resident reuse across X swap
 *     R6 lane-WE merge: partial-lane rewrite over full words
 *     R7 off-by-one specials: len=1 (first==last same beat), len=2,
 *         len=Kc-1/Kc top address edge, back-to-back drain=4 boundary
 *     R8 discipline: write-to-read-selected-group REFUSAL (wr_ready=0,
 *         no access happens -- TB never creates a conflicting access)
 *
 *   TB discipline (project rules): $random bounds precomputed once,
 *   never an outer loop variable reused inside, unsigned-mod idiom
 *   {$random(rs)} % N, per-negedge driving, every wait bounded.
 ************************************************************************/
`timescale 1ns/1ps
module tb_yolo_gemm_bankfeeder #(
    parameter integer P_TO = 8,
    parameter integer P_TN = 16,
    parameter integer P_KC = 64
);
    localparam integer W_WD = 8*P_TO;
    localparam integer X_WD = 8*P_TN;
    localparam integer LSET = (P_KC > 8) ? 8 : P_KC;   //小长度档
    localparam integer L9   = (P_KC > 9) ? 9 : P_KC;   //R4/R8 中长档（单元层钳到 KC）
    localparam integer LLONG = (P_KC >= LSET + 5) ? LSET + 5 : P_KC; //R4 长档
    //阶段字数总和：R1(6+LSET)+R2(17)+R3(21)+R4(3*L9+LLONG)+R5(24)+R6(6)
    //              +R7(12+2KC)+R8(L9)   （R7 小块=1+2+5+5=12，v2 曾误记 13）
    localparam integer EXP_WORDS = 86 + LSET + 4*L9 + LLONG + 2*P_KC;

    // ---- 时钟/复位 ----
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;                  //100MHz

    // ---- 装载写口 ----
    reg         wr_valid = 1'b0;
    reg         wr_is_x  = 1'b0;
    reg         wr_x_hi  = 1'b0;
    reg         wr_first = 1'b0;
    reg         wr_last  = 1'b0;
    reg  [63:0] wr_data  = 64'd0;
    reg  [7:0]  wr_be    = 8'hFF;
    reg         ld_w_grp = 1'b0;
    reg         ld_x_grp = 1'b0;
    wire        wr_ready;
    wire [1:0]  w_ld_ok, x_ld_ok, w_loaded, x_loaded;
    wire [12:0] ld_w_len, ld_x_len;
    wire        ld_done;

    // ---- bank 读侧（feeder 驱动）----
    wire        w_rgrp, x_rgrp;
    wire [12:0] w_raddr, x_raddr;
    wire        w_ren, x_ren;
    wire [W_WD-1:0] w_dg0, w_dg1;
    wire [X_WD-1:0] x_dg0, x_dg1;
    wire        bank_err;
    wire        rd_busy;                        //feeder 读侧在飞 → bank 写口组门控

    // ---- 作业口 ----
    reg         job_valid = 1'b0;
    reg  [12:0] job_len   = 13'd0;
    reg         job_first = 1'b0;
    reg         job_last  = 1'b0;
    reg         job_w_grp = 1'b0;
    reg         job_x_grp = 1'b0;
    wire        job_ready;

    // ---- 阵列侧（TB 消费者）----
    wire        blk_valid;
    wire [12:0] blk_len;
    wire        blk_first, blk_last;
    wire [W_WD-1:0] w_word;
    wire [X_WD-1:0] x_word;
    wire        word_valid, word_first, word_last;
    reg         word_ready = 1'b0;

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
        .blk_valid_o(blk_valid), .blk_len_o(blk_len),
        .blk_first_o(blk_first), .blk_last_o(blk_last),
        .w_word_o(w_word), .x_word_o(x_word),
        .word_valid_o(word_valid), .word_first_o(word_first),
        .word_last_o(word_last), .word_ready_i(word_ready)
    );

    // ---- 镜像模型（BE 合并语义与 DUT 相同）----
    reg [W_WD-1:0] Wm0 [0:P_KC-1];
    reg [W_WD-1:0] Wm1 [0:P_KC-1];
    reg [X_WD-1:0] Xm0 [0:P_KC-1];
    reg [X_WD-1:0] Xm1 [0:P_KC-1];

    // ---- 计分与随机流 ----
    integer checks = 0, errors = 0;
    integer jobs_fed = 0, jobs_hdr = 0, jobs_done = 0, words_checked = 0;
    integer ld_done_seen = 0;
    integer rs1, rs2, rs3, rs4, rs5;
    integer i, j, k, q, t, n, m;            //互不复用的循环变量（run08 教训）
    reg hold_check_en = 1'b0;               //R3 晚到：装载中途 blk_valid 必须为 0
    reg [63:0] rbeat;
    reg [W_WD-1:0] wgen;
    reg [X_WD-1:0] xgen;
    reg bank_err_prev;

    // ---- 基础节拍任务 ----
    task automatic wait_beats(input integer nb);   //negedge 对齐等待
        integer w;
        begin
            for (w = 0; w < nb; w = w + 1) @(negedge clk);
        end
    endtask

    // 单拍装载拍驱动（negedge 置位，posedge 判收，未收则保持）
    task automatic wr_beat_go(input integer isx, input integer xhi,
                    input integer firstb, input integer lastb,
                    input [7:0] be);
        integer guard;
        begin
            @(negedge clk);
            wr_valid = 1'b1; wr_is_x = isx[0]; wr_x_hi = xhi[0];
            wr_first = firstb[0]; wr_last = lastb[0];
            wr_be    = be; wr_data = rbeat;
            guard = 0;
            @(posedge clk);
            while (!wr_ready && guard < 64) begin
                guard = guard + 1;
                @(posedge clk);
            end
            if (!wr_ready) begin
                errors = errors + 1;
                $display("EES_ERR [%0t] wr beat stuck not-ready", $time);
            end
            @(negedge clk);
            wr_valid = 1'b0; wr_first = 1'b0; wr_last = 1'b0;
        end
    endtask

    // ---- 装载块任务：随机字写入镜像+驱动 DUT（W/Xlo/Xhi 交织）----
    // wbe/xbe 可为部分使能（R6 合并语义）；ldjit=1 时节间随机空 1-2 拍
    task automatic load_block(input integer len, input integer wgrp,
                    input integer xgrp,
                    input do_w, input do_x,
                    input [7:0] wbe, input [7:0] xbe_lo, input [7:0] xbe_hi,
                    input ldjit);
        integer kk, l;
        begin
            ld_w_grp = wgrp[0];
            ld_x_grp = xgrp[0];
            for (kk = 0; kk < len; kk = kk + 1) begin
                // W 整字拍
                if (do_w) begin
                    for (l = 0; l < P_TO; l = l + 1)
                        wgen[8*l +: 8] = {$random(rs2)} % 256;
                    rbeat = 64'd0;
                    for (l = 0; l < P_TO; l = l + 1)
                        rbeat[8*l +: 8] = wgen[8*l +: 8];
                    for (l = 0; l < 8; l = l + 1)
                        if (wbe[l] && (l < P_TO))
                            if (wgrp[0]) Wm1[kk][8*l +: 8] = wgen[8*l +: 8];
                            else         Wm0[kk][8*l +: 8] = wgen[8*l +: 8];
                    wr_beat_go(0, 0, (kk == 0), (kk == len-1) && !do_x, wbe);
                end
                // X 两半拍
                if (do_x) begin
                    for (l = 0; l < P_TN; l = l + 1)
                        xgen[8*l +: 8] = {$random(rs3)} % 256;
                    // lo 半
                    rbeat = 64'd0;
                    for (l = 0; l < 8; l = l + 1)
                        if (l < P_TN) rbeat[8*l +: 8] = xgen[8*l +: 8];
                    for (l = 0; l < 8; l = l + 1)
                        if (xbe_lo[l] && (l < P_TN))
                            if (xgrp[0]) Xm1[kk][8*l +: 8] = xgen[8*l +: 8];
                            else         Xm0[kk][8*l +: 8] = xgen[8*l +: 8];
                    wr_beat_go(1, 0, (kk == 0) && !do_w, 1'b0, xbe_lo);
                    // hi 半
                    rbeat = 64'd0;
                    for (l = 0; l < 8; l = l + 1)
                        if ((l + 8) < P_TN) rbeat[8*l +: 8] = xgen[8*(l+8) +: 8];
                    for (l = 0; l < 8; l = l + 1)
                        if (xbe_hi[l] && ((l + 8) < P_TN))
                            if (xgrp[0]) Xm1[kk][8*(l+8) +: 8] = xgen[8*(l+8) +: 8];
                            else         Xm0[kk][8*(l+8) +: 8] = xgen[8*(l+8) +: 8];
                    wr_beat_go(1, 1, 1'b0, (kk == len-1), xbe_hi);
                end
                if (ldjit && (kk < len - 1) && ({$random(rs4)} % 3 == 0))
                    wait_beats(1 + {$random(rs4)} % 2);   //末拍后不留隙：ld_done 单拍脉冲须紧贴采样
                // R3 晚到检查点：重装中途（loaded 已被首拍清零）header 必须被压住
                if (hold_check_en && (kk == len/2) && blk_valid) begin
                    errors = errors + 1;
                    $display("EES_ERR [%0t] gating: blk_valid high mid-reload", $time);
                end
            end
            // 收口检查：ld_done 脉冲 + 块长 + loaded 标志
            @(posedge clk);
            if (!ld_done) begin
                errors = errors + 1;
                $display("EES_ERR [%0t] ld_done missing after block len=%0d", $time, len);
            end
            if (do_w && (ld_w_len != len[12:0])) begin
                errors = errors + 1;
                $display("EES_ERR [%0t] ld_w_len=%0d exp=%0d", $time, ld_w_len, len);
            end
            if (do_x && (ld_x_len != len[12:0])) begin
                errors = errors + 1;
                $display("EES_ERR [%0t] ld_x_len=%0d exp=%0d", $time, ld_x_len, len);
            end
            ld_done_seen = ld_done_seen + 1;
            wait_beats(1);
        end
    endtask

    // ---- 作业递交 ----
    task automatic job_hand(input integer len, input integer wgrp,
                    input integer xgrp,
                    input integer fstb, input integer lstb);
        integer guard;
        begin
            @(negedge clk);
            job_len = len[12:0]; job_first = fstb[0]; job_last = lstb[0];
            job_w_grp = wgrp[0]; job_x_grp = xgrp[0];
            job_valid = 1'b1;
            guard = 0;
            @(posedge clk);
            while (!job_ready && guard < 256) begin
                guard = guard + 1;
                @(posedge clk);
            end
            if (!job_ready) begin
                errors = errors + 1;
                $display("EES_ERR [%0t] job handshake timeout", $time);
            end
            @(negedge clk);
            job_valid = 1'b0;
            jobs_fed = jobs_fed + 1;
        end
    endtask

    // ---- 消费者：等 header（含门控保持窗观测）→ 流式收字逐拍对账 ----
    // hdr_delay：blk_valid 升起后延迟若干拍才进 ISSUE（ready 升）
    // stall_pos：<0 无确定性停拍；否则在该字接受前停 stall_len 拍
    // jit：随机 ready 抖动
    task automatic consume_block(input integer len, input integer wgrp,
                    input integer xgrp,
                    input integer fstb, input integer lstb,
                       input integer hdr_delay, input drain,
                       input integer stall_pos, input integer stall_len,
                       input jit);
        integer guard, kk;
        reg [W_WD-1:0] ew;
        reg [X_WD-1:0] ex;
        begin
            // 1) header 等待（含超时）与字段对账
            guard = 0;
            while (!blk_valid && guard < 512) begin
                guard = guard + 1;
                @(posedge clk);
            end
            if (!blk_valid) begin
                errors = errors + 1;
                $display("EES_ERR [%0t] blk_valid timeout len=%0d", $time, len);
            end else begin
                jobs_hdr = jobs_hdr + 1;
                if (blk_len != len[12:0] || blk_first !== fstb[0] ||
                    blk_last !== lstb[0]) begin
                    errors = errors + 1;
                    $display("EES_ERR [%0t] hdr fields len=%0d/%0d f=%b/%b l=%b/%b",
                             $time, blk_len, len, blk_first, fstb[0], blk_last, lstb[0]);
                end
            end
            // 2) 延迟进 ISSUE（此时 feeder 仍持 header，无字）
            for (kk = 0; kk < hdr_delay; kk = kk + 1) @(negedge clk);
            // 3) 进 ISSUE：ready 升（feeder 在此拍锁组、次拍发首地址）
            @(negedge clk);
            word_ready = 1'b1;
            // 4) 收字
            for (kk = 0; kk < len; kk = kk + 1) begin
                // 确定性停拍 / 随机抖动（首字之后的拍上）
                if (stall_pos >= 0 && kk == stall_pos && stall_len > 0) begin
                    @(negedge clk); word_ready = 1'b0;
                    wait_beats(stall_len);
                    @(negedge clk); word_ready = 1'b1;
                end else if (jit && (kk > 0) && ({$random(rs5)} % 4 == 0)) begin
                    @(negedge clk); word_ready = 1'b0;
                    wait_beats(1 + {$random(rs5)} % 2);
                    @(negedge clk); word_ready = 1'b1;
                end
                guard = 0;
                @(posedge clk);
                while (!(word_valid && word_ready) && guard < 512) begin
                    guard = guard + 1;
                    @(posedge clk);
                end
                if (!(word_valid && word_ready)) begin
                    errors = errors + 1;
                    $display("EES_ERR [%0t] word[%0d] accept timeout", $time, kk);
                    kk = len;                      //跳出
                end else begin
                    ew = wgrp[0] ? Wm1[kk] : Wm0[kk];
                    ex = xgrp[0] ? Xm1[kk] : Xm0[kk];
                    if (w_word !== ew) begin
                        errors = errors + 1;
                        $display("EES_ERR [%0t] w_word[%0d] got=%h exp=%h",
                                 $time, kk, w_word, ew);
                    end
                    if (x_word !== ex) begin
                        errors = errors + 1;
                        $display("EES_ERR [%0t] x_word[%0d] got=%h exp=%h",
                                 $time, kk, x_word, ex);
                    end
                    if (word_first !== (kk == 0) || word_last !== (kk == len-1)) begin
                        errors = errors + 1;
                        $display("EES_ERR [%0t] sideband[%0d] f=%b l=%b",
                                 $time, kk, word_first, word_last);
                    end
                    checks = checks + 1;
                    words_checked = words_checked + 1;
                end
            end
            // 5) DRAIN（ready 低 >=4 拍；feeder 排空回 IDLE）
            @(negedge clk);
            word_ready = 1'b0;
            wait_beats(drain);
            jobs_done = jobs_done + 1;
        end
    endtask

    // ---- 全局仪器：bank_err 上升沿计错 ----
    always @(posedge clk) begin
        if (bank_err && !bank_err_prev && !rst) begin
            errors = errors + 1;
            $display("EES_ERR [%0t] bank_err raised", $time);
        end
        bank_err_prev <= bank_err;
    end

    // ---- DBG 探针（xsim -testplusarg DBG 时逐拍打印写接受/读发起）----
    always @(posedge clk) if ($test$plusargs("DBG") && !rst) begin
        if (wr_valid && wr_ready)
            $display("DBG[%0t] WRACC x=%b hi=%b f=%b l=%b wg=%b xg=%b wk=%0d xk=%0d d=%h",
                     $time, wr_is_x, wr_x_hi, wr_first, wr_last,
                     ld_w_grp, ld_x_grp, u_bank.wk_cnt, u_bank.xk_cnt, wr_data);
        if (w_ren)
            $display("DBG[%0t] REN w_addr=%0d w_grp=%b x_addr=%0d x_grp=%b",
                     $time, w_raddr, w_rgrp, x_raddr, x_rgrp);
    end

    // ---- 一体化便利：装载+递交+消费（早到 gap 可调）----
    task automatic run_block(input integer len, input integer wgrp,
                    input integer xgrp,
                    input integer fstb, input integer lstb, input integer early_gap,
                   input integer hdr_delay, input drain, input jit);
        begin
            load_block(len, wgrp, xgrp, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
            if (early_gap > 0) wait_beats(early_gap);
            job_hand(len, wgrp, xgrp, fstb, lstb);
            consume_block(len, wgrp, xgrp, fstb, lstb,
                          hdr_delay, drain, -1, 0, jit);
        end
    endtask

    initial begin : main
        rs1 = 21; rs2 = 22; rs3 = 23; rs4 = 24; rs5 = 25;
        bank_err_prev = 1'b0;
        for (q = 0; q < P_KC; q = q + 1) begin
            Wm0[q] = {W_WD{1'b0}}; Wm1[q] = {W_WD{1'b0}};
            Xm0[q] = {X_WD{1'b0}}; Xm1[q] = {X_WD{1'b0}};
        end
        repeat (4) @(negedge clk);
        rst = 1'b0;
        wait_beats(2);

        $display("EES_STAGE R1_BASIC config=%0dx%0d KC=%0d", P_TO, P_TN, P_KC);
        run_block(1,  0, 0, 1'b1, 1'b1, 2, 0, 6, 0);
        run_block(2,  0, 0, 1'b1, 1'b1, 1, 1, 6, 0);
        run_block(3,  0, 0, 1'b0, 1'b1, 0, 2, 6, 0);
        run_block(LSET, 0, 0, 1'b0, 1'b1, 3, 0, 8, 0);
        $display("EES_STAGE_R1 checks=%0d errors=%0d", checks, errors);

        $display("EES_STAGE R2_PINGPONG config=%0dx%0d KC=%0d", P_TO, P_TN, P_KC);
        // 真交叠：g0 消费中同时装载 g1（TDP 无冲突的实弹场景）
        load_block(6, 0, 0, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        job_hand(6, 0, 0, 1'b1, 1'b1);
        fork
            begin : r2c
                consume_block(6, 0, 0, 1'b1, 1'b1, 0, 6, -1, 0, 1);
            end
            begin : r2l
                wait_beats(4);                     //字流中段开始装 g1
                load_block(6, 1, 1, 1, 1, 8'hFF, 8'hFF, 8'hFF, 1);
            end
        join
        run_block(6, 1, 1, 1'b0, 1'b1, 0, 0, 4, 1);
        // 回绕：g0 重装新数据（陈旧数据必须被覆盖）
        run_block(5, 0, 0, 1'b0, 1'b1, 1, 0, 5, 0);
        $display("EES_STAGE_R2 checks=%0d errors=%0d", checks, errors);

        $display("EES_STAGE R3_TIMING config=%0dx%0d KC=%0d", P_TO, P_TN, P_KC);
        // 早到：装完等 20+ 拍才递交
        run_block(7, 0, 0, 1'b1, 1'b1, 21, 3, 6, 0);
        // 恰好：ld_done 后下一拍递交（run_block early_gap=0）
        run_block(7, 1, 1, 1'b0, 1'b1, 0, 0, 6, 0);
        // 晚到（重装压顶）：先递交作业，再重装同组——首拍清 loaded 必须
        // 把已呈现的 header 压回，装载全程 blk_valid=0，收口后才准升起
        job_hand(7, 0, 0, 1'b0, 1'b1);
        wait_beats(3);
        hold_check_en = 1'b1;
        load_block(7, 0, 0, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        hold_check_en = 1'b0;
        wait_beats(3);
        if (!blk_valid) begin
            errors = errors + 1;
            $display("EES_ERR [%0t] gating: blk_valid low after load", $time);
        end
        consume_block(7, 0, 0, 1'b0, 1'b1, 1, 6, -1, 0, 0);
        $display("EES_STAGE_R3 checks=%0d errors=%0d", checks, errors);

        $display("EES_STAGE R4_JITTER config=%0dx%0d KC=%0d", P_TO, P_TN, P_KC);
        // 确定性停拍：首字前/中字/末字前（单元层 KC=8 时 L9 钳位，末停拍自然退化）
        load_block(L9, 0, 0, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        job_hand(L9, 0, 0, 1'b1, 1'b1);
        consume_block(L9, 0, 0, 1'b1, 1'b1, 0, 6, 0, 3, 0);
        load_block(L9, 1, 1, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        job_hand(L9, 1, 1, 1'b0, 1'b1);
        consume_block(L9, 1, 1, 1'b0, 1'b1, 0, 6, 4, 2, 0);
        load_block(L9, 0, 0, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        job_hand(L9, 0, 0, 1'b0, 1'b1);
        consume_block(L9, 0, 0, 1'b0, 1'b1, 0, 6, 8, 4, 0);
        // 随机抖动长块
        load_block(LLONG, 1, 1, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        job_hand(LLONG, 1, 1, 1'b0, 1'b1);
        consume_block(LLONG, 1, 1, 1'b0, 1'b1, 0, 6, -1, 0, 1);
        $display("EES_STAGE_R4 checks=%0d errors=%0d", checks, errors);

        $display("EES_STAGE R5_INDEPGP config=%0dx%0d KC=%0d", P_TO, P_TN, P_KC);
        // W 驻留 g0；X 交替 g0→g1（独立选择位）
        load_block(8, 0, 0, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);   //W0+X0
        load_block(8, 0, 1, 0, 1, 8'hFF, 8'hFF, 8'hFF, 0);   //仅 X→g1
        job_hand(8, 0, 0, 1'b1, 1'b0);
        consume_block(8, 0, 0, 1'b1, 1'b0, 0, 5, -1, 0, 0);
        job_hand(8, 0, 1, 1'b0, 1'b1);
        consume_block(8, 0, 1, 1'b0, 1'b1, 0, 5, -1, 0, 0);
        // 再来一次 W 驻留读（第三次读 g0 的 W，数据必须未动）
        load_block(8, 0, 0, 0, 1, 8'hFF, 8'hFF, 8'hFF, 0);   //仅 X→g0（覆盖旧 X0）
        job_hand(8, 0, 0, 1'b0, 1'b1);
        consume_block(8, 0, 0, 1'b0, 1'b1, 0, 5, -1, 0, 0);
        $display("EES_STAGE_R5 checks=%0d errors=%0d", checks, errors);

        $display("EES_STAGE R6_LANEWE config=%0dx%0d KC=%0d", P_TO, P_TN, P_KC);
        // 全字先写，再部分 lane 重写 → 读回应为合并
        load_block(6, 0, 0, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        load_block(6, 0, 0, 1, 1, 8'h0F, 8'h3C, 8'hC3, 0);   //重写（部分 lane）
        job_hand(6, 0, 0, 1'b1, 1'b1);
        consume_block(6, 0, 0, 1'b1, 1'b1, 0, 5, -1, 0, 0);
        $display("EES_STAGE_R6 checks=%0d errors=%0d", checks, errors);

        $display("EES_STAGE R7_OFFBY1 config=%0dx%0d KC=%0d", P_TO, P_TN, P_KC);
        run_block(1, 0, 0, 1'b1, 1'b1, 0, 0, 4, 0);           //首=末同字
        run_block(2, 1, 1, 1'b1, 1'b1, 0, 0, 4, 0);
        run_block(P_KC-1, 0, 0, 1'b1, 1'b0, 0, 0, 5, 0);      //顶地址边界
        run_block(P_KC,   1, 1, 1'b0, 1'b1, 0, 0, 6, 0);
        // 背靠背最小余量：drain=4，job 立即跟上（换组拍边界）
        load_block(5, 0, 0, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        job_hand(5, 0, 0, 1'b1, 1'b0);
        consume_block(5, 0, 0, 1'b1, 1'b0, 0, 4, -1, 0, 0);
        load_block(5, 1, 1, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        job_hand(5, 1, 1, 1'b0, 1'b1);
        consume_block(5, 1, 1, 1'b0, 1'b1, 0, 4, -1, 0, 0);
        $display("EES_STAGE_R7 checks=%0d errors=%0d", checks, errors);

        $display("EES_STAGE R8_DISCIPLINE config=%0dx%0d KC=%0d", P_TO, P_TN, P_KC);
        // 活流中拒绝写读选组：消费者第 4 字前停 30 拍（流冻结但 busy=1），
        // 期间向 g0 打写拍——wr_ready 必须为 0（不发生任何访问：合法反压，
        // 非冲突访问，TB 纪律），bank_err 不得置位，另一组仍可装
        load_block(L9, 0, 0, 1, 1, 8'hFF, 8'hFF, 8'hFF, 0);
        job_hand(L9, 0, 0, 1'b1, 1'b1);
        fork
            begin : r8c
                consume_block(L9, 0, 0, 1'b1, 1'b1, 0, 6, 4, 30, 0);
            end
            begin : r8w
                wait_beats(10);
                ld_w_grp = 1'b0; ld_x_grp = 1'b0;
                for (t = 0; t < 3; t = t + 1) begin
                    @(negedge clk);
                    wr_valid = 1'b1; wr_is_x = 1'b0; wr_first = 1'b1;
                    wr_be = 8'hFF; wr_data = 64'hDEAD_BEEF_DEAD_BEEF;
                    @(posedge clk);
                    if (wr_ready) begin
                        errors = errors + 1;
                        $display("EES_ERR [%0t] refusal: wr_ready=1 to read-selected g0", $time);
                    end
                end
                @(negedge clk);
                wr_valid = 1'b0; wr_first = 1'b0;
                if (bank_err) begin
                    errors = errors + 1;
                    $display("EES_ERR [%0t] refusal wrongly raised bank_err", $time);
                end
                if (!w_ld_ok[1] || !x_ld_ok[1]) begin
                    errors = errors + 1;
                    $display("EES_ERR [%0t] ld_ok[1] should be 1 during g0 stream", $time);
                end
            end
        join
        $display("EES_STAGE_R8 checks=%0d errors=%0d", checks, errors);

        // ---- 守恒与总账 ----
        if (jobs_fed !== jobs_hdr || jobs_hdr !== jobs_done) begin
            errors = errors + 1;
            $display("EES_ERR conservation jobs fed=%0d hdr=%0d done=%0d",
                     jobs_fed, jobs_hdr, jobs_done);
        end
        if (words_checked !== EXP_WORDS) begin
            errors = errors + 1;
            $display("EES_ERR conservation words checked=%0d exp=%0d",
                     words_checked, EXP_WORDS);
        end
        $display("EES_SUMMARY checks=%0d errors=%0d config=%0dx%0d KC=%0d jobs=%0d words=%0d ld_done=%0d",
                 checks, errors, P_TO, P_TN, P_KC, jobs_fed, words_checked, ld_done_seen);
        if (errors == 0)
            $display("EES_VIVADO_RESULT PASS");
        else
            $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

endmodule
