/************************************************************************
 * File Name     : tb_yolo_gemm_top_axi.sv
 * Developer     : LSL
 * Date          : 2026-09-19
 * Module Name   : tb_yolo_gemm_top_axi
 * Description   : run21 / B1 上板第一门：yolo_gemm_top V1.0（AXI-Lite
 *                 寄存器文件 + yolo_gemm_core V1.1 + Y 捕获 BMG IP）
 *                 块级仿真门。TB = PS 角色：纯 AXI-Lite 读写驱动
 *                 （上板即同一寄存器序列），core 信号不驱动、只观察。
 *
 *   场景（S1-S4）：
 *     S1 全 8x16 tile，K=64 单块（first=last=1），act=1（LUT 图样
 *        A: i^A5）——装载/参数/LUT/start/轮询/回读全链 128 坐标对拍。
 *     S2 掩码 tile：row_valid=0x5A / n_mask=0x0F0F，K=40，act=0
 *        （线性旁路）——y_count=32，仅有效坐标回读；掩外坐标保持
 *        S1 旧值（无幻影写证明）。
 *     S3 双块 K=96（48+48 ping-pong grp0/grp1，first/last 链）——
 *        跨块累加 + 装载与计算并发（grp1 装载落在 grp0 计算窗内）。
 *     S4 错误注入与清扫：start-while-busy（start_err）；计算窗内对
 *        读组 WCTL（wr_pend 悬挂）→ 再 WCTL（beat 丢弃 ld_pend_err）；
 *        err_clr / soft_rst 后状态归零。
 *
 *   独立 oracle（与 DUT 不同构，逐字承袭 run15）：INT64 镜像累加 +
 *     截断除 + floor 修正 + RNE(ties-even) + 饱和 + LUT/旁路。
 *     活流检查（eq 队列，r 主序 n 次序）+ tile_done 后 RAM 回读
 *     （eqm 矩阵，按坐标）双重对拍。
 *
 *   驱动纪律（承袭）：每 negedge 驱动；$random 无符号模且上限预计算；
 *     内层循环禁用外层变量；done 事件即消费；bready/rready 常挂。
 *     TB 不制造 TDP 冲突访问（装载只在目标组非读选中时递交——组安
 *     全由 DUT wr_ready 门控，TB 悬挂拍为 S4 故意注入的 err 用例，
 *     该拍在 rd_busy 释放后被接收属设计语义，README 有注）。
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : run21 初版（B1 板级正典序列冻结件）。
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_gemm_top_axi;

    localparam integer P_TO = 8;
    localparam integer P_TN = 16;

    // ---- 时钟/复位 ----
    reg clk, rstn;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- AXI4-Lite 主侧（PS 角色）----
    reg  [31:0] awaddr, wdata;
    reg  [2:0]  awprot;
    reg         awvalid, wvalid;
    wire        awready, wready, bvalid;
    reg         bready;
    reg  [3:0]  wstrb;
    wire [1:0]  bresp;
    reg  [31:0] araddr;
    reg  [2:0]  arprot;
    reg         arvalid;
    wire        arready, rvalid;
    reg         rready;
    wire [31:0] rdata;
    wire [1:0]  rresp;

    initial begin
        bready = 1'b1; rready = 1'b1;   //常挂（PS 风格）
    end

    // ---- DUT ----
    yolo_gemm_top u_dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(awprot), .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(arprot), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready)
    );

    // ---- core 观察线（DUT 顶层 wire，不穿透两层）----
    wire        obs_y_valid = u_dut.core_y_valid;
    wire signed [7:0] obs_y = u_dut.core_y;
    wire [2:0]  obs_y_row   = u_dut.core_y_row;
    wire [3:0]  obs_y_col   = u_dut.core_y_col;
    wire        obs_bank_err = u_dut.core_bank_err;
    wire        obs_proto_err = u_dut.core_proto_err;

    // ---- 记账 ----
    integer checks, errors, rb_checks;
    integer tiles_started, tiles_done;
    integer y_cnt, y_exp_cnt;
    integer cyc;
    always @(negedge clk) cyc = cyc + 1;

    // ---- TB 侧镜像（oracle 数据源，永不读 DUT）----
    reg signed [7:0]  Wm [0:P_TO-1][0:1023];
    reg signed [7:0]  Xm [0:P_TN-1][0:1023];
    reg signed [31:0] PB [0:P_TO-1];
    reg signed [31:0] PM [0:P_TO-1];
    reg        [5:0]  PS [0:P_TO-1];
    reg        [7:0]  lut_exp [0:255];
    reg signed [7:0]  eqm [0:P_TO-1][0:P_TN-1];

    // ---- 独立 requant 模型（run15 逐字）----
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

    // ---- 期望队列（活流对拍，r 主序 n 次序）----
    integer eq_wp, eq_rp;
    reg signed [7:0]       eq_y [0:65535];
    reg [2:0]              eq_r [0:65535];
    reg [3:0]              eq_n [0:65535];
    reg act_exp;
    reg rst_d;
    always @(posedge clk) rst_d <= ~rstn;

    // ---- 检查器：每 negedge 全覆盖（run15 纪律）----
    reg signed [7:0] eqt;
    reg [7:0] eadt;
    reg signed [7:0] eexp;
    reg proto_prev, bank_err_prev;
    always @(negedge clk) begin
        if (rst_d) begin
            if (obs_y_valid) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] y_valid during rst", $time);
            end
        end else begin
            if (obs_proto_err && !proto_prev) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] proto_err", $time);
            end
            if (obs_bank_err && !bank_err_prev) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] bank_err", $time);
            end
            if (obs_y_valid) begin
                if (eq_rp >= eq_wp) begin
                    errors = errors + 1;
                    $display("EES_TOP_ERR [%0t] y_valid without expectation",
                             $time);
                end else begin
                    eqt  = eq_y[eq_rp];
                    eadt = sat_addr(eqt);
                    eexp = act_exp ? $signed(lut_exp[eadt]) : eqt;
                    if (^obs_y === 1'bx) begin
                        errors = errors + 1;
                        $display("EES_TOP_ERR [%0t] X on y", $time);
                    end else if (obs_y !== eexp) begin
                        errors = errors + 1;
                        $display("EES_TOP_ERR [%0t] y=%0d want=%0d @(r=%0d n=%0d)",
                                 $time, obs_y, eexp, eq_r[eq_rp], eq_n[eq_rp]);
                    end else if ((obs_y_row !== eq_r[eq_rp]) ||
                                 (obs_y_col !== eq_n[eq_rp])) begin
                        errors = errors + 1;
                        $display("EES_TOP_ERR [%0t] coord (%0d,%0d) want (%0d,%0d)",
                                 $time, obs_y_row, obs_y_col,
                                 eq_r[eq_rp], eq_n[eq_rp]);
                    end else begin
                        checks = checks + 1;
                    end
                    y_cnt = y_cnt + 1;
                    eq_rp = eq_rp + 1;
                end
            end
        end
        proto_prev   = obs_proto_err;
        bank_err_prev= obs_bank_err;
    end

    // ---- tile_done 计（观察线经 STATUS 同步副本，非脉冲敏感改用粘滞轮询）----

    // ---- AXI 基础任务（带 op 心跳取证）----
    integer wop_cnt, rop_cnt;
    task axi_write(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            awaddr = a; awprot = 3'd0; awvalid = 1'b1;
            wdata = d; wstrb = 4'hF; wvalid = 1'b1;
            while (!bvalid) @(negedge clk);
            if (bresp !== 2'b00) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] write 0x%03x SLVERR", $time, a);
            end
            awvalid = 1'b0; wvalid = 1'b0;
            @(negedge clk);
            wop_cnt = wop_cnt + 1;
            if (wop_cnt % 64 == 0)
                $display("EES_HB wop=%0d cyc=%0d t=%0t", wop_cnt, cyc, $time);
        end
    endtask

    task axi_read(input [31:0] a, output [31:0] d);
        begin
            @(negedge clk);
            araddr = a; arprot = 3'd0; arvalid = 1'b1;
            while (!rvalid) @(negedge clk);
            d = rdata;
            if (rresp !== 2'b00) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] read 0x%03x SLVERR", $time, a);
            end
            arvalid = 1'b0;
            @(negedge clk);
            rop_cnt = rop_cnt + 1;
        end
    endtask

    task gapn(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    // ---- 寄存器地址 ----
    localparam [31:0] A_ID     = 32'h00, A_CTRL   = 32'h04, A_STATUS = 32'h08;
    localparam [31:0] A_GEOM   = 32'h0C, A_ROWVAL = 32'h10, A_NMASK  = 32'h14;
    localparam [31:0] A_JOBCFG = 32'h18, A_LDGRP  = 32'h1C, A_P_BIAS = 32'h20;
    localparam [31:0] A_P_M    = 32'h24, A_P_SH   = 32'h28, A_PCTL   = 32'h2C;
    localparam [31:0] A_WDATA  = 32'h30, A_WDATA2 = 32'h34, A_WCTL   = 32'h38;
    localparam [31:0] A_LDSTAT = 32'h3C, A_LDLEN  = 32'h40, A_LUTD   = 32'h44;
    localparam [31:0] A_YSTAT  = 32'h48, A_YADDR  = 32'h4C, A_YDATA  = 32'h50;

    // ---- task/主流程共用暂存（声明先于所有使用点，xsim VRFC 10-3380）----
    reg [31:0] rd;
    integer guard2;
    reg [31:0] st2;

    // ---- 数据准备（随机流纪律承袭 run15）----
    integer rs1, rs2, rs3, rs4;
    reg signed [7:0] cb [0:5];
    integer kk, ii, r, n, li;
    reg signed [7:0] wv, xv;
    reg [63:0] beat64;

    task fill_wx(input integer K);
        begin
            for (kk = 0; kk < K; kk = kk + 1) begin
                for (ii = 0; ii < P_TN; ii = ii + 1) begin
                    if (ii < P_TO) begin
                        wv = ({$random(rs1)} % 16 == 0) ? cb[{$random(rs2)} % 6]
                            : $signed({$random(rs3)} % 256) - 128;
                        Wm[ii][kk] = wv;
                    end
                    xv = ({$random(rs2)} % 16 == 0) ? cb[{$random(rs1)} % 6]
                        : $signed({$random(rs4)} % 256) - 128;
                    Xm[ii][kk] = xv;
                end
            end
        end
    endtask

    task load_params;
        begin
            for (r = 0; r < P_TO; r = r + 1) begin
                PB[r] = $signed({$random(rs2)} % 32'h08000000) - 32'sh04000000;
                PM[r] = ({$random(rs3)} % 4 == 0) ? -32'sh40000000 : 32'sh40000000;
                if ({$random(rs4)} % 8 == 0) PM[r] = 32'sd1;
                PS[r] = {$random(rs1)} % 63;
                axi_write(A_P_BIAS, PB[r]);
                axi_write(A_P_M,    PM[r]);
                axi_write(A_P_SH,   {26'd0, PS[r]});
                axi_write(A_PCTL,   {29'd0, 1'b1, r[2:0]});
            end
        end
    endtask

    task lut_load_a;        //图样 A：i ^ A5
        begin
            for (li = 0; li < 256; li = li + 1) begin
                lut_exp[li] = li[7:0] ^ 8'hA5;
                axi_write(A_LUTD, {8'd0, li[7:0], lut_exp[li]});
            end
        end
    endtask

    // ---- 装一块（AXI 版 bank_load：每 k 三拍，WDATA/WDATA2/WCTL）----
    task bank_load_axi(input integer len, input integer k0, input integer grp);
        reg [31:0] dummy;
        begin
            axi_write(A_LDGRP, {30'd0, grp[0], grp[0]});
            for (kk = 0; kk < len; kk = kk + 1) begin
                // W 整字拍（bit11=last, bit10=first, 9:2=be, 1=x_hi, 0=is_x）
                beat64 = 64'd0;
                for (ii = 0; ii < P_TO; ii = ii + 1)
                    beat64[8*ii +: 8] = Wm[ii][k0+kk];
                axi_write(A_WDATA,  beat64[31:0]);
                axi_write(A_WDATA2, beat64[63:32]);
                axi_write(A_WCTL, {20'd0, 1'b0, (kk == 0), 8'hFF, 1'b0, 1'b0});
                // X lo
                beat64 = 64'd0;
                for (ii = 0; ii < 8; ii = ii + 1)
                    beat64[8*ii +: 8] = Xm[ii][k0+kk];
                axi_write(A_WDATA,  beat64[31:0]);
                axi_write(A_WDATA2, beat64[63:32]);
                axi_write(A_WCTL, {20'd0, 1'b0, 1'b0, 8'hFF, 1'b0, 1'b1});
                // X hi（末拍 last）
                beat64 = 64'd0;
                for (ii = 0; ii < 8; ii = ii + 1)
                    beat64[8*ii +: 8] = Xm[ii+8][k0+kk];
                axi_write(A_WDATA,  beat64[31:0]);
                axi_write(A_WDATA2, beat64[63:32]);
                axi_write(A_WCTL, {20'd0, (kk == len-1), 1'b0, 8'hFF, 1'b1, 1'b1});
            end
            // ld_done 粘滞 + 长度对账（ld_done 脉冲在末拍接受后 2-3 拍，
            // 轮询而非单读，杜绝早读竞态）
            guard2 = 0; rd = 32'd0;
            while (!rd[3] && guard2 < 100) begin
                axi_read(A_STATUS, rd);
                guard2 = guard2 + 1;
            end
            if (!rd[3]) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] ld_done sticky missing len=%0d",
                         $time, len);
            end
            axi_read(A_LDLEN, dummy);
            if (dummy[12:0] != len[12:0]) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] ld_w_len=%0d exp=%0d",
                         $time, dummy[12:0], len);
            end
            if (dummy[25:13] != len[12:0]) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] ld_x_len=%0d exp=%0d",
                         $time, dummy[25:13], len);
            end
        end
    endtask

    // ---- 计算期望（活流队列 + 回读矩阵双写）----
    task push_expected(input integer K,
                       input [P_TO-1:0] rvm, input [P_TN-1:0] nmm);
        reg signed [63:0] oacc;
        reg signed [7:0]  q7;
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
                            eq_r[eq_wp] = r[2:0];
                            eq_n[eq_wp] = n[3:0];
                            eqm[r][n]   = q7;
                            eq_wp = eq_wp + 1;
                        end
                    end
                end
            end
        end
    endtask

    // ---- start 递交 + 等 tile_done ----
    task run_job_wait(input [12:0] jlen, input act, input fbit, input lbit,
                      input wgrp, input xgrp);
        reg [31:0] st;
        integer guard;
        begin
            tiles_started = tiles_started + 1;
            axi_write(A_GEOM,   {19'd0, jlen});
            axi_write(A_JOBCFG, {27'd0, xgrp, wgrp, lbit, fbit, act});
            axi_write(A_CTRL,   32'd1);
            guard = 0;
            st = 32'd0;                    //至少读一次（哨兵 0，非全 1）
            axi_read(A_STATUS, st);
            while (!(st[0] == 1'b0 && st[5]) && guard < 100000) begin
                axi_read(A_STATUS, st);
                guard = guard + 1;
            end
            if (!st[5]) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] tile_done poll timeout STATUS=%08x",
                         $time, st);
            end
            if (st[6] || st[7] || st[8] || st[9]) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] err bits in STATUS %08x",
                         $time, st);
            end
            gapn(8);      //尾流水/粘滞收口
            tiles_done = tiles_done + 1;
        end
    endtask

    // ---- 回读对拍（按坐标；ycnt_scale = 累计 tile 数×矩阵基数）----
    task readback_check(input [P_TO-1:0] rvm, input [P_TN-1:0] nmm,
                        input integer ycnt_scale);
        reg [31:0] d;
        reg signed [7:0] got, exp8;
        reg [7:0] eadt;
        begin
            for (r = 0; r < P_TO; r = r + 1) begin
                if (rvm[r]) begin
                    for (n = 0; n < P_TN; n = n + 1) begin
                        if (nmm[n]) begin
                            axi_write(A_YADDR, {25'd0, r[2:0], n[3:0]});
                            gapn(2);          //BMG 读延迟 1 + 缓冲
                            axi_read(A_YDATA, d);
                            got  = $signed(d[7:0]);
                            exp8 = act_exp
                                 ? $signed(lut_exp[sat_addr(eqm[r][n])])
                                 : eqm[r][n];
                            if (got !== exp8) begin
                                errors = errors + 1;
                                $display("EES_TOP_ERR [%0t] RB r=%0d n=%0d got=%0d want=%0d",
                                         $time, r, n, got, exp8);
                            end else begin
                                rb_checks = rb_checks + 1;
                            end
                        end
                    end
                end
            end
            // y_count 对账
            axi_read(A_YSTAT, d);
            y_exp_cnt = 0;
            for (r = 0; r < P_TO; r = r + 1)
                if (rvm[r])
                    for (n = 0; n < P_TN; n = n + 1)
                        if (nmm[n]) y_exp_cnt = y_exp_cnt + 1;
            y_exp_cnt = y_exp_cnt * ycnt_scale;
            if (d[15:0] != y_exp_cnt[15:0]) begin
                errors = errors + 1;
                $display("EES_TOP_ERR [%0t] y_count=%0d exp=%0d",
                         $time, d[15:0], y_exp_cnt);
            end
        end
    endtask

    // ---- 主流程 ----

    initial begin
        // 看门狗
        cyc = 0; checks = 0; errors = 0; rb_checks = 0;
        tiles_started = 0; tiles_done = 0; y_cnt = 0;
        eq_wp = 0; eq_rp = 0;
        wop_cnt = 0; rop_cnt = 0;
        rs1 = 16'h1111; rs2 = 16'h2222; rs3 = 16'h3333; rs4 = 16'h4444;
        cb[0] = -8'sd128; cb[1] = -8'sd1; cb[2] = 8'sd0;
        cb[3] = 8'sd1;    cb[4] = 8'sd127; cb[5] = -8'sd128;

        rstn = 1'b0;
        awvalid = 0; wvalid = 0; arvalid = 0;
        repeat (12) @(negedge clk);
        rstn = 1'b1;
        gapn(4);

        // ---- ID 检查 ----
        axi_read(A_ID, rd);
        if (rd !== 32'h2026_0919) begin
            errors = errors + 1;
            $display("EES_TOP_ERR ID=0x%08x exp 0x20260919", rd);
        end

        // ================= S1 =================
        $display("EES_TOP_STAGE S1 full 8x16 K=64 act=1");
        act_exp = 1'b1;
        lut_load_a;
        fill_wx(64);
        load_params;
        push_expected(64, 8'hFF, 16'hFFFF);
        axi_write(A_ROWVAL, 32'hFF);
        axi_write(A_NMASK,  32'hFFFF);
        bank_load_axi(64, 0, 0);
        run_job_wait(64, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        readback_check(8'hFF, 16'hFFFF, 1);
        $display("EES_TOP_STAGE S1 done checks=%0d rb=%0d errs=%0d",
                 checks, rb_checks, errors);

        // ================= S2 =================
        $display("EES_TOP_STAGE S2 masked 0x5A/0x0F0F K=40 act=0");
        act_exp = 1'b0;
        fill_wx(40);
        load_params;
        push_expected(40, 8'h5A, 16'h0F0F);
        axi_write(A_ROWVAL, 32'h5A);
        axi_write(A_NMASK,  32'h0F0F);
        bank_load_axi(40, 0, 1);
        run_job_wait(40, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1);
        readback_check(8'h5A, 16'h0F0F, 1);
        // 掩外坐标不被幻影写：addr 0（r=0 掩外）应保持 S1 值
        begin : s2_stale
            reg signed [7:0] stale_exp;
            reg [31:0] sd;
            stale_exp = lut_exp[sat_addr(eqm[0][0])];   //S1 act=1 语义
            axi_write(A_YADDR, 32'd0);
            gapn(2);
            axi_read(A_YDATA, sd);
            if ($signed(sd[7:0]) !== stale_exp) begin
                errors = errors + 1;
                $display("EES_TOP_ERR S2 phantom write @0: got=%0d want(S1)=%0d",
                         sd[7:0], stale_exp);
            end else rb_checks = rb_checks + 1;
        end
        $display("EES_TOP_STAGE S2 done checks=%0d rb=%0d errs=%0d",
                 checks, rb_checks, errors);

        // ================= S3 =================
        $display("EES_TOP_STAGE S3 two-block K=96 ping-pong");
        act_exp = 1'b1;
        fill_wx(96);
        load_params;
        push_expected(96, 8'hFF, 16'hFFFF);
        axi_write(A_ROWVAL, 32'hFF);
        axi_write(A_NMASK,  32'hFFFF);
        // 块 0：grp0，act=1 first=1 last=0（JOBCFG bit0=act bit1=first）
        bank_load_axi(48, 0, 0);
        axi_write(A_GEOM,   32'd48);
        axi_write(A_JOBCFG, 32'd3);
        axi_write(A_CTRL,   32'd1);
        // 等 job_pend 清（feeder 收单）
        guard2 = 0;
        st2 = 32'hFFFFFFFF;
        while (st2[1] && guard2 < 1000) begin
            axi_read(A_STATUS, st2); guard2 = guard2 + 1;
        end
        if (st2[1]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S3 job0 pend never cleared");
        end
        // 块 1：grp1 装载落在 grp0 计算窗内（并发装载）
        bank_load_axi(48, 48, 1);
        // 递交末块 job（last=1）并等收口
        run_job_wait(48, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        readback_check(8'hFF, 16'hFFFF, 1);
        $display("EES_TOP_STAGE S3 done checks=%0d rb=%0d errs=%0d",
                 checks, rb_checks, errors);

        // ================= S4 =================
        // 双 tile 队列 + 计算窗错误注入 + 清理：
        //   K=192 单块 tile，start#1 开跑 tile1、start#2 busy 中排队成
        //   完整第二 tile（同数据同参数→两次独立 128 流）、start#3 撞
        //   递交槽拒绝；流窗内 WCTL 悬挂/丢弃置错；err_clr 保 done 粘
        //   滞；soft_rst 全清且 ID 不变。
        $display("EES_TOP_STAGE S4 two-tile queue + error injection + cleanup");
        act_exp = 1'b1;
        fill_wx(192);
        load_params;
        push_expected(192, 8'hFF, 16'hFFFF);      //tile1 期望流
        push_expected(192, 8'hFF, 16'hFFFF);      //tile2 期望流（同数据）
        bank_load_axi(192, 0, 0);
        axi_write(A_GEOM,   32'd192);
        axi_write(A_JOBCFG, 32'd7);               //act|first|last, grp0
        tiles_started = tiles_started + 2;
        // start#1：tile1 开跑
        axi_write(A_CTRL,   32'd1);
        gapn(8);                                   //入流窗（rd busy）
        // start#2：busy 中排队 → job_pend=1
        axi_write(A_CTRL,   32'd1);
        gapn(4);
        axi_read(A_STATUS, rd);
        if (!rd[1]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 job_pend not set after queue (STATUS=%03x)", rd);
        end
        // start#3：递交槽占用 → 拒绝并置 start_err，队列不受扰
        axi_write(A_CTRL,   32'd1);
        gapn(4);
        axi_read(A_STATUS, rd);
        if (!rd[9]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 start_err not flagged (STATUS=%03x)", rd);
        end
        if (!rd[1]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 refused start clobbered queue (STATUS=%03x)", rd);
        end
        // (a) 计算窗内对读组 WCTL：悬挂 → 丢弃 → ld_pend_err
        //     WCTL be=FF（bits9:2=0xFF → 0x3FC，无 first/last）。
        //     悬挂拍落点=grp0 w_wa=192 ≥ job_len，tile2 不读——无污染。
        axi_write(A_LDGRP,  32'd0);
        axi_write(A_WDATA,  32'hDEAD_BEEF);
        axi_write(A_WDATA2, 32'hCAFE_F00D);
        axi_write(A_WCTL,   32'h0000_03FC);
        axi_read(A_STATUS, rd);
        if (!rd[2]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 wr_pend not held (STATUS=%03x)", rd);
        end
        axi_write(A_WCTL,   32'h0000_03FC);
        axi_read(A_STATUS, rd);
        if (!rd[8]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 ld_pend_err not flagged (STATUS=%03x)", rd);
        end
        // (b) 等双 tile 全收口：busy==0 && tile_done && job_pend==0
        //     （tile1→tile2 间隙 busy 短暂为 0，靠 job_pend 区分）
        guard2 = 0; st2 = 32'd0;
        while ((st2[0] || !st2[5] || st2[1]) && guard2 < 100000) begin
            axi_read(A_STATUS, st2); guard2 = guard2 + 1;
        end
        if (st2[0] || !st2[5] || st2[1]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 dual-tile timeout (STATUS=%03x)", st2);
        end
        if (st2[6] || st2[7]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 bank/proto err (STATUS=%03x)", st2);
        end
        if (st2[2]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 dropped beat never drained (STATUS=%03x)", st2);
        end
        gapn(8);
        tiles_done = tiles_done + 2;
        // tile2 递交(first=1)清 y_count → 终值=tile2 单 tile 计数 128
        readback_check(8'hFF, 16'hFFFF, 1);
        // (c) err_clr 清 err 位、不清 done 粘滞
        axi_write(A_CTRL, 32'd4);
        axi_read(A_STATUS, rd);
        if (rd[8] || rd[9]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 err_clr failed (STATUS=%03x)", rd);
        end
        if (!rd[5]) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 err_clr clobbered tile_done");
        end
        // (d) soft_rst：粘滞/计数清零、ID 不变
        axi_write(A_CTRL, 32'd2);
        gapn(8);
        axi_read(A_STATUS, rd);
        if (rd !== 32'd0) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 soft_rst STATUS=%03x exp 0", rd);
        end
        axi_read(A_YSTAT, rd);
        if (rd[15:0] !== 16'd0) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 soft_rst y_count=%0d", rd[15:0]);
        end
        axi_read(A_ID, rd);
        if (rd !== 32'h2026_0919) begin
            errors = errors + 1;
            $display("EES_TOP_ERR S4 ID changed after soft_rst");
        end
        $display("EES_TOP_STAGE S4 done checks=%0d rb=%0d errs=%0d",
                 checks, rb_checks, errors);

        // ---- 守恒对账 ----
        if (eq_rp != eq_wp) begin
            errors = errors + 1;
            $display("EES_TOP_ERR unsent expectations %0d", eq_wp - eq_rp);
        end
        if (tiles_started != tiles_done) begin
            errors = errors + 1;
            $display("EES_TOP_ERR tiles started=%0d done=%0d",
                     tiles_started, tiles_done);
        end

        $display("EES_TOP_INFO tiles=%0d/%0d y=%0d", tiles_started,
                 tiles_done, y_cnt);
        if (errors == 0)
            $display("EES_SUMMARY checks=%0d rb_checks=%0d errors=0 PASS",
                     checks, rb_checks);
        else
            $display("EES_SUMMARY checks=%0d rb_checks=%0d errors=%0d FAIL",
                     checks, rb_checks, errors);
        $display("EES_VIVADO_RESULT %s", (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

    // 看门狗
    initial begin
        #20_000_000;
        $display("EES_TOP_ERR watchdog timeout");
        $display("EES_SUMMARY checks=%0d rb_checks=%0d errors=999 FAIL",
                 checks, rb_checks);
        $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

endmodule
