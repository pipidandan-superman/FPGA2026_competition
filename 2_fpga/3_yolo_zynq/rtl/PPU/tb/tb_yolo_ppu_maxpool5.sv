/************************************************************************
 * File Name     : tb_yolo_ppu_maxpool5.sv
 * Developer     : LSL
 * Date          : 2026-09-19
 * Project Name  : AMD embodied sorting / EES-331 XC7Z020
 * Module Name   : tb_yolo_ppu_maxpool5
 * Description   : P2c maxpool5 引擎核独立门仿真（PPU 手册 §7 P2c）。
 *
 *   DUT: rtl_ppu/yolo_ppu_maxpool5.sv（5x5 s1 SAME，有效位掩码结构，
 *   不物化 pad；(H+2)x(W+2) 处理网格，输入步握手/pad 步自走，
 *   in_ready 反压，CHW 线性输出，D+1 寄存输出，全 H/W>=1 通用）。
 *
 *   期望值三方互证（手册 §2.2 等价性实证义务）：
 *   - golden_maxpool5.hex：python pad(-128) 模型（P1 已对软件 golden
 *     闭环），含全-128/全127/边框图案/棋盘/双轨随机与 H/W<5 形状；
 *   - TB 模型：按输出位置直接索引 in_arr 的有效位掩码 max
 *     （结构=地址算术取数，与 DUT 流式移位 taps 不同构）；
 *   - 装载期交叉：TB 模型(CHW 序) ≡ 金文件 → pad 模型 ≡ 掩码模型
 *     在对抗向量上钉死等价；运行期 DUT ≡ 金文件逐拍比对。
 *
 *   用例：11 金形状（随机供数间隔反压）+ rst 在飞击杀重启全查 +
 *   X 绊线（out_data 不得出现 X）+ 收尾静默/busy 归零/守恒。
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : Initial release (P2c).
 ************************************************************************/

`timescale 1ns/1ps

module tb_yolo_ppu_maxpool5;

    // ---- DUT ----
    reg         clk, rst;
    reg         start;
    reg  [15:0] c_in, h_in, w_in;
    wire        in_ready;
    reg         in_valid;
    reg  [7:0]  in_data;
    wire        out_valid;
    wire [7:0]  out_data;
    wire        out_last;
    wire        busy;

    yolo_ppu_maxpool5 dut (
        .clk_i(clk), .rst_i(rst),
        .start_i(start), .c_i(c_in), .h_i(h_in), .w_i(w_in),
        .in_ready_o(in_ready), .in_valid_i(in_valid), .in_data_i(in_data),
        .out_valid_o(out_valid), .out_data_o(out_data),
        .out_last_o(out_last), .busy_o(busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;              //100 MHz

    // ---- 记账 ----
    integer checks, errors;
    integer rs1;

    // ---- 用例库 ----
    localparam integer MAXCASE = 32;
    localparam integer MAXBYT  = 200000;
    integer ncase;
    integer cs_c   [0:MAXCASE-1];
    integer cs_h   [0:MAXCASE-1];
    integer cs_w   [0:MAXCASE-1];
    integer cs_ino [0:MAXCASE-1];
    integer cs_eo  [0:MAXCASE-1];
    integer cs_nn  [0:MAXCASE-1];      //输入=输出字节数
    reg [7:0] in_arr  [0:MAXBYT-1];
    reg [7:0] exp_dt  [0:MAXBYT-1];

    // ---- 运行态 ----
    integer ci, in_cnt, out_cnt, k;

    // ---- TB 独立模型：按输出位置直接索引的掩码 max ----
    function [7:0] mp_model(input integer base, input integer hh,
                            input integer ww,
                            input integer cy, input integer cx);
        integer yy, xx, y0, y1, x0, x1;
        reg [7:0] m;
        begin
            y0 = (cy - 2 > 0) ? cy - 2 : 0;
            y1 = (cy + 2 < hh - 1) ? cy + 2 : hh - 1;
            x0 = (cx - 2 > 0) ? cx - 2 : 0;
            x1 = (cx + 2 < ww - 1) ? cx + 2 : ww - 1;
            m = 8'h80;
            for (yy = y0; yy <= y1; yy = yy + 1)
                for (xx = x0; xx <= x1; xx = xx + 1)
                    if ($signed(in_arr[base + yy*ww + xx]) > $signed(m))
                        m = in_arr[base + yy*ww + xx];
            mp_model = m;
        end
    endfunction

    // ---- 单拍输出检查 ----
    task chk_beat;
        reg [7:0] ed;
        reg       el;
        begin
            if (out_cnt >= cs_nn[ci]) begin
                errors = errors + 1;
                $display("EES_MAXP5_ERR [%0t] case%0d EXTRA output (cnt=%0d want=%0d)",
                         $time, ci, out_cnt, cs_nn[ci]);
            end else begin
                ed = exp_dt[cs_eo[ci] + out_cnt];
                el = (out_cnt == cs_nn[ci] - 1);
                if (^out_data === 1'bx) begin
                    errors = errors + 1;
                    $display("EES_MAXP5_ERR [%0t] case%0d beat%0d X on out_data",
                             $time, ci, out_cnt);
                end else if (out_data !== ed) begin
                    errors = errors + 1;
                    $display("EES_MAXP5_ERR [%0t] case%0d beat%0d data=%02h want=%02h",
                             $time, ci, out_cnt, out_data, ed);
                end else begin
                    checks = checks + 1;
                end
                if (out_last !== el) begin
                    errors = errors + 1;
                    $display("EES_MAXP5_ERR [%0t] case%0d beat%0d last=%b want=%b",
                             $time, ci, out_cnt, out_last, el);
                end
                out_cnt = out_cnt + 1;
            end
        end
    endtask

    // ---- 运行一个用例（随机输入间隔反压）----
    task run_case(input integer idx);
        begin
            ci = idx;
            @(negedge clk);
            start = 1'b1; c_in = cs_c[ci]; h_in = cs_h[ci]; w_in = cs_w[ci];
            @(negedge clk);
            start = 1'b0;
            in_cnt = 0; out_cnt = 0;
            while (out_cnt < cs_nn[ci]) begin
                in_valid = 1'b0;
                if (in_ready && (in_cnt < cs_nn[ci])) begin
                    in_valid = ({$random(rs1)} % 4) != 0;
                    if (in_valid) begin
                        in_data = in_arr[cs_ino[ci] + in_cnt];
                        in_cnt = in_cnt + 1;
                    end
                end
                @(negedge clk);
                if (out_valid)
                    chk_beat;
            end
            in_valid = 1'b0;
            //收尾静默 + busy 归零
            for (k = 0; k < 10; k = k + 1) begin
                @(negedge clk);
                if (out_valid) begin
                    errors = errors + 1;
                    $display("EES_MAXP5_ERR [%0t] case%0d output after done",
                             $time, ci);
                end
            end
            if (busy) begin
                errors = errors + 1;
                $display("EES_MAXP5_ERR [%0t] case%0d busy after done", $time, ci);
            end
            //输入守恒：全部输入已喂入
            if (in_cnt != cs_nn[ci]) begin
                errors = errors + 1;
                $display("EES_MAXP5_ERR case%0d input not consumed %0d/%0d",
                         ci, in_cnt, cs_nn[ci]);
            end
        end
    endtask

    // ---- 金文件读取 ----
    integer fd, rc;
    reg [8*128:1] line;
    integer gc, gh, gw, b, i, oy, ox;
    reg [1023:0] golden_path;
    integer ino, eo;

    initial begin
        checks = 0; errors = 0;
        rs1 = 21;
        ncase = 0;
        start = 0; c_in = 0; h_in = 0; w_in = 0;
        in_valid = 0; in_data = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;

        if (!$value$plusargs("GOLDEN=%s", golden_path))
            golden_path = "golden_maxpool5.hex";

        fd = $fopen(golden_path, "r");
        if (fd == 0) begin
            errors = errors + 1;
            $display("EES_MAXP5_ERR cannot open golden %s", golden_path);
        end else begin
            while ($fgets(line, fd) > 0) begin
                rc = $sscanf(line, "%d %d %d", gc, gh, gw);
                if (rc == 3 && gc > 0) begin
                    cs_c[ncase] = gc; cs_h[ncase] = gh; cs_w[ncase] = gw;
                    cs_nn[ncase] = gc * gh * gw;
                    if (ncase == 0) begin
                        cs_ino[ncase] = 0; cs_eo[ncase] = 0;
                    end else begin
                        cs_ino[ncase] = cs_ino[ncase-1] + cs_nn[ncase-1];
                        cs_eo[ncase]  = cs_eo[ncase-1] + cs_nn[ncase-1];
                    end
                    ino = cs_ino[ncase]; eo = cs_eo[ncase];
                    for (i = 0; i < cs_nn[ncase]; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%h", b);
                        in_arr[ino + i] = b[7:0];
                    end
                    for (i = 0; i < cs_nn[ncase]; i = i + 1) begin
                        rc = $fgets(line, fd);
                        rc = $sscanf(line, "%h", b);
                        exp_dt[eo + i] = b[7:0];
                    end
                    //交叉：TB 直接索引掩码模型 ≡ python pad 模型金
                    for (oy = 0; oy < gh; oy = oy + 1)
                        for (ox = 0; ox < gw; ox = ox + 1) begin
                            if (mp_model(ino, gh, gw, oy, ox)
                                !== exp_dt[eo + oy*gw + ox]) begin
                                errors = errors + 1;
                                $display("EES_MAXP5_ERR CROSS case%0d (%0d,%0d) model!=golden",
                                         ncase, oy, ox);
                            end else
                                checks = checks + 1;
                        end
                    ncase = ncase + 1;
                end
            end
            $fclose(fd);
        end
        $display("EES_MAXP5_INFO loaded %0d golden cases (cross done)", ncase);

        // ============ T1 全形状逐个跑 ============
        for (i = 0; i < ncase; i = i + 1)
            run_case(i);
        $display("EES_MAXP5_INFO T1 all %0d cases done", ncase);

        // ============ T2 rst 在飞击杀 + 重启全查 ============
        ci = 7;                              //case (2,4,7)
        @(negedge clk);
        start = 1'b1; c_in = cs_c[ci]; h_in = cs_h[ci]; w_in = cs_w[ci];
        @(negedge clk);
        start = 1'b0;
        in_cnt = 0; out_cnt = 0;
        while (in_cnt < 10 && in_cnt < cs_nn[ci]) begin
            in_valid = in_ready;
            if (in_valid) begin
                in_data = in_arr[cs_ino[ci] + in_cnt];
                in_cnt = in_cnt + 1;
            end
            @(negedge clk);
            if (out_valid)
                chk_beat;
        end
        @(negedge clk);
        rst = 1'b1; in_valid = 1'b0;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        for (k = 0; k < 8; k = k + 1) begin
            @(negedge clk);
            if (out_valid) begin
                errors = errors + 1;
                $display("EES_MAXP5_ERR [%0t] output during/after rst", $time);
            end
        end
        run_case(ci);
        $display("EES_MAXP5_INFO T2_RSTKILL done");

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
        #40_000_000;
        $display("EES_MAXP5_ERR watchdog timeout");
        $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

endmodule
