/************************************************************************
 * File Name     : tb_yolo_ppu_requant.sv
 * Developer     : LSL
 * Date          : 2026-09-18
 * Project Name  : AMD embodied sorting / EES-331 XC7Z020
 * Module Name   : tb_yolo_ppu_requant
 * Description   : P2a requant 核独立门仿真（PPU 手册 §7 P2a）。
 *
 *   DUT: rtl_ppu/yolo_ppu_requant.sv（x INT8 × M[0,2^31) → INT64 积 →
 *   RNE(ties-to-even, s=0 直通) → INT8 饱和；D→D+3 三级流水，
 *   M/s 随元素入流水可逐拍换参）。
 *
 *   期望值来源（永不取自被测公式）：
 *   - requant_model()：TB 独立实现——截断除法 + floor 修正 + RNE，
 *     与 DUT 的"移位+掩码"法不同构；
 *   - golden_requant.hex（ppu_requant_vecgen.py 产物，python int64
 *     oracle、P1 已对软件 golden 闭环）：双向交叉 model ≡ golden、
 *     DUT ≡ model。向量含构造平局（奇/偶 q、双号）、饱和双轨、
 *     死通道 M=0、恒等对全扫描、s=0..62 全域、随机全域 3000。
 *
 *   继承 GEMM 线 tail TB 纪律（run05）：每 negedge 驱动（gapn）、
 *   $random 无符号模、X 绊线、K=1 式记账守恒、rst 在飞击杀 + 恢复、
 *   看门狗。延迟记分板改为 posedge 三级 valid 镜像（cyc-tag 打戳法
 *   在 vsim 事件序下与驱动任务同沿竞争，run01 首跑教训）。
 * Revision History:
 *   - V1.1 (2026-09-19) by LSL : 延迟记分板改三级镜像；修 T3 模回绕。
 *   - V1.0 (2026-09-18) by LSL : Initial release (P2a).
 ************************************************************************/

`timescale 1ns/1ps

module tb_yolo_ppu_requant;

    // ---- DUT ----
    reg                clk, rst;
    reg                in_valid, in_last;
    reg signed [7:0]   x_in;
    reg signed [31:0]  m_in;
    reg        [5:0]   sh_in;
    wire               y_valid, y_last;
    wire signed [7:0]  y;

    yolo_ppu_requant #(.R(1)) dut (
        .clk_i(clk), .rst_i(rst),
        .in_valid_i(in_valid), .in_last_i(in_last),
        .x_i(x_in), .m_i(m_in), .sh_i(sh_in),
        .y_valid_o(y_valid), .y_last_o(y_last), .y_o(y)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;              //100 MHz

    // ---- 记账 ----
    integer checks, errors, lat_err;
    integer driven, y_cnt, flushed, last_seen;
    integer cyc;
    integer wp, rp;                    //期望队列指针
    reg signed [7:0] exp_y   [0:16383];
    reg                exp_last[0:16383];
    integer rs1, rs2, rs3, rs4;

    // ---- 独立 oracle：截断除 + floor 修正 + RNE（与 DUT 移位/掩码不同构）----
    function [7:0] requant_model(input signed [63:0] x64,
                                 input signed [63:0] m64,
                                 input [5:0] s);
        reg signed [63:0] p, fl, qn, qs;
        reg        [63:0] mod_u, hh, rr;
        begin
            p = x64 * m64;                      //oracle 积（64 位）
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
            qn = fl + (((rr > hh) || ((rr == hh) && fl[0])) ? 64'sd1
                                                             : 64'sd0);
            qs = (qn > 64'sd127)  ? 64'sd127
               : ((qn < -64'sd128) ? -64'sd128
               : qn);
            requant_model = qs[7:0];
        end
    endfunction

    // ---- 周期计数 + rst 采样延迟（避免与 initial 的同沿竞争）----
    always @(negedge clk) cyc = cyc + 1;
    reg rst_d;
    always @(posedge clk) rst_d <= rst;

    // ---- 延迟记分板：posedge 三级 valid 镜像（调度顺序无关）----
    // DUT 的 v1/v2/v3 与本镜像在同一 posedge 采样同一 in_valid；
    // negedge 检查器读到的两者均已稳定，绕开"检查器 vs 驱动任务
    // 同 negedge 竞争"的隐性竞态（vsim 与 xsim 事件序不同——本门
    // run01 首跑教训：cyc-tag 法在 vsim 下恒差 1）。
    reg tb_v1, tb_v2, tb_v3;
    always @(posedge clk) begin
        if (rst) begin
            tb_v1 <= 1'b0; tb_v2 <= 1'b0; tb_v3 <= 1'b0;
        end else begin
            tb_v1 <= in_valid;        //in_valid 只在 negedge 变化，此处稳定
            tb_v2 <= tb_v1;
            tb_v3 <= tb_v2;
        end
    end

    // ---- 检查器：每 negedge 全覆盖 ----
    reg signed [7:0] ey8;
    always @(negedge clk) begin
        if (rst_d) begin
            if (y_valid || y_last) begin      //rst 采样后不得有残影
                errors = errors + 1;
                $display("EES_REQUANT_ERR [%0t] y_valid/last during rst", $time);
            end
        end else begin
            if (y_valid !== tb_v3) begin
                lat_err = lat_err + 1;
                $display("EES_REQUANT_ERR [%0t] valid-timing y_valid=%b mirror=%b",
                         $time, y_valid, tb_v3);
            end
            if (y_valid) begin
                if (rp >= wp) begin
                    errors = errors + 1;
                    $display("EES_REQUANT_ERR [%0t] y_valid without expectation (rp=%0d wp=%0d)",
                             $time, rp, wp);
                end else begin
                    ey8 = exp_y[rp];
                    if (^y === 1'bx) begin
                        errors = errors + 1;
                        $display("EES_REQUANT_ERR [%0t] X on y_o (rp=%0d)", $time, rp);
                    end else if (y !== ey8) begin
                        errors = errors + 1;
                        $display("EES_REQUANT_ERR [%0t] y=%0d want=%0d",
                                 $time, y, ey8);
                    end else begin
                        checks = checks + 1;
                    end
                    if (y_last !== exp_last[rp]) begin
                        errors = errors + 1;
                        $display("EES_REQUANT_ERR [%0t] y_last=%b want %b",
                                 $time, y_last, exp_last[rp]);
                    end else if (y_last)
                        last_seen = last_seen + 1;
                    y_cnt = y_cnt + 1;
                    rp = rp + 1;
                end
            end else if (y_last) begin
                errors = errors + 1;
                $display("EES_REQUANT_ERR [%0t] y_last without y_valid", $time);
            end
        end
    end

    // ---- 驱动任务 ----
    task req_beat(input signed [7:0] xx, input signed [31:0] mm,
                  input [5:0] ss, input last);
        begin
            if ((^xx === 1'bx) || (^mm === 1'bx) || (^ss === 1'bx)) begin
                errors = errors + 1;
                $display("EES_REQUANT_ERR [%0t] X on driven inputs", $time);
            end
            x_in = xx; m_in = mm; sh_in = ss;
            in_valid = 1'b1; in_last = last;
            exp_y[wp]    = requant_model(xx, mm, ss);  //有符号实参自动扩 64 位
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

    // ---- 金文件读取 ----
    integer fd, rc, gvec;
    reg [8*128:1] line;
    reg [31:0] gx, gm, gs, gy;       //四列全十六进制
    reg [1023:0] golden_path;

    integer i, k;

    initial begin
        checks = 0; errors = 0; lat_err = 0;
        driven = 0; y_cnt = 0; flushed = 0; last_seen = 0;
        cyc = 0; wp = 0; rp = 0;
        rs1 = 21; rs2 = 22; rs3 = 33; rs4 = 44;
        in_valid = 0; in_last = 0;
        x_in = 0; m_in = 0; sh_in = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        gapn(2);

        if (!$value$plusargs("GOLDEN=%s", golden_path))
            golden_path = "golden_requant.hex";

        // ======== T0 GOLDEN：全向量双向交叉（模型≡金 + DUT≡模型）========
        fd = $fopen(golden_path, "r");
        gvec = 0;
        if (fd == 0) begin
            errors = errors + 1;
            $display("EES_REQUANT_ERR cannot open golden %s", golden_path);
        end else begin
            while ($fgets(line, fd) > 0) begin
                rc = $sscanf(line, "%h %h %h %h", gx, gm, gs, gy);
                if (rc == 4) begin
                    //交叉 1：独立模型 ≡ python oracle 金（模型自身过门）
                    if (requant_model($signed(gx[7:0]), $signed(gm),
                                      gs[5:0]) !== $signed(gy[7:0])) begin
                        errors = errors + 1;
                        $display("EES_REQUANT_ERR T0 model!=golden vec%0d (x=%h M=%h s=%0d y=%h)",
                                 gvec, gx, gm, gs, gy);
                    end else
                        checks = checks + 1;
                    //交叉 2：DUT ≡ 模型（检查器队列路径）
                    req_beat($signed(gx[7:0]), $signed(gm), gs[5:0], 1'b0);
                    gapn(1);
                    gvec = gvec + 1;
                end
            end
            $fclose(fd);
        end
        gapn(4);
        $display("EES_REQUANT_INFO T0_GOLDEN vecs=%0d (model<->golden + DUT<->model)", gvec);

        // ======== T1 TIE_EVEN：手册钉值 ±1.5/±2.5 → 偶（s=30）========
        req_beat(8'sd1,  32'sh60000000, 6'd30, 1'b0);   // +1.5 ->  2
        req_beat(-8'sd1, 32'sh60000000, 6'd30, 1'b0);   // -1.5 -> -2
        req_beat(8'sd1,  32'shA0000000, 6'd30, 1'b0);   // +2.5 ->  2
        req_beat(-8'sd1, 32'shA0000000, 6'd30, 1'b0);   // -2.5 -> -2
        // s=1 小步长平局：x*M 奇数即 rem=half（M=1）
        req_beat(8'sd3,  32'sd1, 6'd1, 1'b0);           // +1.5 ->  2
        req_beat(-8'sd3, 32'sd1, 6'd1, 1'b0);           // -1.5 -> -2
        req_beat(8'sd5,  32'sd1, 6'd2, 1'b0);           // +1.25 -> 1
        req_beat(-8'sd5, 32'sd1, 6'd2, 1'b0);           // -1.25 -> -1
        gapn(4);
        $display("EES_REQUANT_INFO T1_TIE_EVEN done");

        // ======== T2 SAT/EXTREME + shift 全域扫描 ========
        req_beat(8'sd127,  32'sh7FFFFFFF, 6'd30, 1'b0); // +254 -> 127
        req_beat(-8'sd128, 32'sh7FFFFFFF, 6'd30, 1'b0); // -256 -> -128
        req_beat(8'sd127,  32'sh7FFFFFFF, 6'd0,  1'b0); // s=0 巨积 -> 127
        req_beat(-8'sd128, 32'sh7FFFFFFF, 6'd0, 1'b0);  // s=0 巨积 -> -128
        for (k = 0; k <= 62; k = k + 1) begin
            req_beat(8'sd100, 32'sd1, k[5:0], 1'b0);
            req_beat(-8'sd100, 32'sd1, k[5:0], 1'b0);
        end
        gapn(4);
        $display("EES_REQUANT_INFO T2_SAT_EXTREME_SHIFT done");

        // ======== T3 IDENTITY：恒等对全扫描（y 必须逐位还原 x）========
        // x = k-128 经 8 位模运算回绕（k[7:0]-8'd128），k≥128 时避免
        // 9 位中间值溢出（run01 首跑教训：$signed(k[7:0])-128 产生
        // −256，任务入参截断为 0 而自检按 −256 比对 → 128 个假错）。
        for (k = 0; k < 256; k = k + 1) begin
            req_beat($signed(k[7:0] - 8'd128), 32'sh40000000, 6'd30, 1'b0);
            if (exp_y[wp-1] !== $signed(k[7:0] - 8'd128)) begin
                errors = errors + 1;
                $display("EES_REQUANT_ERR T3 identity exp mismatch k=%0d", k);
            end
            if ({$random(rs4)} % 4 == 0) gapn(1);
        end
        gapn(4);
        $display("EES_REQUANT_INFO T3_IDENTITY done (256 sweep)");

        // ======== T4 STREAM：400 背靠背随机流（域内 M 混 specialties）========
        for (k = 0; k < 400; k = k + 1) begin
            case ({$random(rs1)} % 16)
                0:       m_in = 32'd0;                   //死通道
                1:       m_in = 32'h40000000;            //恒等 M
                2:       m_in = 32'h7FFFFFFF;            //上界
                default: m_in = {$random(rs2)} & 32'h7FFFFFFF; //域内随机
            endcase
            req_beat($signed({$random(rs3)} % 256) - 128, m_in,
                     {$random(rs4)} % 63, (k == 399) ? 1'b1 : 1'b0);
            //背靠背为主，20% 随机气泡
            if ({$random(rs1)} % 5 == 0) gapn(1);
        end
        gapn(8);
        $display("EES_REQUANT_INFO T4_STREAM done (last beat tagged)");

        // ======== T5 GAPS + rst 在飞击杀 + 恢复 ========
        for (k = 0; k < 200; k = k + 1) begin
            req_beat($signed({$random(rs1)} % 256) - 128,
                     {$random(rs2)} & 32'h7FFFFFFF,
                     {$random(rs3)} % 63, 1'b0);
            gapn({$random(rs2)} % 6);
        end
        //rst 击杀：3 拍在飞（含已入流水未呈现的）
        req_beat(8'sd42,  32'sd1, 6'd1, 1'b0);
        req_beat(-8'sd7, 32'sh40000000, 6'd30, 1'b1);
        req_beat(8'sd8,  32'sd1, 6'd0, 1'b0);
        @(negedge clk);
        rst = 1'b1; in_valid = 1'b0; in_last = 1'b0;
        repeat (2) @(negedge clk);
        flushed = flushed + (wp - rp);        //在飞期望作废
        wp = 0; rp = 0;
        rst = 1'b0;
        gapn(6);                              //残影观察窗
        //击杀后恢复
        req_beat(8'sd42, 32'sd1, 6'd0, 1'b0);
        gapn(8);
        $display("EES_REQUANT_INFO T5_GAPS_RSTKILL done (flushed=%0d)", flushed);

        // ======== 收尾 ========
        gapn(4);
        if (wp != rp) begin
            errors = errors + 1;
            $display("EES_REQUANT_ERR queue not drained wp=%0d rp=%0d", wp, rp);
        end
        if ((y_cnt + flushed) != driven) begin
            errors = errors + 1;
            $display("EES_REQUANT_ERR conservation driven=%0d y=%0d flushed=%0d",
                     driven, y_cnt, flushed);
        end
        $display("EES_SUMMARY checks=%0d errors=%0d lat_err=%0d", checks, errors, lat_err);
        $display("EES_REQUANT_INFO driven=%0d y=%0d flushed=%0d last_seen=%0d",
                 driven, y_cnt, flushed, last_seen);
        if (errors == 0 && lat_err == 0)
            $display("EES_MODELSIM_RESULT PASS");
        else
            $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

    //看门狗
    initial begin
        #20_000_000;
        $display("EES_REQUANT_ERR watchdog timeout");
        $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

endmodule
