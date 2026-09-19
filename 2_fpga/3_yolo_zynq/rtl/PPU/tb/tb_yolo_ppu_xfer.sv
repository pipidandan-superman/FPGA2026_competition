/************************************************************************
 * File Name     : tb_yolo_ppu_xfer.sv
 * Developer     : LSL
 * Date          : 2026-09-19
 * Project Name  : AMD embodied sorting / EES-331 XC7Z020
 * Module Name   : tb_yolo_ppu_xfer
 * Description   : P2e xfer 引擎核独立门仿真（PPU 手册 §7 P2e）。
 *
 *   DUT: rtl_ppu/yolo_ppu_xfer.sv（段序字节流拷贝 + 逐段可选 requant；
 *   恒等对 (M=2^30,s=30) 走硬件捷径——S3 字节旁路，结构性而非退化
 *   requant；段表写口地址自增，start 清 wa_r 支持多任务轮转；D+3 含
 *   气泡；drain 计数收尾）。
 *
 *   期望值三源独立（期望永不取自被测结构）：
 *   - golden_xfer.hex（ppu_xfer_vecgen.py：ppu_oracle.requant_seg，
 *     P1 已对软件 golden 闭环）：真实 concat 任务段数/profile + 合成
 *     小长度、heads 型 6 恒等段、恒等/非恒等混排（首/中/尾）、单段、
 *     len=1 边界、构造平局段（s=1..3 奇 M——段内每字节皆平局）、
 *     s=0 饱和轨/死通道 M=0/M=1 全数据通路拷贝、s=39..62 轨、
 *     s 全 63 档、随机任务；金对【每一段】（含恒等段）都算全量
 *     requant —— DUT 恒等段走捷径，DUT≡金即钉死捷径≡全算等价；
 *   - TB 模型：截断除+floor 修正+平局到偶（与 DUT 移位+掩码不同构）
 *     +sat_i8，同样【无捷径】对每字节按其段 profile 计算，装载期与
 *     金文件逐条交叉；
 *   - 运行期 DUT≡金逐拍比对。
 *
 *   延迟记分板（P2a 教训①：vsim/xsim 事件序无关）：posedge 三级
 *   镜像 mv1/mv2/mv3，数据检查全部键在镜像上；喂数 hold-until-
 *   transfer 以 mv1 为准（P2d 教训③：末拍后 in_ready 已落 0，negedge
 *   事后采样漏末拍）。
 *
 *   用例：T1 全任务随机间隔（气泡）+ T2 rst 在飞击杀重启全量复检 +
 *   X 绷线 + y_last 恰末拍 + 收尾静默/busy 归零/守恒 + 40ms 看门狗。
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : Initial release (P2e).
 ************************************************************************/

`timescale 1ns/1ps

module tb_yolo_ppu_xfer;

    // ---- DUT ----
    reg         clk, rst;
    reg         seg_we;
    reg  [31:0] seg_len;
    reg  [31:0] seg_m;
    reg  [5:0]  seg_s;
    reg         start;
    reg  [3:0]  nseg_in;
    wire        in_ready;
    reg         in_valid;
    reg  [7:0]  in_data;
    wire        y_valid;
    wire [7:0]  y;
    wire        y_last;
    wire        busy;

    yolo_ppu_xfer dut (
        .clk_i(clk), .rst_i(rst),
        .seg_we_i(seg_we), .seg_len_i(seg_len),
        .seg_m_i(seg_m), .seg_s_i(seg_s),
        .start_i(start), .nseg_i(nseg_in),
        .in_ready_o(in_ready), .in_valid_i(in_valid),
        .in_data_i(in_data),
        .y_valid_o(y_valid), .y_o(y), .y_last_o(y_last), .busy_o(busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;              //100 MHz

    // ---- 记账 ----
    integer checks, errors, lat_err;
    integer rs1;

    // ---- 任务库（金文件多任务：每任务独立段表）----
    localparam integer MAXT = 256;
    localparam integer MAXSEG = 8;
    localparam integer MAXN = 16384;
    integer ntask;
    integer cs_nseg  [0:MAXT-1];
    integer cs_off   [0:MAXT-1];       //输入/期望流偏移
    integer cs_soff  [0:MAXT-1];       //段表偏移（×MAXSEG）
    integer sg_len   [0:MAXT*MAXSEG-1];
    integer sg_m     [0:MAXT*MAXSEG-1];
    integer sg_s     [0:MAXT*MAXSEG-1];
    integer n_cur;                     //当前任务总字节数（检查器用）
    integer nseg_cur;
    reg [7:0] x_arr [0:MAXN-1];
    reg [7:0] e_arr [0:MAXN-1];

    // ---- TB 独立模型：截断除+floor 修正（≠ DUT 移位+掩码，且无捷径）----
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

    function [7:0] rq_model(input [7:0] xx, input [31:0] mm,
                            input [5:0] ss);
        reg signed [63:0] p, q;
        begin
            p = rne_div($signed({{24{xx[7]}}, xx}) * $signed(mm), ss);
            rq_model = (p > 64'sd127)  ? 8'd127 :
                       (p < -64'sd128) ? 8'h80 : p[7:0];
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
            mv1 <= in_valid && in_ready;
            mv2 <= mv1;
            mv3 <= mv2;
        end
        //检查（镜像驱动，非 DUT 输出驱动）
        if (!rst && chk_en) begin
            if (mv3) begin
                if (y_valid !== 1'b1) begin
                    lat_err = lat_err + 1;
                    $display("EES_XFER_ERR [%0t] mirror beat%0d y_valid=%b",
                             $time, exp_cnt, y_valid);
                end else begin
                    if (^y === 1'bx) begin
                        errors = errors + 1;
                        $display("EES_XFER_ERR [%0t] beat%0d X on y",
                                 $time, exp_cnt);
                    end else if (y !== e_arr[cs_off[run_ti] + exp_cnt]) begin
                        errors = errors + 1;
                        $display("EES_XFER_ERR [%0t] beat%0d y=%02h want=%02h (x=%02h)",
                                 $time, exp_cnt, y,
                                 e_arr[cs_off[run_ti] + exp_cnt],
                                 x_arr[cs_off[run_ti] + exp_cnt]);
                    end else begin
                        checks = checks + 1;
                    end
                    if (y_last !== (exp_cnt == n_cur - 1)) begin
                        errors = errors + 1;
                        $display("EES_XFER_ERR [%0t] beat%0d last=%b want=%b",
                                 $time, exp_cnt, y_last,
                                 (exp_cnt == n_cur - 1));
                    end
                end
                exp_cnt = exp_cnt + 1;
            end else if (y_valid !== 1'b0) begin
                lat_err = lat_err + 1;
                $display("EES_XFER_ERR [%0t] y_valid without mirror beat",
                         $time);
            end
        end
    end

    // ---- 运行一个任务（单流随机间隔）----
    // 协议：发出新字节后 hold valid 直到传输（in_valid && in_ready，
    // 以 mv1 镜像为准）才前进——计的是传输不是发出（P2d 教训②③）。
    task run_task(input integer ti, input integer gapmode);
        integer cnt, k, sk;
        reg x_off;
        begin
            run_ti  = ti;
            n_cur   = 0;
            for (k = 0; k < cs_nseg[ti]; k = k + 1)
                n_cur = n_cur + sg_len[cs_soff[ti] + k];
            nseg_cur = cs_nseg[ti];
            //段表写入（引擎 wa_r 已由上次 start/复位清 0）
            @(negedge clk);
            for (k = 0; k < nseg_cur; k = k + 1) begin
                seg_we  = 1'b1;
                seg_len = sg_len[cs_soff[ti] + k];
                seg_m   = sg_m[cs_soff[ti] + k];
                seg_s   = sg_s[cs_soff[ti] + k];
                @(negedge clk);
            end
            seg_we = 1'b0;
            start = 1'b1; nseg_in = nseg_cur[3:0];
            @(negedge clk);
            start = 1'b0;
            cnt = 0; exp_cnt = 0;
            x_off = 1'b0;
            in_valid = 1'b0;
            chk_en = 1'b1;
            @(negedge clk);                //让镜像建立一拍
            while (cnt < n_cur) begin
                //传输判定=posedge 镜像 mv1（末拍后 in_ready 已落 0）
                if (mv1) begin
                    cnt = cnt + 1;
                    x_off = 1'b0;
                end
                if (!x_off && cnt < n_cur) begin
                    if (gapmode == 0 || ({$random(rs1)} % 4) != 0) begin
                        x_off   = 1'b1;
                        in_data = x_arr[cs_off[ti] + cnt];
                    end
                end
                in_valid = x_off;
                @(negedge clk);
            end
            in_valid = 1'b0;
            //排空 + 收尾静默
            for (k = 0; k < 12; k = k + 1)
                @(negedge clk);
            chk_en = 1'b0;
            if (exp_cnt != n_cur) begin
                errors = errors + 1;
                $display("EES_XFER_ERR task%0d produced %0d/%0d beats",
                         ti, exp_cnt, n_cur);
            end
            for (k = 0; k < 6; k = k + 1) begin
                @(negedge clk);
                if (y_valid) begin
                    errors = errors + 1;
                    $display("EES_XFER_ERR [%0t] output after done", $time);
                end
            end
            if (busy) begin
                errors = errors + 1;
                $display("EES_XFER_ERR busy after done");
            end
            //守恒
            if (cnt != n_cur) begin
                errors = errors + 1;
                $display("EES_XFER_ERR consumed %0d want=%0d", cnt, n_cur);
            end
        end
    endtask

    // ---- 金文件读取（多任务直至终止行 "0"）----
    integer fd, rc, i, j, tkill;
    reg [8*160:1] line;
    integer hn;
    integer hlen, hm;
    integer hs;
    reg [7:0] dx, dy;
    reg [1023:0] golden_path;
    integer off, soff, bcnt;

    initial begin
        checks = 0; errors = 0; lat_err = 0;
        rs1 = 21;
        chk_en = 1'b0; exp_cnt = 0; run_ti = 0; n_cur = 0; nseg_cur = 0;
        ntask = 0; off = 0; soff = 0;
        seg_we = 0; seg_len = 0; seg_m = 0; seg_s = 0;
        start = 0; nseg_in = 0;
        in_valid = 0; in_data = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;

        if (!$value$plusargs("GOLDEN=%s", golden_path))
            golden_path = "golden_xfer.hex";

        fd = $fopen(golden_path, "r");
        if (fd == 0) begin
            errors = errors + 1;
            $display("EES_XFER_ERR cannot open golden %s", golden_path);
        end else begin
            while ($fgets(line, fd) > 0) begin
                rc = $sscanf(line, "%d", hn);
                if (rc == 1 && hn == 0)
                    break;                          //终止行
                if (rc != 1 || hn <= 0 || hn > MAXSEG) begin
                    errors = errors + 1;
                    $display("EES_XFER_ERR bad header rc=%0d nseg=%0d",
                             rc, hn);
                    break;
                end else begin
                    cs_nseg[ntask] = hn;
                    cs_off[ntask]  = off;
                    cs_soff[ntask] = soff;
                    for (i = 0; i < hn; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%d %d %d", hlen, hm, hs);
                        if (rc != 3 || hlen <= 0) begin
                            errors = errors + 1;
                            $display("EES_XFER_ERR bad seg line task%0d", ntask);
                        end
                        sg_len[soff + i] = hlen;
                        sg_m[soff + i]   = hm;
                        sg_s[soff + i]   = hs;
                    end
                    bcnt = 0;
                    for (i = 0; i < hn; i = i + 1)
                        bcnt = bcnt + sg_len[soff + i];
                    for (i = 0; i < bcnt; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%h", dx);
                        x_arr[off + i] = dx;
                    end
                    for (i = 0; i < bcnt; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%h", dy);
                        e_arr[off + i] = dy;
                    end
                    //交叉：TB 截断除模型【无捷径全量 requant】≡ python
                    //oracle 金（含恒等段——钉死 DUT 捷径≡全算等价）
                    j = 0;
                    for (i = 0; i < hn; i = i + 1)
                        for (bcnt = 0; bcnt < sg_len[soff + i];
                             bcnt = bcnt + 1) begin
                            if (rq_model(x_arr[off + j],
                                         sg_m[soff + i], sg_s[soff + i])
                                !== e_arr[off + j]) begin
                                errors = errors + 1;
                                $display("EES_XFER_ERR CROSS task%0d vec%0d model!=golden (x=%02h y=%02h)",
                                         ntask, j, x_arr[off + j],
                                         e_arr[off + j]);
                            end else
                                checks = checks + 1;
                            j = j + 1;
                        end
                    off  = off + bcnt * 0 + j;      //j=总字节数
                    soff = soff + hn;
                    ntask = ntask + 1;
                end
            end
            $fclose(fd);
        end
        $display("EES_XFER_INFO loaded %0d tasks / %0d bytes (cross done)",
                 ntask, off);

        // ============ T1 全任务：常供与随机间隔轮转 ============
        for (i = 0; i < ntask; i = i + 1)
            run_task(i, (i % 2));
        $display("EES_XFER_INFO T1 all %0d tasks done", ntask);

        // ============ T2 rst 在飞击杀 + 重启全量复检 ============
        tkill = 0;                       //取首个总字节>=40 的任务
        for (i = 0; i < ntask; i = i + 1) begin
            bcnt = 0;
            for (j = 0; j < cs_nseg[i]; j = j + 1)
                bcnt = bcnt + sg_len[cs_soff[i] + j];
            if (tkill == 0 && bcnt >= 40)
                tkill = i;
        end
        if (tkill == 0) tkill = ntask - 1;
        run_ti = tkill;
        n_cur = 0;
        for (j = 0; j < cs_nseg[tkill]; j = j + 1)
            n_cur = n_cur + sg_len[cs_soff[tkill] + j];
        nseg_cur = cs_nseg[tkill];
        @(negedge clk);
        for (j = 0; j < nseg_cur; j = j + 1) begin
            seg_we = 1'b1;
            seg_len = sg_len[cs_soff[tkill] + j];
            seg_m   = sg_m[cs_soff[tkill] + j];
            seg_s   = sg_s[cs_soff[tkill] + j];
            @(negedge clk);
        end
        seg_we = 1'b0;
        start = 1'b1; nseg_in = nseg_cur[3:0];
        @(negedge clk);
        start = 1'b0;
        exp_cnt = 0; chk_en = 1'b1;
        j = 0;
        while (j < 40 && j < n_cur) begin
            in_valid = in_ready;
            if (in_valid) begin
                in_data = x_arr[cs_off[tkill] + j];
                j = j + 1;
            end
            @(negedge clk);
        end
        @(negedge clk);
        rst = 1'b1; in_valid = 1'b0;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        chk_en = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            if (y_valid) begin
                errors = errors + 1;
                $display("EES_XFER_ERR [%0t] output during/after rst", $time);
            end
        end
        run_task(tkill, 1);              //重启同任务，全量复检
        $display("EES_XFER_INFO T2_RSTKILL done (task %0d)", tkill);

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
        $display("EES_XFER_ERR watchdog timeout");
        $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

endmodule
