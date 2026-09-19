/************************************************************************
 * File Name     : tb_yolo_gemm_b3_bridge.sv
 * Developer     : LSL
 * Date          : 2026-09-19
 * Module Name   : tb_yolo_gemm_b3_bridge
 * Description   : run26 / B3 第一门：yolo_gemm_top V1.1（B3 DMA 桥：
 *                 AXI4-Stream 装载从口三拍节律 + y 回收流主口 8y->64b
 *                 打包/FIFO/tlast + BRGSTAT/STALLCNT）块级仿真门。
 *                 TB = PS 角色（AXI-Lite，逐字承袭 run21）+ DMA MM2S
 *                 BFM（s_axis_ld 驱动，按合同 §3.2 节律打包）+ y 接收
 *                 BFM（m_axis_y 收集，逐字节对拍 + 每 tile 128B tlast）。
 *
 *   场景（S1-S7，合同 1_docs/yolo_b3_dma_gemm_contract_20260919.md）：
 *     S1 槽路径回归：B1 S1 正典（K=64 act=1 全 tile）——双源共存下
 *        B1 语义零漂移；y 流同时双检（ycap 回读 + 流字节）。
 *     S2 流路径单块：DMA BFM 装载 K=64（first/last/节律/TLAST 全走
 *        桥）→ job → y 流 + ycap 双对拍。
 *     S3 双组重叠装载：块0 grp0 → job0 开跑 → 块1 grp1 流装载落在
 *        计算窗内（组安全=零反压：STALLCNT 增量必须为 0）。
 *     S4 同组重载 + 随机空拍：tile1 计算中流重载 grp0（读组不安全
 *        → 反压等待）→ STALLCNT>0 证反压；读清后回 0；tile2 数据
 *        零丢失。
 *     S5 双源冲突（D4）：(a) 流窗内 WCTL → 丢弃（wr_pend 恒 0、
 *        ld_pend_err+src_conflict 置位、块数据不受扰）；(b) 槽悬挂
 *        （读组垃圾拍）+ 流等待 → src_conflict、槽排空后流零丢失。
 *     S6 tlast 错位：tlast 落 W 相拍 → tlast_err 置位、无 job、
 *        soft_rst 恢复后好块全链通过。
 *     S7 y FIFO 溢出：sink 停 3 tile（48 词 > 32 词）→ y_ovf 置位；
 *        soft_rst 清 FIFO、sink 放行、重跑 tile 流全对（恢复性）。
 *
 *   驱动纪律（逐字承袭 run21）：每 negedge 驱动；$random 无符号模且
 *     上限预计算；内层循环禁用外层变量种子；done 事件即消费；
 *     bready/rready 常挂。TB 不制造 TDP 冲突访问（组安全由 DUT
 *     wr_ready/tready 门控，反压等待为设计语义）。
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : run26 初版（B3 桥正典序列冻结件）。
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_gemm_b3_bridge;

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

    // ---- AXI4-Stream：DMA MM2S BFM（装载）+ y 接收 BFM ----
    reg  [63:0] s_axis_ld_tdata;
    reg         s_axis_ld_tvalid;
    wire        s_axis_ld_tready;
    reg         s_axis_ld_tlast;
    wire [63:0] m_axis_y_tdata;
    wire        m_axis_y_tvalid;
    reg         m_axis_y_tready;
    wire        m_axis_y_tlast;

    initial begin
        bready = 1'b1; rready = 1'b1;   //常挂（PS 风格）
        s_axis_ld_tdata = 64'd0;
        s_axis_ld_tvalid = 1'b0;
        s_axis_ld_tlast = 1'b0;
        m_axis_y_tready = 1'b1;         //sink 缺省放行（S7 才停）
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
        .s_axi_rready(rready),
        .s_axis_ld_tdata(s_axis_ld_tdata), .s_axis_ld_tvalid(s_axis_ld_tvalid),
        .s_axis_ld_tready(s_axis_ld_tready), .s_axis_ld_tlast(s_axis_ld_tlast),
        .m_axis_y_tdata(m_axis_y_tdata), .m_axis_y_tvalid(m_axis_y_tvalid),
        .m_axis_y_tready(m_axis_y_tready), .m_axis_y_tlast(m_axis_y_tlast)
    );

    // ---- core 观察线（DUT 顶层 wire，不穿透两层）----
    wire        obs_y_valid = u_dut.core_y_valid;
    wire signed [7:0] obs_y = u_dut.core_y;
    wire [2:0]  obs_y_row   = u_dut.core_y_row;
    wire [3:0]  obs_y_col   = u_dut.core_y_col;
    wire        obs_bank_err = u_dut.core_bank_err;
    wire        obs_proto_err = u_dut.core_proto_err;

    // ---- 记账 ----
    integer checks, errors, rb_checks, sc_checks;
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
    reg [63:0] dma_beats [0:3071];          //3*1024 上限

    // ---- 独立 requant 模型（run15/run21 逐字）----
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

    // ---- 期望队列：eq_y 预激活值（活流检查）；eq_f 终值（流检查，
    //      推队时即定 LUT/旁路——流到达晚于场景切换，不能临时取
    //      act_exp）----
    integer eq_wp, eq_rp;
    reg signed [7:0]       eq_y [0:65535];
    reg signed [7:0]       eq_f [0:65535];
    reg [2:0]              eq_r [0:65535];
    reg [3:0]              eq_n [0:65535];
    reg act_exp;
    reg rst_d;
    always @(posedge clk) rst_d <= ~rstn;

    // ---- 活流检查器：每 negedge 全覆盖（run15/21 纪律）----
    reg signed [7:0] eqt;
    reg [7:0] eadt;
    reg signed [7:0] eexp;
    reg proto_prev, bank_err_prev;
    always @(negedge clk) begin
        if (rst_d) begin
            if (obs_y_valid) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] y_valid during rst", $time);
            end
        end else begin
            if (obs_proto_err && !proto_prev) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] proto_err", $time);
            end
            if (obs_bank_err && !bank_err_prev) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] bank_err", $time);
            end
            if (obs_y_valid) begin
                if (eq_rp >= eq_wp) begin
                    errors = errors + 1;
                    $display("EES_B3_ERR [%0t] y_valid without expectation",
                             $time);
                end else begin
                    eqt  = eq_y[eq_rp];
                    eadt = sat_addr(eqt);
                    eexp = act_exp ? $signed(lut_exp[eadt]) : eqt;
                    if (^obs_y === 1'bx) begin
                        errors = errors + 1;
                        $display("EES_B3_ERR [%0t] X on y", $time);
                    end else if (obs_y !== eexp) begin
                        errors = errors + 1;
                        $display("EES_B3_ERR [%0t] y=%0d want=%0d @(r=%0d n=%0d)",
                                 $time, obs_y, eexp, eq_r[eq_rp], eq_n[eq_rp]);
                    end else if ((obs_y_row !== eq_r[eq_rp]) ||
                                 (obs_y_col !== eq_n[eq_rp])) begin
                        errors = errors + 1;
                        $display("EES_B3_ERR [%0t] coord (%0d,%0d) want (%0d,%0d)",
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

    // ---- y 流检查器（posedge 采样：tvalid=FIFO 组合、tready=TB reg）----
    //      字内 [7:0] 为本字第 1 拍（低位先行，合同 §3.5）；tlast 必须恰
    //      落在每 tile 第 128 字节（全有效 tile 流路径合同）。
    reg        sc_en;                  //场景门（溢出段/破坏段关闭）
    integer    sc_rp;                  //eq_f 读指针
    integer    sc_bytes_tile;          //距上 tlast 的字节数
    integer    sc_words;
    integer    b;
    reg signed [7:0] sc_got, sc_want;
    always @(posedge clk) begin
        if (!rst_d && m_axis_y_tvalid && m_axis_y_tready) begin
            sc_words = sc_words + 1;
            if (sc_en) begin
                if (sc_rp + 8 > eq_wp) begin
                    errors = errors + 1;
                    $display("EES_B3_ERR [%0t] stream word beyond expectations",
                             $time);
                end else begin
                    for (b = 0; b < 8; b = b + 1) begin
                        sc_got  = $signed(m_axis_y_tdata[8*b +: 8]);
                        sc_want = eq_f[sc_rp + b];
                        if (sc_got !== sc_want) begin
                            errors = errors + 1;
                            $display("EES_B3_ERR [%0t] stream byte %0d got=%0d want=%0d",
                                     $time, sc_rp + b, sc_got, sc_want);
                        end else begin
                            sc_checks = sc_checks + 1;
                        end
                    end
                    sc_rp = sc_rp + 8;
                end
                sc_bytes_tile = sc_bytes_tile + 8;
                if (m_axis_y_tlast) begin
                    if (sc_bytes_tile != 128) begin
                        errors = errors + 1;
                        $display("EES_B3_ERR [%0t] stream tlast at %0dB (exp 128)",
                                 $time, sc_bytes_tile);
                    end
                    sc_bytes_tile = 0;
                end
            end
        end
    end

    // ---- tlast 诊断：tile_done 原始脉冲 vs y 打包/推出时序（每 tile
    //      一行 + 每次 tlast 弹出一行——S7 mid-tile 128B 取证用）----
    always @(posedge clk) begin
        if (rstn && u_dut.core_tile_done_w)
            $display("EES_TL tile_done t=%0t wv_d=%0b wv_r=%0b wtl_r=%0b ypk_cnt=%0d fifo_cnt=%0d",
                     $time, u_dut.ypk_wv_d, u_dut.ypk_wv_r, u_dut.ypk_wtl_r,
                     u_dut.ypk_cnt_r, u_dut.yfifo_cnt);
        if (rstn && m_axis_y_tvalid && m_axis_y_tready && m_axis_y_tlast)
            $display("EES_TL pop_tlast t=%0t scbt=%0d", $time, sc_bytes_tile);
    end

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
                $display("EES_B3_ERR [%0t] write 0x%03x SLVERR", $time, a);
            end
            awvalid = 1'b0; wvalid = 1'b0;
            @(negedge clk);
            wop_cnt = wop_cnt + 1;
            if (wop_cnt % 128 == 0)
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
                $display("EES_B3_ERR [%0t] read 0x%03x SLVERR", $time, a);
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
    localparam [31:0] A_BRGSTAT= 32'h54, A_STALLCNT = 32'h58;

    // ---- task/主流程共用暂存（声明先于所有使用点，xsim VRFC 10-3380）----
    reg [31:0] rd;
    integer guard2;
    reg [31:0] st2;
    reg [31:0] scnt;

    // ---- 数据准备（随机流纪律承袭）----
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

    // ---- 槽路径装一块（run21 bank_load_axi 逐字）----
    task bank_load_axi(input integer len, input integer k0, input integer grp);
        reg [31:0] dummy;
        begin
            axi_write(A_LDGRP, {30'd0, grp[0], grp[0]});
            for (kk = 0; kk < len; kk = kk + 1) begin
                beat64 = 64'd0;
                for (ii = 0; ii < P_TO; ii = ii + 1)
                    beat64[8*ii +: 8] = Wm[ii][k0+kk];
                axi_write(A_WDATA,  beat64[31:0]);
                axi_write(A_WDATA2, beat64[63:32]);
                axi_write(A_WCTL, {20'd0, 1'b0, (kk == 0), 8'hFF, 1'b0, 1'b0});
                beat64 = 64'd0;
                for (ii = 0; ii < 8; ii = ii + 1)
                    beat64[8*ii +: 8] = Xm[ii][k0+kk];
                axi_write(A_WDATA,  beat64[31:0]);
                axi_write(A_WDATA2, beat64[63:32]);
                axi_write(A_WCTL, {20'd0, 1'b0, 1'b0, 8'hFF, 1'b0, 1'b1});
                beat64 = 64'd0;
                for (ii = 0; ii < 8; ii = ii + 1)
                    beat64[8*ii +: 8] = Xm[ii+8][k0+kk];
                axi_write(A_WDATA,  beat64[31:0]);
                axi_write(A_WDATA2, beat64[63:32]);
                axi_write(A_WCTL, {20'd0, (kk == len-1), 1'b0, 8'hFF, 1'b1, 1'b1});
            end
            guard2 = 0; rd = 32'd0;
            while (!rd[3] && guard2 < 100) begin
                axi_read(A_STATUS, rd);
                guard2 = guard2 + 1;
            end
            if (!rd[3]) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] ld_done sticky missing len=%0d",
                         $time, len);
            end
            axi_read(A_LDLEN, dummy);
            if (dummy[12:0] != len[12:0]) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] ld_w_len=%0d exp=%0d",
                         $time, dummy[12:0], len);
            end
            if (dummy[25:13] != len[12:0]) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] ld_x_len=%0d exp=%0d",
                         $time, dummy[25:13], len);
            end
        end
    endtask

    // ---- 流路径：按合同 §3.2 节律打包 dma_beats ----
    task pack_dma(input integer len, input integer k0);
        begin
            for (kk = 0; kk < len; kk = kk + 1) begin
                beat64 = 64'd0;
                for (ii = 0; ii < P_TO; ii = ii + 1)
                    beat64[8*ii +: 8] = Wm[ii][k0+kk];
                dma_beats[3*kk] = beat64;
                beat64 = 64'd0;
                for (ii = 0; ii < 8; ii = ii + 1)
                    beat64[8*ii +: 8] = Xm[ii][k0+kk];
                dma_beats[3*kk+1] = beat64;
                beat64 = 64'd0;
                for (ii = 0; ii < 8; ii = ii + 1)
                    beat64[8*ii +: 8] = Xm[ii+8][k0+kk];
                dma_beats[3*kk+2] = beat64;
            end
        end
    endtask

    // ---- MM2S BFM：发一块（negedge 驱动、posedge 收账；gaps=1 随机空拍）----
    task dma_send(input integer len, input integer gaps);
        integer bi;
        begin
            bi = 0;
            while (bi < 3*len) begin
                @(negedge clk);
                if (gaps != 0 && bi != 0 && ({$random(rs3)} % 8 == 0)) begin
                    s_axis_ld_tvalid = 1'b0;    //空拍注入（反压另计）
                end else begin
                    s_axis_ld_tvalid = 1'b1;
                    s_axis_ld_tdata  = dma_beats[bi];
                    s_axis_ld_tlast  = (bi == 3*len - 1);
                end
                @(posedge clk);
                if (s_axis_ld_tvalid && s_axis_ld_tready) bi = bi + 1;
            end
            @(negedge clk);
            s_axis_ld_tvalid = 1'b0; s_axis_ld_tlast = 1'b0;
        end
    endtask

    // ---- MM2S BFM 变体：tlast 错位（发 tbeat+1 拍，tlast 落第 tbeat 拍）----
    task dma_send_tbad(input integer len, input integer tbeat);
        integer bi;
        begin
            bi = 0;
            while (bi <= tbeat) begin
                @(negedge clk);
                s_axis_ld_tvalid = 1'b1;
                s_axis_ld_tdata  = dma_beats[bi];
                s_axis_ld_tlast  = (bi == tbeat);      //故意错位
                @(posedge clk);
                if (s_axis_ld_tvalid && s_axis_ld_tready) bi = bi + 1;
            end
            @(negedge clk);
            s_axis_ld_tvalid = 1'b0; s_axis_ld_tlast = 1'b0;
        end
    endtask

    // ---- MM2S BFM 变体：缺失 tlast（发 3*len 拍，永无 tlast；合同
    //      §8.2/§12.2——流自身无法产生新握手事件，短流由 BFM watchdog
    //      判、超长流由 R3 accepted-beat 计数判）----
    task dma_send_ntlast(input integer len);
        integer bi;
        begin
            bi = 0;
            while (bi < 3*len) begin
                @(negedge clk);
                s_axis_ld_tvalid = 1'b1;
                s_axis_ld_tdata  = dma_beats[bi];
                s_axis_ld_tlast  = 1'b0;               //故意缺失
                @(posedge clk);
                if (s_axis_ld_tvalid && s_axis_ld_tready) bi = bi + 1;
            end
            @(negedge clk);
            s_axis_ld_tvalid = 1'b0;
        end
    endtask

    // ---- 流路径装一块：LDGRP + 打包 + 发送 + ld_done/LDLEN 对账 ----
    task dma_load_block(input integer len, input integer k0,
                        input integer grp, input integer gaps);
        reg [31:0] dummy;
        begin
            axi_write(A_LDGRP, {30'd0, grp[0], grp[0]});
            pack_dma(len, k0);
            dma_send(len, gaps);
            guard2 = 0; rd = 32'd0;
            while (!rd[3] && guard2 < 100) begin
                axi_read(A_STATUS, rd);
                guard2 = guard2 + 1;
            end
            if (!rd[3]) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] stream ld_done missing len=%0d",
                         $time, len);
            end
            axi_read(A_LDLEN, dummy);
            if (dummy[12:0] != len[12:0]) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] stream ld_w_len=%0d exp=%0d",
                         $time, dummy[12:0], len);
            end
            if (dummy[25:13] != len[12:0]) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] stream ld_x_len=%0d exp=%0d",
                         $time, dummy[25:13], len);
            end
        end
    endtask

    // ---- 计算期望（活流队列 + 终值队列 + 回读矩阵三写）----
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
                            eq_f[eq_wp] = act_exp
                                        ? $signed(lut_exp[sat_addr(q7)]) : q7;
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

    // ---- start 递交 + 等 tile_done（run21 逐字）----
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
                $display("EES_B3_ERR [%0t] tile_done poll timeout STATUS=%08x guard=%0d tile#%0d",
                         $time, st, guard, tiles_started);
            end
            if (st[6] || st[7] || st[8] || st[9]) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] err bits in STATUS %08x",
                         $time, st);
            end
            gapn(8);      //尾流水/粘滞收口
            tiles_done = tiles_done + 1;
        end
    endtask

    // ---- 回读对拍（按坐标，run21 逐字）----
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
                                $display("EES_B3_ERR [%0t] RB r=%0d n=%0d got=%0d want=%0d",
                                         $time, r, n, got, exp8);
                            end else begin
                                rb_checks = rb_checks + 1;
                            end
                        end
                    end
                end
            end
            axi_read(A_YSTAT, d);
            y_exp_cnt = 0;
            for (r = 0; r < P_TO; r = r + 1)
                if (rvm[r])
                    for (n = 0; n < P_TN; n = n + 1)
                        if (nmm[n]) y_exp_cnt = y_exp_cnt + 1;
            y_exp_cnt = y_exp_cnt * ycnt_scale;
            if (d[15:0] != y_exp_cnt[15:0]) begin
                errors = errors + 1;
                $display("EES_B3_ERR [%0t] y_count=%0d exp=%0d",
                         $time, d[15:0], y_exp_cnt);
            end
        end
    endtask

    // ---- 主流程 ----

    initial begin
        // 看门狗
        cyc = 0; checks = 0; errors = 0; rb_checks = 0; sc_checks = 0;
        tiles_started = 0; tiles_done = 0; y_cnt = 0;
        eq_wp = 0; eq_rp = 0;
        sc_en = 0; sc_rp = 0; sc_bytes_tile = 0; sc_words = 0;
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
            $display("EES_B3_ERR ID=0x%08x exp 0x20260919", rd);
        end

        // ================= S1 槽路径回归（B1 语义零漂移 + y 流双检）====
        $display("EES_B3_STAGE S1 slot-path regression K=64 act=1");
        act_exp = 1'b1;
        sc_en = 1'b1;                       //流检查从此路开（sink 常放行）
        lut_load_a;
        fill_wx(64);
        load_params;
        push_expected(64, 8'hFF, 16'hFFFF);
        axi_write(A_ROWVAL, 32'hFF);
        axi_write(A_NMASK,  32'hFFFF);
        bank_load_axi(64, 0, 0);
        run_job_wait(64, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        readback_check(8'hFF, 16'hFFFF, 1);
        axi_read(A_BRGSTAT, rd);
        if (rd[4:2] !== 3'b000) begin
            errors = errors + 1;
            $display("EES_B3_ERR S1 bridge errors BRGSTAT=%03x", rd);
        end
        $display("EES_B3_STAGE S1 done checks=%0d rb=%0d sc=%0d errs=%0d",
                 checks, rb_checks, sc_checks, errors);

        // ================= S2 流路径单块（DMA BFM 全链）====
        $display("EES_B3_STAGE S2 stream single block K=64");
        act_exp = 1'b1;
        fill_wx(64);
        load_params;
        push_expected(64, 8'hFF, 16'hFFFF);
        dma_load_block(64, 0, 0, 0);
        run_job_wait(64, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        readback_check(8'hFF, 16'hFFFF, 1);
        axi_read(A_BRGSTAT, rd);
        if (rd[4:2] !== 3'b000) begin
            errors = errors + 1;
            $display("EES_B3_ERR S2 bridge errors BRGSTAT=%03x", rd);
        end
        $display("EES_B3_STAGE S2 done checks=%0d rb=%0d sc=%0d errs=%0d",
                 checks, rb_checks, sc_checks, errors);

        // ================= S3 双组重叠装载（零反压证明）====
        $display("EES_B3_STAGE S3 ping-pong overlap K=96 (48+48)");
        act_exp = 1'b1;
        fill_wx(96);
        load_params;
        push_expected(96, 8'hFF, 16'hFFFF);
        // 块0 grp0（流）→ job0 开跑
        axi_write(A_LDGRP, 32'd0);
        pack_dma(48, 0);
        dma_send(48, 0);
        axi_write(A_GEOM,   32'd48);
        axi_write(A_JOBCFG, 32'd3);          //act|first, grp0
        axi_write(A_CTRL,   32'd1);
        guard2 = 0; st2 = 32'hFFFFFFFF;
        while (st2[1] && guard2 < 1000) begin
            axi_read(A_STATUS, st2); guard2 = guard2 + 1;
        end
        if (st2[1]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S3 job0 pend never cleared");
        end
        // STALLCNT 清零起算（读清）
        axi_read(A_STALLCNT, scnt);
        axi_read(A_STALLCNT, scnt);          //再读应为 0（已清）
        if (scnt !== 32'd0) begin
            errors = errors + 1;
            $display("EES_B3_ERR S3 STALLCNT read-clear failed=%0d", scnt);
        end
        // 块1 grp1 流装载落在计算窗内（组安全 → 零反压）
        dma_load_block(48, 48, 1, 1);
        // 递交末块 job 并等收口
        run_job_wait(48, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        readback_check(8'hFF, 16'hFFFF, 1);
        // 双组重叠必须零反压（组安全让装载与计算同刻共存）
        axi_read(A_STALLCNT, scnt);
        if (scnt != 32'd0) begin
            errors = errors + 1;
            $display("EES_B3_ERR S3 dual-group load stalled %0d cycles", scnt);
        end
        $display("EES_B3_STAGE S3 done checks=%0d rb=%0d sc=%0d errs=%0d",
                 checks, rb_checks, sc_checks, errors);

        // ================= S4 同组重载 + 反压 + 空拍 ====
        $display("EES_B3_STAGE S4 same-group reload backpressure K=64");
        act_exp = 1'b1;
        fill_wx(64);
        load_params;
        push_expected(64, 8'hFF, 16'hFFFF);
        dma_load_block(64, 0, 0, 0);
        axi_write(A_GEOM,   32'd64);
        axi_write(A_JOBCFG, 32'd7);          //act|first|last, grp0
        axi_write(A_CTRL,   32'd1);
        guard2 = 0; st2 = 32'hFFFFFFFF;
        while (st2[1] && guard2 < 1000) begin
            axi_read(A_STATUS, st2); guard2 = guard2 + 1;
        end
        // tile1 计算中：换新数据（Wm/Xm 即将被 tile2 重用——tile1 的
        // 期望已推、bank 内容已装载，改 TB 镜像安全）→ 流重载 grp0
        fill_wx(48);
        push_expected(48, 8'hFF, 16'hFFFF);
        dma_load_block(48, 0, 0, 1);         //gaps=1；读组不安全→反压
        run_job_wait(48, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        readback_check(8'hFF, 16'hFFFF, 1);
        axi_read(A_STALLCNT, scnt);
        if (scnt == 32'd0) begin
            errors = errors + 1;
            $display("EES_B3_ERR S4 expected backpressure, STALLCNT=0");
        end else begin
            $display("EES_B3_INFO S4 STALLCNT=%0d (backpressure proven)", scnt);
        end
        axi_read(A_STALLCNT, scnt);
        if (scnt !== 32'd0) begin
            errors = errors + 1;
            $display("EES_B3_ERR S4 STALLCNT read-clear failed=%0d", scnt);
        end
        $display("EES_B3_STAGE S4 done checks=%0d rb=%0d sc=%0d errs=%0d",
                 checks, rb_checks, sc_checks, errors);

        // ================= S5 双源冲突（D4）====
        $display("EES_B3_STAGE S5 dual-source conflicts");
        act_exp = 1'b1;
        // (a) 流窗内 WCTL → 丢弃
        fill_wx(48);
        load_params;
        push_expected(48, 8'hFF, 16'hFFFF);
        axi_write(A_LDGRP, 32'd0);
        pack_dma(48, 0);
        fork
            begin : f_bfm
                dma_send(48, 1);             //gaps=1 拉宽传输窗
            end
            begin : f_wctl
                guard2 = 0; rd = 32'd0;
                while (!rd[0] && guard2 < 200) begin
                    axi_read(A_BRGSTAT, rd); guard2 = guard2 + 1;
                end
                if (!rd[0]) begin
                    errors = errors + 1;
                    $display("EES_B3_ERR S5a stream window never opened");
                end
                axi_write(A_WDATA,  32'hDEAD_BEEF);
                axi_write(A_WDATA2, 32'hCAFE_F00D);
                axi_write(A_WCTL,   32'h0000_03FC);
            end
        join
        guard2 = 0; rd = 32'd0;
        while (!rd[3] && guard2 < 100) begin
            axi_read(A_STATUS, rd); guard2 = guard2 + 1;
        end
        axi_read(A_STATUS, rd);
        if (rd[2]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S5a dropped WCTL left wr_pend=%0d", rd[2]);
        end
        if (!rd[8]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S5a ld_pend_err not flagged");
        end
        axi_read(A_BRGSTAT, rd);
        if (!rd[3] || rd[2] || rd[4]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S5a BRGSTAT=%03x (exp src_conflict only)", rd);
        end
        // 数据不受扰：LDLEN + job 全链
        axi_read(A_LDLEN, rd);
        if (rd[12:0] != 13'd48 || rd[25:13] != 13'd48) begin
            errors = errors + 1;
            $display("EES_B3_ERR S5a block corrupted LDLEN=%03x", rd);
        end
        // 场景注入的 ld_pend_err/src_conflict 已取证 → err_clr 后再跑
        // （run_job_wait 对 STATUS 错误位是全场景绊线，保持严格）
        axi_write(A_CTRL, 32'h4);            //err_clr
        run_job_wait(48, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        readback_check(8'hFF, 16'hFFFF, 1);
        // (b) 槽悬挂 + 流等待：先清冲突位
        axi_write(A_CTRL, 32'h4);            //err_clr
        axi_read(A_BRGSTAT, rd);
        if (rd[3]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S5b err_clr failed BRGSTAT=%03x", rd);
        end
        fill_wx(64);
        load_params;
        push_expected(64, 8'hFF, 16'hFFFF);
        bank_load_axi(64, 0, 0);             //tile1 槽路径装载 grp0
        axi_write(A_GEOM,   32'd64);
        axi_write(A_JOBCFG, 32'd7);
        axi_write(A_CTRL,   32'd1);
        guard2 = 0; st2 = 32'hFFFFFFFF;
        while (st2[1] && guard2 < 1000) begin
            axi_read(A_STATUS, st2); guard2 = guard2 + 1;
        end
        // 垃圾 WCTL 打读组 → 悬挂（w_wa=64 越过 tile1 的 64——无害）
        axi_write(A_WDATA,  32'hBAADF00D);
        axi_write(A_WDATA2, 32'h0BADCAFE);
        axi_write(A_WCTL,   32'h0000_03FC);
        axi_read(A_STATUS, rd);
        if (!rd[2]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S5b garbage WCTL not held (STATUS=%03x)", rd);
        end
        // 流装载 tile2 块（grp0 同组；先等槽排空——计算结束后垃圾拍
        // 落 w_wa=64，随后流块 first 复址 0..47 不受扰）
        fill_wx(48);
        push_expected(48, 8'hFF, 16'hFFFF);
        dma_load_block(48, 0, 0, 1);
        axi_read(A_BRGSTAT, rd);
        if (!rd[3]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S5b src_conflict not flagged BRGSTAT=%03x", rd);
        end
        // R2 正控制：槽悬挂+流等待也置 ld_pend_err（合同 §8.2 两条件均
        // 落双位）；取证后 err_clr（run_job_wait 的 STATUS 绊线保持严格）
        axi_read(A_STATUS, rd);
        if (!rd[8]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S5b ld_pend_err not flagged (R2) STATUS=%03x",
                     rd);
        end
        axi_write(A_CTRL, 32'h4);            //err_clr
        run_job_wait(48, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        readback_check(8'hFF, 16'hFFFF, 1);
        $display("EES_B3_STAGE S5 done checks=%0d rb=%0d sc=%0d errs=%0d",
                 checks, rb_checks, sc_checks, errors);

        // ================= S6 tlast 错位 + 恢复 ====
        $display("EES_B3_STAGE S6 tlast misplacement + recovery");
        pack_dma(16, 0);
        dma_send_tbad(16, 6);                //tlast 落第 6 拍（W 相）
        guard2 = 0; rd = 32'd0;
        while (!rd[2] && guard2 < 100) begin
            axi_read(A_BRGSTAT, rd); guard2 = guard2 + 1;
        end
        if (!rd[2]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S6 tlast_err not flagged BRGSTAT=%03x", rd);
        end
        // soft_rst 恢复
        axi_write(A_CTRL, 32'h2);
        gapn(8);
        axi_read(A_BRGSTAT, rd);
        if (rd !== 32'd0) begin
            errors = errors + 1;
            $display("EES_B3_ERR S6 soft_rst left BRGSTAT=%03x", rd);
        end
        // 恢复证明：好块全链
        act_exp = 1'b1;
        fill_wx(48);
        load_params;
        push_expected(48, 8'hFF, 16'hFFFF);
        dma_load_block(48, 0, 1, 0);
        run_job_wait(48, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        readback_check(8'hFF, 16'hFFFF, 1);
        // ---- S6b tlast 延后一拍（beat 48=k16 W 相，§12.2 变体）----
        pack_dma(16, 0);
        dma_send_tbad(16, 48);               //tlast 落第 48 拍（Xhi 后一拍）
        guard2 = 0; rd = 32'd0;
        while (!rd[2] && guard2 < 100) begin
            axi_read(A_BRGSTAT, rd); guard2 = guard2 + 1;
        end
        if (!rd[2]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S6b tlast_err not flagged BRGSTAT=%03x", rd);
        end
        axi_write(A_CTRL, 32'h2);            //soft_rst 恢复
        gapn(8);
        axi_read(A_BRGSTAT, rd);
        if (rd !== 32'd0) begin
            errors = errors + 1;
            $display("EES_B3_ERR S6b soft_rst left BRGSTAT=%03x", rd);
        end
        // ---- S6c 缺失 tlast（短流 48 拍）：流自身无法产生新握手事件
        //      → 硬件不可检（合同 §8.2）；负向轮询证 ld_done_st 恒 0
        //      且无假 flag，判据归 BFM watchdog/DMA BTT ----
        pack_dma(16, 0);
        dma_send_ntlast(16);
        repeat (32) begin                    //足够长窗：任何收口都该发生
            axi_read(A_BRGSTAT, rd); gapn(4);
        end
        if (rd[1] || rd[2]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S6c missing tlast wrongly closed/flagged BRGSTAT=%03x",
                     rd);
        end
        $display("EES_B3_INFO S6c missing tlast judged by watchdog BRGSTAT=%03x",
                 rd);
        axi_write(A_CTRL, 32'h2);            //soft_rst 恢复（流悬挂解除）
        gapn(8);
        // ---- S6d 超长无 tlast（3072 拍=K 上限×3）：R3 accepted-beat
        //      块长检查（修订项 4——不能只查 TLAST phase）----
        fill_wx(1024);
        pack_dma(1024, 0);
        dma_send_ntlast(1024);               //3*1024 拍全无 tlast
        guard2 = 0; rd = 32'd0;
        while (!rd[2] && guard2 < 200) begin
            axi_read(A_BRGSTAT, rd); guard2 = guard2 + 1;
        end
        if (!rd[2]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S6d overlength tlast_err not flagged BRGSTAT=%03x",
                     rd);
        end
        if (rd[1]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S6d overlength block wrongly closed BRGSTAT=%03x",
                     rd);
        end
        axi_write(A_CTRL, 32'h2);            //soft_rst 恢复
        gapn(8);
        axi_read(A_BRGSTAT, rd);
        if (rd !== 32'd0) begin
            errors = errors + 1;
            $display("EES_B3_ERR S6d soft_rst left BRGSTAT=%03x", rd);
        end
        $display("EES_B3_STAGE S6 done checks=%0d rb=%0d sc=%0d errs=%0d",
                 checks, rb_checks, sc_checks, errors);

        // ================= S7 y FIFO 溢出 + 恢复 ====
        $display("EES_B3_STAGE S7 y FIFO overflow + recovery");
        act_exp = 1'b1;
        sc_en = 1'b0;                        //溢出段流丢字不计账
        m_axis_y_tready = 1'b0;              //sink 停
        fill_wx(64);
        load_params;
        push_expected(64, 8'hFF, 16'hFFFF);  //tile1 期望
        push_expected(64, 8'hFF, 16'hFFFF);  //tile2（同数据重跑）
        push_expected(64, 8'hFF, 16'hFFFF);  //tile3（FIFO 32 词满 → 溢出）
        dma_load_block(64, 0, 0, 0);
        run_job_wait(64, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        $display("EES_DBG S7 t1 done eq_wp=%0d eq_rp=%0d y=%0d",
                 eq_wp, eq_rp, y_cnt);
        run_job_wait(64, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        $display("EES_DBG S7 t2 done eq_wp=%0d eq_rp=%0d y=%0d",
                 eq_wp, eq_rp, y_cnt);
        run_job_wait(64, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        $display("EES_DBG S7 t3 done eq_wp=%0d eq_rp=%0d y=%0d",
                 eq_wp, eq_rp, y_cnt);
        readback_check(8'hFF, 16'hFFFF, 1);
        axi_read(A_BRGSTAT, rd);
        if (!rd[4]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S7 y_ovf not flagged BRGSTAT=%03x", rd);
        end
        // ---- §11 正典恢复链（修订版合同强制：FIFO 非空禁 soft_rst；
        //      soft_rst 清 bank w_loaded/x_loaded → 重装载 + LDSTAT 确认
        //      后才允许 start——此前 S7 死锁的根因即跳过本步）----
        // (1) 排空 y FIFO：sink 放行，等 tvalid 观测为 0（溢出段陈旧
        //     词全部流出；sc_en=0 期间不记账）
        m_axis_y_tready = 1'b1;
        guard2 = 0;
        @(negedge clk);
        while (m_axis_y_tvalid && guard2 < 2000) begin
            @(negedge clk); guard2 = guard2 + 1;
        end
        if (m_axis_y_tvalid) begin
            errors = errors + 1;
            $display("EES_B3_ERR S7 FIFO never drained (tvalid stuck)");
        end
        gapn(16);                            //排空稳定窗（计算已停）
        // (2) 流检查器同步：跳过溢出段（已丢字，无法逐字节对账）
        sc_rp = eq_wp; sc_bytes_tile = 0;
        // (3) err_clr：清 sticky（§11 顺序 err_clr 先于 soft_rst）
        axi_write(A_CTRL, 32'h4);
        axi_read(A_BRGSTAT, rd);
        if (rd[4]) begin
            errors = errors + 1;
            $display("EES_B3_ERR S7 err_clr left y_ovf BRGSTAT=%03x", rd);
        end
        // (4) soft_rst（FIFO 已空，合规）：清运行态/FIFO/错误/loaded
        axi_write(A_CTRL, 32'h2);
        gapn(8);
        // (5) 正控制：soft_rst 清 bank w_loaded/x_loaded（V1.0 语义，
        //     合同 §11 强制项）——未重装载前禁止 start
        axi_read(A_LDSTAT, rd);
        if (rd[5:4] !== 2'b00 || rd[7:6] !== 2'b00) begin
            errors = errors + 1;
            $display("EES_B3_ERR S7 loaded meta survived soft_rst LDSTAT=%03x",
                     rd);
        end
        // (6) 重装载（配置/LUT/参数 soft_rst 保留无需重写）+ LDSTAT 确认
        push_expected(64, 8'hFF, 16'hFFFF);  //tile4
        dma_load_block(64, 0, 0, 0);
        axi_read(A_LDSTAT, rd);
        if (rd[5:4] !== 2'b01 || rd[7:6] !== 2'b01) begin
            errors = errors + 1;
            $display("EES_B3_ERR S7 reload LDSTAT loaded!=01 LDSTAT=%03x", rd);
        end
        // (7) 重跑 tile4 全链对拍
        sc_en = 1'b1;
        run_job_wait(64, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        readback_check(8'hFF, 16'hFFFF, 1);
        gapn(64);                            //等 FIFO 排空
        $display("EES_B3_STAGE S7 done checks=%0d rb=%0d sc=%0d errs=%0d",
                 checks, rb_checks, sc_checks, errors);

        // ---- 守恒对账 ----
        if (eq_rp != eq_wp) begin
            errors = errors + 1;
            $display("EES_B3_ERR unsent expectations %0d", eq_wp - eq_rp);
        end
        if (sc_rp != eq_wp) begin
            errors = errors + 1;
            $display("EES_B3_ERR stream checker lag %0d", eq_wp - sc_rp);
        end
        if (sc_bytes_tile != 0) begin
            errors = errors + 1;
            $display("EES_B3_ERR stream ends mid-tile %0dB", sc_bytes_tile);
        end
        if (tiles_started != tiles_done) begin
            errors = errors + 1;
            $display("EES_B3_ERR tiles started=%0d done=%0d",
                     tiles_started, tiles_done);
        end

        $display("EES_B3_INFO tiles=%0d/%0d y=%0d sc_words=%0d",
                 tiles_started, tiles_done, y_cnt, sc_words);
        if (errors == 0)
            $display("EES_SUMMARY checks=%0d rb_checks=%0d sc_checks=%0d errors=0 PASS",
                     checks, rb_checks, sc_checks);
        else
            $display("EES_SUMMARY checks=%0d rb_checks=%0d sc_checks=%0d errors=%0d FAIL",
                     checks, rb_checks, sc_checks, errors);
        $display("EES_VIVADO_RESULT %s", (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

    // 看门狗
    initial begin
        #40_000_000;
        $display("EES_B3_ERR watchdog timeout");
        $display("EES_SUMMARY checks=%0d rb_checks=%0d sc_checks=%0d errors=999 FAIL",
                 checks, rb_checks, sc_checks);
        $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

endmodule
