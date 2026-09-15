// G3 首层 conv testbench：加载 stim hex -> 跑核 -> 与 golden 期望逐字节比对。
// 用法（ModelSim，在 sim/msim 下）：
//   vsim -c work.tb_yolo_conv0 +STIM=../stim/conv0_golden00 [+PARTIAL=500] [+CORE0/02]
// 数值门：全部有效元素零差异 -> 打印 TB_CONV0_PASS / 否则 TB_CONV0_FAIL + 首错信息。
`timescale 1ns/1ps
module tb_yolo_conv0;

    localparam int NX = 307200, NW = 432, NP = 16, NL = 256, NY = 409600;

    logic clk = 0, rst_n = 0, start = 0;
    logic busy, done, y_we;
    logic [18:0] x_addr;
    logic [8:0]  w_addr;
    logic [3:0]  bias_addr, m_addr, shift_addr;
    logic [7:0]  lut_addr;
    logic [19:0] y_addr;
    logic signed [7:0] x_rdata, w_rdata, lut_rdata, y_wdata;
    logic signed [31:0] bias_rdata, m_rdata;
    logic [7:0] shift_rdata;

    // ---- 行为 RAM（组合读） ----
    logic signed [7:0]  mem_x [0:NX-1];
    logic signed [7:0]  mem_w [0:NW-1];
    logic signed [31:0] mem_bias [0:NP-1];
    logic signed [31:0] mem_m [0:NP-1];
    logic [7:0]         mem_shift [0:NP-1];
    logic signed [7:0]  mem_lut [0:NL-1];
    logic signed [7:0]  mem_y [0:NY-1];
    logic signed [7:0]  mem_yexp [0:NY-1];

    assign x_rdata     = mem_x[x_addr];
    assign w_rdata     = mem_w[w_addr];
    assign bias_rdata  = mem_bias[bias_addr];
    assign m_rdata     = mem_m[m_addr];
    assign shift_rdata = mem_shift[shift_addr];
    assign lut_rdata   = mem_lut[lut_addr];

    // DUT 输出写入（寄存的 we/addr/data）
    always @(posedge clk) if (y_we) mem_y[y_addr] <= y_wdata;

    yolo_conv0_core dut (.*);

    always #5 clk = ~clk;

    int unsigned n_cmp = NY, n_err = 0, first_i = 0;
    logic signed [7:0] first_got, first_exp;
    string stim = "../stim/conv0_golden00";
    int unsigned partial = 0;

    initial begin
        void'($value$plusargs("STIM=%s", stim));
        void'($value$plusargs("PARTIAL=%d", partial));
        if (partial > 0) n_cmp = partial;
        $display("[tb] stim=%s partial=%0d", stim, partial);

        $readmemh({stim, "/x_i8.hex"},         mem_x);
        $readmemh({stim, "/w_i8.hex"},         mem_w);
        $readmemh({stim, "/bias_eff_i32.hex"}, mem_bias);
        $readmemh({stim, "/m_i32.hex"},        mem_m);
        $readmemh({stim, "/shift_u8.hex"},     mem_shift);
        $readmemh({stim, "/lut_i8.hex"},       mem_lut);
        $readmemh({stim, "/y_exp_i8.hex"},     mem_yexp);
        foreach (mem_y[i]) mem_y[i] = 0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
    end

    // 看门狗：满量 409600 像素 × 29 拍 ≈ 11.9M 拍 ≈ 119ms，留裕量 200ms
    initial begin
        #200_000_000;
        $display("TB_CONV0_FAIL (timeout)");
        $finish;
    end

    // 比对触发：写满 n_cmp 个像素（或全量 done 兜底）后一拍执行
    int unsigned n_wr = 0;
    logic cmp_pending;

    always @(posedge clk) begin
        if (y_we) begin
            n_wr++;
            if (n_wr == n_cmp) cmp_pending <= 1'b1;
        end
        if (cmp_pending) begin
            cmp_pending <= 1'b0;
            for (int unsigned i = 0; i < n_cmp; i++) begin
                if (mem_y[i] !== mem_yexp[i]) begin
                    n_err++;
                    if (n_err == 1) begin
                        first_i = i;
                        first_got = mem_y[i];
                        first_exp = mem_yexp[i];
                        $display("[tb] first mismatch @oc=%0d oy=%0d ox=%0d (lin=%0d) got=%0d exp=%0d",
                                 i/25600, (i%25600)/160, i%160, i, mem_y[i], mem_yexp[i]);
                    end
                end
            end
            if (n_err == 0)
                $display("TB_CONV0_PASS compared=%0d/%0d (stim=%s)", n_cmp, NY, stim);
            else
                $display("TB_CONV0_FAIL compared=%0d/%0d errors=%0d first_lin=%0d got=%0d exp=%0d",
                         n_cmp, NY, n_err, first_i, first_got, first_exp);
            $finish;
        end
    end

endmodule
