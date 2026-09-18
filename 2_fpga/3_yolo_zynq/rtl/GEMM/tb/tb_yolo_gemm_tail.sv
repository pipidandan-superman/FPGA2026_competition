/************************************************************************
 * File Name     : tb_yolo_gemm_tail.sv
 * Developer     : LSL
 * Date          : 2026-09-18
 * Module Name   : tb_yolo_gemm_tail
 * Description   : 手册③ 共享尾独立门仿真（run05）。
 *
 *   DUT: rtl/GEMM/yolo_gemm_tail.sv（GEMM 手册 §8 全链：
 *   sum 33 位 → prod 64 位 → RNE(ties-to-even, s=0 直通) → INT8 饱和
 *   → LUT addr=sat+128 / 线性旁路；D→D+3 三级流水）。
 *
 *   期望值来源（GEMM 手册 §14：更宽独立 oracle，永不取自被测公式）：
 *   - tail_model()：TB 独立实现——截断除法 + floor 修正 + RNE，
 *     与 DUT 的"移位+掩码"法不同构；
 *   - golden_tail.hex（run01 软件 oracle 产物，10 向量）双向交叉：
 *     model ≡ golden、DUT ≡ model；
 *   - LUT 图样 A(i^A5)：DUT LUT 写口 + y 读出双跨验，钉死
 *     sat+128 有符号寻址（含 ±128 双轨边界 addr=0/255）。
 *
 *   继承 ②/级2 TB 纪律：每 negedge 驱动（gapn）、$random 无符号模、
 *   X 绊线、K=1 式记账守恒、延迟硬查（cyc−tag==3）、rst 在飞击杀。
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release.
 ************************************************************************/

`timescale 1ns/1ps

module tb_yolo_gemm_tail;

    // ---- DUT ----
    reg                clk, rst;
    reg                in_valid, in_last;
    reg signed [31:0]  acc_in, bias_in, m_in;   //R=1：打包端口即标量宽
    reg        [5:0]   sh_in;
    reg                act_en;
    wire               y_valid, y_last;
    wire signed [7:0]  y;
    reg                lut_we;
    reg        [7:0]   lut_wa, lut_wd;

    yolo_gemm_tail #(.R(1)) dut (
        .clk_i(clk), .rst_i(rst),
        .in_valid_i(in_valid), .in_last_i(in_last),
        .acc_i(acc_in), .bias_i(bias_in),
        .m_i(m_in), .sh_i(sh_in), .act_en_i(act_en),
        .y_valid_o(y_valid), .y_last_o(y_last), .y_o(y),
        .lut_we_i(lut_we), .lut_wa_i(lut_wa), .lut_wd_i(lut_wd)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;              //100 MHz

    // ---- 记账 ----
    integer checks, errors, lat_err;
    integer driven, y_cnt, flushed, last_seen;
    integer cyc;
    integer wp, rp;                    //期望队列指针
    reg signed [7:0] exp_y   [0:8191];
    reg                exp_act [0:8191];
    reg                exp_last[0:8191];
    reg        [7:0]   lut_exp [0:255];   //TB 侧 LUT 镜像（装载时同步写）
    integer rs1, rs2, rs3, rs4;
    integer dtags [0:8191];            //驱动拍时间戳（检查器侧同相位采样）
    integer dwp;

    // ---- 独立 oracle：截断除 + floor 修正 + RNE（与 DUT 移位/掩码不同构）----
    function [7:0] tail_model(input signed [63:0] a64, input signed [63:0] b64,
                              input signed [63:0] m64, input [5:0] s);
        reg signed [63:0] p, fl, rr, qn, qs;
        reg        [63:0] mod_u, hh;
        begin
            p = (a64 + b64) * m64;              //oracle sum/prod（64 位）
            if (s == 6'd0) begin
                fl = p;                          //s=0 直通，无舍入
                rr = 64'd0;
            end else begin
                mod_u = 64'd1 << s;
                hh   = mod_u >> 1;
                fl = p / $signed(mod_u);         //截断除（向零）
                if ((p < 0) && ((p % $signed(mod_u)) != 0))
                    fl = fl - 1;                 //floor 修正
                rr = p - fl * $signed(mod_u);    //∈[0, 2^s)
            end
            qn = fl + (((rr > hh) || ((rr == hh) && fl[0])) ? 64'sd1 : 64'sd0);
            qs = (qn > 64'sd127)  ? 64'sd127
               : ((qn < -64'sd128) ? -64'sd128
               : qn);
            tail_model = qs[7:0];
        end
    endfunction

    // sat+128 有符号寻址（镜像 DUT 契约的 TB 侧计算）
    function [7:0] sat_addr(input signed [7:0] q7);
        sat_addr = {~q7[7], q7[6:0]};
    endfunction

    // ---- 周期计数 + rst 采样延迟（避免与 initial 的同沿竞争）----
    always @(negedge clk) cyc = cyc + 1;
    reg rst_d;
    always @(posedge clk) rst_d <= rst;

    // ---- 检查器：每 negedge 全覆盖 ----
    reg signed [7:0] eq8, ey8;
    reg [7:0] eaddr;
    always @(negedge clk) begin
        if (rst_d) begin
            if (y_valid || y_last) begin      //rst 采样后不得有残影
                errors = errors + 1;
                $display("EES_TAIL_ERR [%0t] y_valid/last during rst", $time);
            end
        end else begin
            //驱动拍打戳：与观测同进程同相位，规避调度顺序偏差
            if (in_valid && !rst) begin
                dtags[dwp] = cyc;
                dwp = dwp + 1;
            end
            if (y_valid) begin
                if (rp >= wp) begin
                    errors = errors + 1;
                    $display("EES_TAIL_ERR [%0t] y_valid without expectation (rp=%0d wp=%0d)",
                             $time, rp, wp);
                end else begin
                    eq8   = exp_y[rp];
                    eaddr = sat_addr(eq8);
                    ey8   = exp_act[rp] ? $signed(lut_exp[eaddr]) : eq8;
                    if (^y === 1'bx) begin
                        errors = errors + 1;
                        $display("EES_TAIL_ERR [%0t] X on y_o (rp=%0d)", $time, rp);
                    end else if (y !== ey8) begin
                        errors = errors + 1;
                        $display("EES_TAIL_ERR [%0t] y=%0d want=%0d (act=%b)",
                                 $time, y, ey8, exp_act[rp]);
                    end else begin
                        checks = checks + 1;
                    end
                    if ((cyc - dtags[rp]) != 3) begin
                        lat_err = lat_err + 1;
                        $display("EES_TAIL_ERR [%0t] latency cyc-tag=%0d want 3",
                                 $time, cyc - dtags[rp]);
                    end
                    if (y_last !== exp_last[rp]) begin
                        errors = errors + 1;
                        $display("EES_TAIL_ERR [%0t] y_last=%b want %b", $time, y_last, exp_last[rp]);
                    end else if (y_last)
                        last_seen = last_seen + 1;
                    y_cnt = y_cnt + 1;
                    rp = rp + 1;
                end
            end else if (y_last) begin
                errors = errors + 1;
                $display("EES_TAIL_ERR [%0t] y_last without y_valid", $time);
            end
        end
    end

    // ---- 驱动任务 ----
    task tail_beat(input signed [31:0] a, input signed [31:0] b,
                   input signed [31:0] mm, input [5:0] s,
                   input act, input last);
        begin
            if ((^a === 1'bx) || (^b === 1'bx) || (^mm === 1'bx) || (^s === 1'bx)) begin
                errors = errors + 1;
                $display("EES_TAIL_ERR [%0t] X on driven inputs", $time);
            end
            acc_in = a; bias_in = b; m_in = mm; sh_in = s; act_en = act;
            in_valid = 1'b1; in_last = last;
            exp_y[wp]    = tail_model(a, b, mm, s);   //有符号实参自动扩展到 64 位
            exp_act[wp]  = act;
            exp_last[wp] = last;
            wp = wp + 1;
            driven = driven + 1;
            @(negedge clk);
        end
    endtask

    task gapn(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                in_valid = 1'b0; in_last = 1'b0;
                @(negedge clk);
            end
        end
    endtask

    task lut_load(input pat);        //0: A 图样 i^A5；1: B 图样 i-128
        integer i;
        reg [7:0] d;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                d = pat ? (i[7:0] - 8'd128) : (i[7:0] ^ 8'hA5);
                lut_we = 1'b1; lut_wa = i[7:0]; lut_wd = d;
                lut_exp[i] = d;
                @(negedge clk);
            end
            lut_we = 1'b0;
        end
    endtask

    // ---- 金文件读取 ----
    integer fd, rc, gvec;
    reg [8*128:1] line;
    reg [31:0] ga, gb, gm, gs;        //五列全十六进制（含 shift：1e/3e/1f）
    reg [7:0] gy;
    reg [1023:0] golden_path;

    integer i, k, t;

    initial begin
        checks = 0; errors = 0; lat_err = 0;
        driven = 0; y_cnt = 0; flushed = 0; last_seen = 0;
        cyc = 0; wp = 0; rp = 0; dwp = 0;
        rs1 = 21; rs2 = 22; rs3 = 33; rs4 = 44;
        in_valid = 0; in_last = 0; act_en = 0;
        acc_in = 0; bias_in = 0; m_in = 0; sh_in = 0;
        lut_we = 0; lut_wa = 0; lut_wd = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        gapn(2);

        if (!$value$plusargs("GOLDEN=%s", golden_path))
            golden_path = "golden_tail.hex";

        // ============ T0 GOLDEN：10 向量 双向交叉（act=0 → y_pre 域） ============
        lut_load(1'b0);                     //A 图样（T0 不用 LUT，act=0）
        gapn(2);
        fd = $fopen(golden_path, "r");
        gvec = 0;
        if (fd == 0) begin
            errors = errors + 1;
            $display("EES_TAIL_ERR cannot open golden %s", golden_path);
        end else begin
            while ($fgets(line, fd) > 0) begin
                rc = $sscanf(line, "%h %h %h %h %h", ga, gb, gm, gs, gy);
                if (rc == 5) begin
                    //交叉 1：独立模型 ≡ 软件 golden（模型自身过门）
                    if (tail_model($signed(ga), $signed(gb), $signed(gm), gs[5:0]) !== $signed(gy)) begin
                        errors = errors + 1;
                        $display("EES_TAIL_ERR T0 model!=golden vec%0d (acc=%h b=%h M=%h s=%0d y=%h)",
                                 gvec, ga, gb, gm, gs, gy);
                    end else
                        checks = checks + 1;
                    //交叉 2：DUT ≡ 模型（检查器队列路径）
                    tail_beat($signed(ga), $signed(gb), $signed(gm), gs[5:0], 1'b0, 1'b0);
                    gapn(2);
                    gvec = gvec + 1;
                end
            end
            $fclose(fd);
        end
        gapn(4);
        $display("EES_TAIL_INFO T0_GOLDEN vecs=%0d (model<->golden + DUT<->model)", gvec);

        // ============ T1 TIE_EVEN：RNE 平局双奇偶（s=1/s=2 手工钉值） ============
        for (k = 0; k < 8; k = k + 1) begin
            //sum ∈ {±1,±3,±5,±7}，M=1，s=1：|prod| 奇 → r=half 必平局
            t = (k < 4) ? (k * 2 + 1) : -(k - 3) * 2 - 1;
            tail_beat(t - 1, 1, 32'sd1, 6'd1, 1'b0, 1'b0);   //sum = t
            gapn(1);
        end
        for (k = 0; k < 4; k = k + 1) begin
            //s=2：sum ∈ {2,6,10,14} → r=2=half，q 奇偶交替
            t = 2 + k * 4;
            tail_beat(t, 0, 32'sd1, 6'd2, 1'b0, 1'b0);
            gapn(1);
        end
        //负平局：sum=−2,s=2 → floor(−0.5)=−1 奇 → 进位到 0（ties-to-even）
        tail_beat(-2, 0, 32'sd1, 6'd2, 1'b0, 1'b0);
        gapn(4);
        $display("EES_TAIL_INFO T1_TIE_EVEN done");

        // ============ T2 SAT/EXTREME + shift 扫描 ============
        //33 位 sum 正上界 × 2^30 → 饱和 127；负轨 → −128
        tail_beat(32'sh7FFFFFFF, 32'sh7FFFFFFF, 32'sh40000000, 6'd30, 1'b0, 1'b0);
        gapn(1);
        tail_beat(32'sh80000000, 32'sh80000000, 32'sh40000000, 6'd30, 1'b0, 1'b0);
        gapn(1);
        //M 负 + s=0 直通（负积直接饱和判定）
        tail_beat(1000, 0, -32'sd1, 6'd0, 1'b0, 1'b0);
        gapn(1);
        //shift 全域扫描 s=0..62（sum=1000, M=1）
        for (k = 0; k <= 62; k = k + 1)
            tail_beat(1000, 0, 32'sd1, k[5:0], 1'b0, 1'b0);
        gapn(4);
        $display("EES_TAIL_INFO T2_SAT_EXTREME_SHIFT done");

        // ============ T3 LUT_ADDR：sat+128 寻址 + 双轨边界 ============
        for (k = 0; k < 7; k = k + 1) begin
            t = -128 + k * 42;               //−128,−86,−44,−2,40,82,124
            tail_beat(t, 0, 32'sd1, 6'd0, 1'b1, 1'b0);
            gapn(1);
        end
        tail_beat(127, 0, 32'sd1, 6'd0, 1'b1, 1'b0);          //addr=255
        gapn(1);
        tail_beat(-128, 0, 32'sd1, 6'd0, 1'b1, 1'b0);         //addr=0
        gapn(1);
        tail_beat(200, 0, 32'sd1, 6'd0, 1'b1, 1'b0);          //饱和→127→addr 255
        gapn(1);
        tail_beat(-200, 0, 32'sd1, 6'd0, 1'b1, 1'b0);         //饱和→−128→addr 0
        gapn(4);
        $display("EES_TAIL_INFO T3_LUT_ADDR done");

        // ============ T4 STREAM：400 背靠背随机流 ============
        for (k = 0; k < 400; k = k + 1) begin
            if ({$random(rs1)} % 20 == 0)
                acc_in = ({$random(rs2)} % 2) ? 32'sh7FFFFFFF : 32'sh80000000;
            tail_beat(acc_in,
                      $signed({$random(rs3)} % 32'h08000000) - 32'sh04000000, //bias ±2^26 域
                      ({$random(rs4)} % 4 == 0) ? -32'sh40000000 : 32'sh40000000,
                      {$random(rs2)} % 63,
                      {$random(rs3)} % 2, (k == 399) ? 1'b1 : 1'b0);
            //背靠背：不插 gapn（除尾拍外）
            if ({$random(rs1)} % 5 == 0) gapn(1);             //20% 随机气泡
        end
        gapn(8);
        $display("EES_TAIL_INFO T4_STREAM done (last beat tagged)");

        // ============ T5 GAPS + rst 在飞击杀 ============
        for (k = 0; k < 200; k = k + 1) begin
            tail_beat($signed({$random(rs1)}),
                      $signed({$random(rs2)}) & 32'h0FFFFFFF,
                      32'sd1, {$random(rs3)} % 63,
                      {$random(rs4)} % 2, 1'b0);
            gapn({$random(rs2)} % 6);
        end
        //rst 击杀：3 拍在飞（含已入流水未呈现的）
        tail_beat(1234, 10, 32'sd1, 6'd1, 1'b0, 1'b0);
        tail_beat(-567, -20, 32'sh40000000, 6'd3, 1'b1, 1'b1);
        tail_beat(8, 0, 32'sd1, 6'd0, 1'b0, 1'b0);
        @(negedge clk);
        rst = 1'b1; in_valid = 1'b0; in_last = 1'b0;
        repeat (2) @(negedge clk);
        flushed = flushed + (wp - rp);        //在飞期望作废
        wp = 0; rp = 0; dwp = 0;
        rst = 1'b0;
        gapn(6);                              //残影观察窗
        //击杀后恢复
        tail_beat(42, 0, 32'sd1, 6'd0, 1'b0, 1'b0);
        gapn(8);
        $display("EES_TAIL_INFO T5_GAPS_RSTKILL done (flushed=%0d)", flushed);

        // ============ 收尾 ============
        gapn(4);
        if (wp != rp) begin
            errors = errors + 1;
            $display("EES_TAIL_ERR queue not drained wp=%0d rp=%0d", wp, rp);
        end
        if ((y_cnt + flushed) != driven) begin
            errors = errors + 1;
            $display("EES_TAIL_ERR conservation driven=%0d y=%0d flushed=%0d",
                     driven, y_cnt, flushed);
        end
        $display("EES_SUMMARY checks=%0d errors=%0d lat_err=%0d", checks, errors, lat_err);
        $display("EES_TAIL_INFO driven=%0d y=%0d flushed=%0d last_seen=%0d",
                 driven, y_cnt, flushed, last_seen);
        if (errors == 0 && lat_err == 0)
            $display("EES_VIVADO_RESULT PASS");
        else
            $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

    //看门狗
    initial begin
        #20_000_000;
        $display("EES_TAIL_ERR watchdog timeout");
        $display("EES_VIVADO_RESULT FAIL");
        $finish;
    end

endmodule
