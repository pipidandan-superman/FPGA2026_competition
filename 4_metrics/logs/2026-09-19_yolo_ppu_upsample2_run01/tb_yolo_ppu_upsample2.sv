/************************************************************************
 * File Name     : tb_yolo_ppu_upsample2.sv
 * Developer     : LSL
 * Date          : 2026-09-19
 * Project Name  : AMD embodied sorting / EES-331 XC7Z020
 * Module Name   : tb_yolo_ppu_upsample2
 * Description   : P2b upsample2 引擎核独立门仿真（PPU 手册 §7 P2b）。
 *
 *   DUT: rtl_ppu/yolo_ppu_upsample2.sv（最近邻 ×2 字节流核：每输入
 *   字节发射 4 拍 (dy,dx)=00/01/10/11，in_ready 反压，增量加法寻址，
 *   out_last 随末拍脉冲，D+1..D+4 寄存输出）。
 *
 *   期望值来源（永不取自被测结构）：
 *   - golden_upsample2.hex（ppu_upsample2_vecgen.py：ppu_oracle.
 *     upsample2_q + 直接地址公式，含 11 形状：本包真实 (256,10,10)/
 *     (128,20,20) + 合成边角 1x1x1/W=1/H=1/C=1/奇宽/奇高）；
 *   - TB 按地址收集交叉：把金文件期望按 addr 收集成表，再断言每拍
 *     数据 == in[c][y=oy>>1][x=ox>>1]（与发射序不同构）；
 *   - TB 乘法公式模型生成 2 个随机形状（DUT 为增量加法，不同构）。
 *
 *   用例：全 11 金形状 + 2 TB 随机形状（随机输入间隔反压）+ 长停顿
 *   案例 + rst 在飞击杀后重启同形状全查 + 收尾 idle/busy 检查。
 *   检查项：每拍 addr+data、out_last 恰在末拍、无多余输出、任务后
 *   out_valid 静默、busy 归零。
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : Initial release (P2b).
 ************************************************************************/

`timescale 1ns/1ps

module tb_yolo_ppu_upsample2;

    // ---- DUT ----
    reg         clk, rst;
    reg         start;
    reg  [15:0] c_in, h_in, w_in;
    wire        in_ready;
    reg         in_valid;
    reg  [7:0]  in_data;
    wire        out_valid;
    wire [7:0]  out_data;
    wire [31:0] out_addr;
    wire        out_last;
    wire        busy;

    yolo_ppu_upsample2 dut (
        .clk_i(clk), .rst_i(rst),
        .start_i(start), .c_i(c_in), .h_i(h_in), .w_i(w_in),
        .in_ready_o(in_ready), .in_valid_i(in_valid), .in_data_i(in_data),
        .out_valid_o(out_valid), .out_data_o(out_data),
        .out_addr_o(out_addr), .out_last_o(out_last), .busy_o(busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;              //100 MHz

    // ---- 记账 ----
    integer checks, errors;
    integer rs1, rs2;

    // ---- 用例库（金文件 + TB 自生成）----
    localparam integer MAXCASE = 32;
    localparam integer MAXIN   = 100000;
    localparam integer MAXOUT  = 340000;
    integer ncase;
    integer cs_c   [0:MAXCASE-1];
    integer cs_h   [0:MAXCASE-1];
    integer cs_w   [0:MAXCASE-1];
    integer cs_ino [0:MAXCASE-1];      //in_arr 内偏移
    integer cs_eo  [0:MAXCASE-1];      //exp_arr 内偏移
    integer cs_inn [0:MAXCASE-1];      //输入字节数
    integer cs_onn [0:MAXCASE-1];      //输出拍数
    reg [7:0]  in_arr  [0:MAXIN-1];
    reg [31:0] exp_ad  [0:MAXOUT-1];
    reg [7:0]  exp_dt  [0:MAXOUT-1];

    // ---- 运行态 ----
    integer ci, in_cnt, out_cnt, k, ec;

    // ---- 单拍输出检查 ----
    task chk_beat;
        reg [31:0] ea;
        reg [7:0]  ed;
        reg        el;
        begin
            if (out_cnt >= cs_onn[ci]) begin
                errors = errors + 1;
                $display("EES_UPS2_ERR [%0t] case%0d EXTRA output (cnt=%0d want=%0d)",
                         $time, ci, out_cnt, cs_onn[ci]);
            end else begin
                ea = exp_ad[cs_eo[ci] + out_cnt];
                ed = exp_dt[cs_eo[ci] + out_cnt];
                el = (out_cnt == cs_onn[ci] - 1);
                if (out_addr !== ea) begin
                    errors = errors + 1;
                    $display("EES_UPS2_ERR [%0t] case%0d beat%0d addr=%0d want=%0d",
                             $time, ci, out_cnt, out_addr, ea);
                end else if (out_data !== ed) begin
                    errors = errors + 1;
                    $display("EES_UPS2_ERR [%0t] case%0d beat%0d data=%02h want=%02h",
                             $time, ci, out_cnt, out_data, ed);
                end else begin
                    checks = checks + 1;
                end
                if (out_last !== el) begin
                    errors = errors + 1;
                    $display("EES_UPS2_ERR [%0t] case%0d beat%0d last=%b want=%b",
                             $time, ci, out_cnt, out_last, el);
                end
                out_cnt = out_cnt + 1;
            end
        end
    endtask

    // ---- 运行一个用例（随机输入间隔反压）----
    // gapmode: 0=常供, 1=25% 随机间隔, 2=每 50 字节长停顿 7 拍
    task run_case(input integer idx, input integer gapmode);
        integer stall;
        begin
            ci = idx;
            @(negedge clk);
            start = 1'b1; c_in = cs_c[ci]; h_in = cs_h[ci]; w_in = cs_w[ci];
            @(negedge clk);
            start = 1'b0;
            in_cnt = 0; out_cnt = 0; stall = 0;
            while (out_cnt < cs_onn[ci]) begin
                in_valid = 1'b0;
                if (in_ready && (in_cnt < cs_inn[ci])) begin
                    if (gapmode == 0)
                        in_valid = 1'b1;
                    else if (gapmode == 1)
                        in_valid = ({$random(rs1)} % 4) != 0;
                    else begin
                        in_valid = (stall == 0);
                        if (in_cnt % 50 == 49 && stall == 0 && in_valid)
                            stall = 7;
                    end
                    if (in_valid) begin
                        in_data = in_arr[cs_ino[ci] + in_cnt];
                        in_cnt = in_cnt + 1;
                    end
                end
                if (stall > 0) stall = stall - 1;
                @(negedge clk);
                if (out_valid)
                    chk_beat;
                if (in_cnt == cs_inn[ci] && out_cnt == cs_onn[ci])
                    in_valid = 1'b0;
            end
            //收尾静默 + busy 归零
            in_valid = 1'b0;
            for (k = 0; k < 8; k = k + 1) begin
                @(negedge clk);
                if (out_valid) begin
                    errors = errors + 1;
                    $display("EES_UPS2_ERR [%0t] case%0d output after done", $time, ci);
                end
            end
            if (busy) begin
                errors = errors + 1;
                $display("EES_UPS2_ERR [%0t] case%0d busy after done", $time, ci);
            end
        end
    endtask

    // ---- TB 自生成用例（乘法公式模型，与 DUT 增量加法不同构）----
    task gen_case_tb(input integer cc, input integer hh, input integer ww);
        integer ino, eo, plane, rowl, xx, yy, cx, a0, off;
        begin
            ino = 0; eo = 0;
            if (ncase > 0) begin
                ino = cs_ino[ncase-1] + cs_inn[ncase-1];
                eo  = cs_eo[ncase-1] + cs_onn[ncase-1];
            end
            cs_c[ncase] = cc; cs_h[ncase] = hh; cs_w[ncase] = ww;
            cs_ino[ncase] = ino; cs_eo[ncase] = eo;
            cs_inn[ncase] = cc * hh * ww;
            cs_onn[ncase] = 4 * cc * hh * ww;
            plane = 4 * hh * ww;
            rowl  = 2 * ww;
            for (cx = 0; cx < cc; cx = cx + 1)
                for (yy = 0; yy < hh; yy = yy + 1)
                    for (xx = 0; xx < ww; xx = xx + 1) begin
                        in_arr[ino + cx*hh*ww + yy*ww + xx] =
                            {$random(rs2)} % 256;
                        a0 = cx * plane + 2 * yy * rowl + 2 * xx;
                        for (off = 0; off < 4; off = off + 1) begin
                            exp_ad[eo] = a0 + ((off == 0) ? 0 :
                                               (off == 1) ? 1 :
                                               (off == 2) ? rowl : rowl + 1);
                            exp_dt[eo] = in_arr[ino + cx*hh*ww + yy*ww + xx];
                            eo = eo + 1;
                        end
                    end
            ncase = ncase + 1;
        end
    endtask

    // ---- 金文件读取 ----
    integer fd, rc;
    reg [8*128:1] line;
    integer gc, gh, gw, b;
    reg [31:0] ga, gd;
    reg [1023:0] golden_path;
    integer ino, eo, i;

    initial begin
        checks = 0; errors = 0;
        rs1 = 21; rs2 = 22;
        ncase = 0;
        start = 0; c_in = 0; h_in = 0; w_in = 0;
        in_valid = 0; in_data = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;

        if (!$value$plusargs("GOLDEN=%s", golden_path))
            golden_path = "golden_upsample2.hex";

        fd = $fopen(golden_path, "r");
        if (fd == 0) begin
            errors = errors + 1;
            $display("EES_UPS2_ERR cannot open golden %s", golden_path);
        end else begin
            while ($fgets(line, fd) > 0) begin
                rc = $sscanf(line, "%d %d %d", gc, gh, gw);
                if (rc == 3 && gc > 0) begin
                    cs_c[ncase] = gc; cs_h[ncase] = gh; cs_w[ncase] = gw;
                    cs_inn[ncase] = gc * gh * gw;
                    cs_onn[ncase] = 4 * gc * gh * gw;
                    if (ncase == 0) begin
                        cs_ino[ncase] = 0; cs_eo[ncase] = 0;
                    end else begin
                        cs_ino[ncase] = cs_ino[ncase-1] + cs_inn[ncase-1];
                        cs_eo[ncase]  = cs_eo[ncase-1] + cs_onn[ncase-1];
                    end
                    ino = cs_ino[ncase]; eo = cs_eo[ncase];
                    for (i = 0; i < cs_inn[ncase]; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%h", b);
                        in_arr[ino + i] = b[7:0];
                    end
                    for (i = 0; i < cs_onn[ncase]; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%h %h", ga, gd);
                        exp_ad[eo + i] = ga;
                        exp_dt[eo + i] = gd[7:0];
                    end
                    //交叉：按地址收集（期望拍数据 == 源输入字节）
                    for (i = 0; i < cs_onn[ncase]; i = i + 1) begin
                        // addr = c*4HW + (2y+dy)*2W + 2x+dx -> 源 = in[...]
                        // 由 addr 反解源输入下标：oy=addr/2W, ox=addr%2W
                        ec = exp_ad[eo + i];
                        k = ((ec / (2 * gw)) % (2 * gh)) / 2; //源 y
                        b = ((ec % (2 * gw)) / 2);            //源 x
                        k = k * gw + b;                        //行内源偏移
                        k = k + ((ec / (4 * gw * gh)) * gw * gh); //加 c 面
                        if (exp_dt[eo + i] !== in_arr[ino + k]) begin
                            errors = errors + 1;
                            $display("EES_UPS2_ERR CROSS case%0d beat%0d addr=%0d data=%02h != src %02h",
                                     ncase, i, ec, exp_dt[eo + i], in_arr[ino + k]);
                        end else
                            checks = checks + 1;
                    end
                    ncase = ncase + 1;
                end else if (rc == 3 && gc == 0) begin
                    // terminator
                end
            end
            $fclose(fd);
        end
        $display("EES_UPS2_INFO loaded %0d golden cases (cross done)", ncase);

        //TB 自生成随机形状（模型=乘法公式）
        gen_case_tb(7, 13, 9);
        gen_case_tb(31, 5, 6);

        // ============ T1 金形状逐个跑（混合供数模式）============
        for (i = 0; i < ncase; i = i + 1) begin
            run_case(i, (i % 3 == 0) ? 0 : ((i % 3 == 1) ? 1 : 2));
        end
        $display("EES_UPS2_INFO T1 all %0d cases done", ncase);

        // ============ T2 rst 在飞击杀 + 重启全查 ============
        ci = 6;                              //case (3,5,4)：60 字节
        @(negedge clk);
        start = 1'b1; c_in = cs_c[ci]; h_in = cs_h[ci]; w_in = cs_w[ci];
        @(negedge clk);
        start = 1'b0;
        in_cnt = 0; out_cnt = 0;
        while (in_cnt < 20 && in_cnt < cs_inn[ci]) begin  //喂 20 字节后击杀
            in_valid = in_ready;
            if (in_valid) begin
                in_data = in_arr[cs_ino[ci] + in_cnt];
                in_cnt = in_cnt + 1;
            end
            @(negedge clk);
            if (out_valid)
                chk_beat;                    //击杀前输出仍须逐拍正确
        end
        @(negedge clk);
        rst = 1'b1; in_valid = 1'b0;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        for (k = 0; k < 6; k = k + 1) begin  //残影观察
            @(negedge clk);
            if (out_valid) begin
                errors = errors + 1;
                $display("EES_UPS2_ERR [%0t] output during/after rst", $time);
            end
        end
        run_case(ci, 1);                     //重启同形状，全量复检
        $display("EES_UPS2_INFO T2_RSTKILL done");

        // ======== 收尾 ========
        $display("EES_SUMMARY checks=%0d errors=%0d", checks, errors);
        if (errors == 0)
            $display("EES_MODELSIM_RESULT PASS");
        else
            $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

    //看门狗
    initial begin
        #80_000_000;
        $display("EES_UPS2_ERR watchdog timeout");
        $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

endmodule
