/************************************************************************
 * File Name     : tb_yolo_ppu_add.sv
 * Developer     : LSL
 * Date          : 2026-09-19
 * Project Name  : AMD embodied sorting / EES-331 XC7Z020
 * Module Name   : tb_yolo_ppu_add
 * Description   : P2d add 引擎核独立门仿真（PPU 手册 §7 P2d）。
 *
 *   DUT: rtl_ppu/yolo_ppu_add.sv（双路 requant【不逐路饱和】→ int64
 *   求和一次 → int32 合同截断 → sat_i8 一次；双流会合接收，ready 不
 *   组合依赖对侧 valid；任务级 profile；D+3 含气泡；drain 计数收尾）。
 *
 *   期望值三源独立（期望永不取自被测结构）：
 *   - golden_add.hex（ppu_add_vecgen.py：ppu_oracle.add_q，P1 已对
 *     软件 golden 闭环）：真实 6 add 任务 profile 对×极值叉乘、
 *     全 x 对消/倍增扫描、构造平局 84+93（s=1..37，q 奇偶/正负）、
 *     构造 int32 截断命中 1742、死通道 15、恒等路 1600+、s=0 直通
 *     （含 M=1 裸 passthrough）、s=39..62 轨、s 全 63 档、随机全域；
 *   - TB 模型：截断除+floor 修正+平局到偶（与 DUT 移位+掩码不同构）
 *     +int32 截断+sat，装载期与金文件逐条交叉；
 *   - 运行期 DUT≡金文件逐拍比对。
 *
 *   延迟记分板（P2a 教训①：vsim/xsim 事件序无关）：posedge 三级
 *   valid 镜像 mv1/mv2/mv3，数据检查全部键在镜像上。
 *
 *   用例：T1 全任务双流独立随机间隔（会合/气泡）+ T2 rst 在飞击杀
 *   重启全量复检 + X 绷线 + out_last 恰末拍 + 收尾静默/busy 归零/
 *   双流守恒 + 40ms 看门狗。
 *
 *   首跑教训（run01a，TB/金文件格式）：金文件原为单任务头混装全部
 *   向量，而引擎 profile 是任务级的——不同 quad 的向量全按 quad0
 *   计算致 CROSS 假错。修正=按 profile 分组多任务布局（每任务独立
 *   "N Ma sa Mb sb" 头）。另：TB 喂数计数原在"发出"时递进而非"会合
 *   传输"，未收字节会丢——改 hold-until-transfer 协议。
 * Revision History:
 *   - V1.1 (2026-09-19) by LSL : 多任务金文件 + hold-until-transfer。
 *   - V1.0 (2026-09-19) by LSL : Initial release (P2d).
 ************************************************************************/

`timescale 1ns/1ps

module tb_yolo_ppu_add;

    // ---- DUT ----
    reg         clk, rst;
    reg         start;
    reg  [31:0] n_in;
    reg  [31:0] ma_in;
    reg  [5:0]  sa_in;
    reg  [31:0] mb_in;
    reg  [5:0]  sb_in;
    wire        a_ready, b_ready;
    reg         a_valid, b_valid;
    reg  [7:0]  a_data, b_data;
    wire        y_valid;
    wire [7:0]  y;
    wire        y_last;
    wire        busy;

    yolo_ppu_add dut (
        .clk_i(clk), .rst_i(rst),
        .start_i(start), .n_i(n_in),
        .ma_i(ma_in), .sa_i(sa_in), .mb_i(mb_in), .sb_i(sb_in),
        .a_ready_o(a_ready), .a_valid_i(a_valid), .a_data_i(a_data),
        .b_ready_o(b_ready), .b_valid_i(b_valid), .b_data_i(b_data),
        .y_valid_o(y_valid), .y_o(y), .y_last_o(y_last), .busy_o(busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;              //100 MHz

    // ---- 记账 ----
    integer checks, errors, lat_err;
    integer rs1, rs2, rs3;

    // ---- 任务库（金文件多任务：每任务独立 profile）----
    localparam integer MAXT = 512;
    localparam integer MAXN = 16384;
    integer ntask;
    integer cs_n   [0:MAXT-1];
    integer cs_ma  [0:MAXT-1];
    integer cs_sa  [0:MAXT-1];
    integer cs_mb  [0:MAXT-1];
    integer cs_sb  [0:MAXT-1];
    integer cs_off [0:MAXT-1];
    integer n_cur;                     //当前任务元素数（检查器用）
    reg [7:0] a_arr [0:MAXN-1];
    reg [7:0] b_arr [0:MAXN-1];
    reg [7:0] e_arr [0:MAXN-1];

    // ---- TB 独立模型：截断除+floor 修正（≠ DUT 移位+掩码）----
    function signed [63:0] rne_div(input signed [63:0] n,
                                   input [5:0] sh);
        reg signed [63:0] q, p2, rem;
        begin
            if (sh == 6'd0) begin
                rne_div = n;                     //s=0 旁路
            end else begin
                p2  = 64'sd1 <<< sh;
                q   = n / p2;                    //Verilog 截断向零
                if (n < 0 && (n % p2) != 0)
                    q = q - 1;                   //floor 修正
                rem = n - q * p2;                //∈[0,2^s)
                if ((rem <<< 1) > p2)
                    q = q + 1;                   //向近整
                else if ((rem <<< 1) == p2 && q[0] == 1'b1)
                    q = q + 1;                   //平局到偶（q 奇进位）
                rne_div = q;
            end
        end
    endfunction

    function [7:0] add_model(input [7:0] xa, input [31:0] ma, input [5:0] sa,
                             input [7:0] xb, input [31:0] mb, input [5:0] sb);
        reg signed [63:0] aa, bb, s64, c64;
        begin
            aa  = rne_div($signed({{24{xa[7]}}, xa}) * $signed(ma), sa);
            bb  = rne_div($signed({{24{xb[7]}}, xb}) * $signed(mb), sb);
            s64 = aa + bb;
            c64 = (s64 > 64'sd2147483647)  ? 64'sd2147483647 :
                  (s64 < -64'sd2147483648) ? -64'sd2147483648 : s64;
            add_model = (c64 > 64'sd127)  ? 8'd127 :
                        (c64 < -64'sd128) ? 8'h80 : c64[7:0];
        end
    endfunction

    // ---- 延迟记分板：posedge 三级镜像（调度序无关，P2a 教训①）----
    reg mv1, mv2, mv3, chk_en;
    integer exp_cnt;                   //当前任务期望拍计数（键在镜像上）
    integer run_ti;                    //当前运行任务号（检查器索引用）
    always @(posedge clk) begin
        if (rst) begin
            mv1 <= 1'b0; mv2 <= 1'b0; mv3 <= 1'b0;
        end else begin
            mv1 <= a_valid && b_valid && a_ready && b_ready;
            mv2 <= mv1;
            mv3 <= mv2;
        end
        //检查（镜像驱动，非 DUT 输出驱动）
        if (!rst && chk_en) begin
            if (mv3) begin
                if (y_valid !== 1'b1) begin
                    lat_err = lat_err + 1;
                    $display("EES_ADD_ERR [%0t] mirror beat%0d y_valid=%b",
                             $time, exp_cnt, y_valid);
                end else begin
                    if (^y === 1'bx) begin
                        errors = errors + 1;
                        $display("EES_ADD_ERR [%0t] beat%0d X on y",
                                 $time, exp_cnt);
                    end else if (y !== e_arr[cs_off[run_ti] + exp_cnt]) begin
                        errors = errors + 1;
                        $display("EES_ADD_ERR [%0t] beat%0d y=%02h want=%02h (a=%02h b=%02h)",
                                 $time, exp_cnt, y,
                                 e_arr[cs_off[run_ti] + exp_cnt],
                                 a_arr[cs_off[run_ti] + exp_cnt],
                                 b_arr[cs_off[run_ti] + exp_cnt]);
                    end else begin
                        checks = checks + 1;
                    end
                    if (y_last !== (exp_cnt == n_cur - 1)) begin
                        errors = errors + 1;
                        $display("EES_ADD_ERR [%0t] beat%0d last=%b want=%b",
                                 $time, exp_cnt, y_last,
                                 (exp_cnt == n_cur - 1));
                    end
                end
                exp_cnt = exp_cnt + 1;
            end else if (y_valid !== 1'b0) begin
                lat_err = lat_err + 1;
                $display("EES_ADD_ERR [%0t] y_valid without mirror beat", $time);
            end
        end
    end

    // ---- 运行一个任务（双流独立随机间隔）----
    // 协议：lane 发出新字节后 hold valid 直到会合传输
    //（a_valid && b_valid && ready）才前进——计的是传输不是发出。
    task run_task(input integer ti, input integer gapmode);
        integer acnt, bcnt, k;
        reg a_off, b_off;
        begin
            run_ti = ti;
            n_cur = cs_n[ti];
            @(negedge clk);
            start = 1'b1; n_in = cs_n[ti];
            ma_in = cs_ma[ti]; sa_in = cs_sa[ti];
            mb_in = cs_mb[ti]; sb_in = cs_sb[ti];
            @(negedge clk);
            start = 1'b0;
            acnt = 0; bcnt = 0; exp_cnt = 0;
            a_off = 0; b_off = 0;
            a_valid = 1'b0; b_valid = 1'b0;
            chk_en = 1'b1;
            @(negedge clk);                //让镜像建立一拍
            while (acnt < n_cur || bcnt < n_cur) begin
                //传输判定=posedge 镜像 mv1（末拍后 a_ready 已落 0，
                //negedge 事后采样会漏末拍——run01b 卡死根因）
                if (mv1) begin
                    acnt = acnt + 1; bcnt = bcnt + 1;
                    a_off = 1'b0; b_off = 1'b0;
                end
                if (!a_off && acnt < n_cur) begin
                    if (gapmode == 0 || ({$random(rs1)} % 4) != 0) begin
                        a_off  = 1'b1;
                        a_data = a_arr[cs_off[ti] + acnt];
                    end
                end
                if (!b_off && bcnt < n_cur) begin
                    if (gapmode == 0 || ({$random(rs2)} % 4) != 0) begin
                        b_off  = 1'b1;
                        b_data = b_arr[cs_off[ti] + bcnt];
                    end
                end
                a_valid = a_off;
                b_valid = b_off;
                @(negedge clk);
            end
            a_valid = 1'b0; b_valid = 1'b0;
            //排空 + 收尾静默
            for (k = 0; k < 12; k = k + 1)
                @(negedge clk);
            chk_en = 1'b0;
            if (exp_cnt != n_cur) begin
                errors = errors + 1;
                $display("EES_ADD_ERR task%0d produced %0d/%0d beats",
                         ti, exp_cnt, n_cur);
            end
            for (k = 0; k < 6; k = k + 1) begin
                @(negedge clk);
                if (y_valid) begin
                    errors = errors + 1;
                    $display("EES_ADD_ERR [%0t] output after done", $time);
                end
            end
            if (busy) begin
                errors = errors + 1;
                $display("EES_ADD_ERR busy after done");
            end
            //双流守恒
            if (acnt != n_cur || bcnt != n_cur) begin
                errors = errors + 1;
                $display("EES_ADD_ERR lanes consumed a=%0d b=%0d want=%0d",
                         acnt, bcnt, n_cur);
            end
        end
    endtask

    // ---- 金文件读取（多任务直至终止行 "0 0 0 0 0"）----
    integer fd, rc, i, j, tkill;
    reg [8*160:1] line;
    integer hn;
    reg [31:0] hma, hsa, hmb, hsb;
    reg [7:0] da, db, dy;
    reg [1023:0] golden_path;
    integer off;

    initial begin
        checks = 0; errors = 0; lat_err = 0;
        rs1 = 21; rs2 = 22; rs3 = 23;
        chk_en = 1'b0; exp_cnt = 0; run_ti = 0; n_cur = 0;
        ntask = 0; off = 0;
        start = 0; n_in = 0;
        ma_in = 0; sa_in = 0; mb_in = 0; sb_in = 0;
        a_valid = 0; b_valid = 0; a_data = 0; b_data = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;

        if (!$value$plusargs("GOLDEN=%s", golden_path))
            golden_path = "golden_add.hex";

        fd = $fopen(golden_path, "r");
        if (fd == 0) begin
            errors = errors + 1;
            $display("EES_ADD_ERR cannot open golden %s", golden_path);
        end else begin
            while ($fgets(line, fd) > 0) begin
                rc = $sscanf(line, "%d %d %d %d %d",
                             hn, hma, hsa, hmb, hsb);
                if (rc == 5 && hn == 0)
                    break;                          //终止行
                if (rc != 5 || hn <= 0) begin
                    errors = errors + 1;
                    $display("EES_ADD_ERR bad header rc=%0d n=%0d", rc, hn);
                    break;
                end else begin
                    cs_n[ntask]  = hn;
                    cs_ma[ntask] = hma; cs_sa[ntask] = hsa;
                    cs_mb[ntask] = hmb; cs_sb[ntask] = hsb;
                    cs_off[ntask] = off;
                    for (i = 0; i < hn; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%h %h", da, db);
                        a_arr[off + i] = da;
                        b_arr[off + i] = db;
                    end
                    for (i = 0; i < hn; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%h", dy);
                        e_arr[off + i] = dy;
                    end
                    //交叉：TB 截断除模型 ≡ python oracle 金（每任务
                    //用其自身 profile——单头混装多 profile 是 run01a 教训）
                    for (i = 0; i < hn; i = i + 1) begin
                        if (add_model(a_arr[off + i], hma, hsa,
                                      b_arr[off + i], hmb, hsb)
                            !== e_arr[off + i]) begin
                            errors = errors + 1;
                            $display("EES_ADD_ERR CROSS task%0d vec%0d model!=golden (a=%02h b=%02h y=%02h)",
                                     ntask, i, a_arr[off + i],
                                     b_arr[off + i], e_arr[off + i]);
                        end else
                            checks = checks + 1;
                    end
                    off = off + hn;
                    ntask = ntask + 1;
                end
            end
            $fclose(fd);
        end
        $display("EES_ADD_INFO loaded %0d tasks / %0d vectors (cross done)",
                 ntask, off);

        // ============ T1 全任务：常供与双流独立随机间隔轮转 ============
        for (i = 0; i < ntask; i = i + 1)
            run_task(i, (i % 2));
        $display("EES_ADD_INFO T1 all %0d tasks done", ntask);

        // ============ T2 rst 在飞击杀 + 重启全量复检 ============
        tkill = 0;                       //取首个 N>=40 的任务
        for (i = 0; i < ntask; i = i + 1)
            if (tkill == 0 && cs_n[i] >= 40)
                tkill = i;
        if (tkill == 0) tkill = ntask - 1;
        run_ti = tkill; n_cur = cs_n[tkill];
        @(negedge clk);
        start = 1'b1; n_in = cs_n[tkill];
        ma_in = cs_ma[tkill]; sa_in = cs_sa[tkill];
        mb_in = cs_mb[tkill]; sb_in = cs_sb[tkill];
        @(negedge clk);
        start = 1'b0;
        exp_cnt = 0; chk_en = 1'b1;
        j = 0;
        while (j < 40 && j < n_cur) begin
            a_valid = a_ready;           //a_ready==b_ready（会合同收）
            b_valid = b_ready;
            if (a_valid) a_data = a_arr[cs_off[tkill] + j];
            if (b_valid) b_data = b_arr[cs_off[tkill] + j];
            if (a_valid && b_valid)
                j = j + 1;
            @(negedge clk);
        end
        @(negedge clk);
        rst = 1'b1; a_valid = 1'b0; b_valid = 1'b0;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        chk_en = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            if (y_valid) begin
                errors = errors + 1;
                $display("EES_ADD_ERR [%0t] output during/after rst", $time);
            end
        end
        run_task(tkill, 1);              //重启同任务，全量复检
        $display("EES_ADD_INFO T2_RSTKILL done (task %0d)", tkill);

        // ======== 收尾 ========
        $display("EES_SUMMARY checks=%0d errors=%0d lat_err=%0d",
                 checks, errors, lat_err);
        if (errors == 0 && lat_err == 0)
            $display("EES_MODELSIM_RESULT PASS");
        else
            $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

    //看门狗
    initial begin
        #40_000_000;
        $display("EES_ADD_ERR watchdog timeout");
        $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

endmodule
