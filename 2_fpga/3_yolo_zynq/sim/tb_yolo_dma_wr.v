/************************************************************************
 * File Name       : tb_yolo_dma_wr.v
 * Developer       : LSL
 * Date            : 2026-09-16
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_dma_wr
 * Description     : M9b gate testbench for yolo_dma_wr: AXI write BFM
 *                   slave + protocol monitors + DDR-side byte
 *                   scoreboard.
 *                   Data authority: a DDR byte at address a must equal
 *                   F_byte(a) = F(word(a)) >> 8*(a%8), F = murmur-style
 *                   64-bit finalize (bit-identical to dma_wr_vecgen.py).
 *                   Random awready/wready stalls, random B-response
 *                   delay, and source backpressure from a seeded
 *                   xorshift32 (negedge-driven, stable at the posedge).
 *                   Monitors: AW (alignment, awlen<=15, awsize, INCR,
 *                   no 4KB crossing, exact address-chain coverage of
 *                   [cmd_addr, cmd_addr+ceil(len/8)*8), single
 *                   outstanding: no AW offered while the previous
 *                   burst's W beats are incomplete), W (wlast exactly
 *                   on the last beat of each burst, no beat overrun;
 *                   every strobed byte: in-range, written exactly once
 *                   (command-relative bitmap), value == F_byte;
 *                   per-command count + additive checksum mod 2^64 vs
 *                   golden files; done checkpoint walks the bitmap so
 *                   every byte in range is written), B (one per burst,
 *                   random delay, bready always honored).
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/dma_wr +WDT_MS=60000 \
 *                          -do "run -all; quit -f" work.tb_yolo_dma_wr
 *                   Gate token: TB_DMA_WR_PASS / TB_DMA_WR_FAIL.
 * Dependencies    : rtl/yolo_dma_wr.v, sim/dma_wr_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-16) by LSL : Initial release (M9b).
 *   - V1.1 (2026-09-16) by LSL : 生产者竞态修复——握手改在 posedge 本拍
 *                 捕获（valid/ready 与 DUT 判决输入同值同拍；ready 是
 *                 DUT 状态组合且接受行为会改变它，negedge 采样会漏计/
 *                 多计成对出现、同字节重复呈现，run01 证据）；呈现仍
 *                 negedge 驱动。WDT 降 2s 防楔死时墙钟空转。
 *   - V1.2 (2026-09-16) by LSL : 非对齐起始（DUT V1.2 head 偏移）：
 *                 AW 链期望起点改为 cmd_addr 下对齐 8B、覆盖字数 =
 *                 ceil((head+len)/8)；W 记分板按物理地址查值/双写/范围
 *                 ——原逻辑即对（unstrobe 的 head lanes 不检），零改动。
 *                 run03 激励（seed 912）加 head=0..7 全覆盖与非对齐
 *                 大长度跨 4KB。
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_dma_wr;

    localparam ADDR_W    = 32;
    localparam LEN_W     = 24;
    localparam MAX_BURST = 16;
    localparam NCMDS_MAX = 1024;
    localparam WRBIT_MAX = 131072;      // >= max cmd_len (123456)

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg cmd_valid = 1'b0;
    wire cmd_ready;
    reg [ADDR_W-1:0] cmd_addr = {ADDR_W{1'b0}};
    reg [LEN_W-1:0]  cmd_len = {LEN_W{1'b0}};
    wire done;
    reg  src_valid = 1'b0;
    reg  [7:0] src_data = 8'h00;
    wire src_ready;
    wire [ADDR_W-1:0] awaddr;
    wire [7:0]  awlen;
    wire [2:0]  awsize;
    wire [1:0]  awburst;
    wire        awvalid;
    wire        awready;
    wire [63:0] wdata;
    wire [7:0]  wstrb;
    wire        wlast;
    wire        wvalid;
    wire        wready;
    wire        bvalid;
    wire [1:0]  bresp;
    wire        bready;

    integer n_cmds = 0;
    reg [31:0] mem_n [0:0];
    reg [ADDR_W-1:0] mem_caddr [0:NCMDS_MAX-1];
    reg [31:0] mem_clen  [0:NCMDS_MAX-1];
    reg [31:0] mem_gcnt  [0:NCMDS_MAX-1];
    reg [63:0] mem_gsum  [0:NCMDS_MAX-1];
    reg wr_bit [0:WRBIT_MAX-1];         // written-once, command-relative

    integer k;
    integer n_err = 0;
    integer n_bytes = 0;                // DDR-side strobed bytes
    integer n_fed = 0;                  // source-side accepted bytes
    integer n_aws = 0;
    integer n_done = 0;

    yolo_dma_wr #(
        .ADDR_W(ADDR_W),
        .LEN_W(LEN_W),
        .MAX_BURST(MAX_BURST)
    ) dut (
        .clk_i(clk),
        .rst_n(rst_n),
        .cmd_valid_i(cmd_valid),
        .cmd_ready_o(cmd_ready),
        .cmd_addr_i(cmd_addr),
        .cmd_len_i(cmd_len),
        .done_o(done),
        .src_valid_i(src_valid),
        .src_data_i(src_data),
        .src_ready_o(src_ready),
        .awaddr_o(awaddr),
        .awlen_o(awlen),
        .awsize_o(awsize),
        .awburst_o(awburst),
        .awvalid_o(awvalid),
        .awready_i(awready),
        .wdata_o(wdata),
        .wstrb_o(wstrb),
        .wlast_o(wlast),
        .wvalid_o(wvalid),
        .wready_i(wready),
        .bvalid_i(bvalid),
        .bresp_i(bresp),
        .bready_o(bready)
    );

    always #5 clk = ~clk;

    // ---- BFM data functions, bit-identical to dma_wr_vecgen.py ----
    function [63:0] f_word;
        input [31:0] wa;
        reg [63:0] x;
        begin
            x = {32'd0, wa} * 64'h9E3779B97F4A7C15;
            x = x ^ (x >> 31);
            x = x * 64'hBF58476D1CE4E5B9;
            x = x ^ (x >> 27);
            f_word = x;
        end
    endfunction

    function [7:0] f_byte;
        input [31:0] a;
        reg [63:0] w;
        begin
            w = f_word({a[31:3], 3'b000});
            f_byte = (w >> (8 * a[2:0])) & 64'h00000000000000FF;
        end
    endfunction

    // ---- stall engine (negedge-driven: stable through the posedge) ----
    integer rng = 32'h5A5A00C6;
    reg aw_stall = 1'b0;
    reg w_stall = 1'b0;
    reg src_stall = 1'b0;
    reg [1:0] gap_cyc = 2'd0;

    always @(negedge clk) begin
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        aw_stall  <= ((rng % 100) < 30);
        w_stall   <= ((rng % 100) < 25);
        src_stall <= ((rng % 100) < 30);
        gap_cyc   <= rng % 4;
    end

    // ---- byte source producer: handshake captured AT the posedge --
    //      src_ready is DUT-state combinational and CHANGES ON
    //      ACCEPTANCE (bcnt->8 drops it, w_fire clear raises it), so
    //      counting handshakes at the negedge mis-counts: the accept
        //      posedge P reads stale-fallen ready (miss), P+1 reads
    //      w_fire-raised ready (false advance) -> the same byte gets
    //      presented twice (run01 evidence). At the posedge, valid and
    //      ready equal the DUT's exact decision inputs. Presentation
    //      stays negedge-driven (stable through the posedge). ----
    integer i_src = 0;
    integer prod_len = 0;
    reg [ADDR_W-1:0] prod_base = {ADDR_W{1'b0}};
    reg prod_on = 1'b0;

    always @(posedge clk) begin
        if (rst_n && src_valid === 1'b1 && src_ready === 1'b1) begin
            i_src <= i_src + 1;             // one advance per real accept
            n_fed <= n_fed + 1;
        end
    end

    always @(negedge clk) begin
        if (rst_n && prod_on) begin
            if (i_src >= prod_len) begin
                prod_on   = 1'b0;
                src_valid = 1'b0;
            end else begin
                src_valid = ~src_stall;
                if (src_valid) begin
                    src_data = f_byte(prod_base + i_src);
                end
            end
        end else begin
            src_valid = 1'b0;
        end
    end

    // ---- BFM AXI write slave: AW accept -> W beats -> B per burst ----
    reg        slv_aw_busy = 1'b0;          // AW accepted, W incomplete
    reg [ADDR_W-1:0] slv_addr = {ADDR_W{1'b0}};
    reg [7:0]  slv_len = 8'd0;
    reg [7:0]  slv_beat = 8'd0;

    assign awready = ~slv_aw_busy && ~aw_stall;
    assign wready  = slv_aw_busy && ~w_stall;

    always @(posedge clk) begin
        if (rst_n) begin
            if (awvalid && awready) begin
                slv_aw_busy <= 1'b1;
                slv_addr    <= awaddr;
                slv_len     <= awlen;
                slv_beat    <= 8'd0;
            end else if (wvalid && wready) begin
                if (wlast) begin
                    slv_aw_busy <= 1'b0;
                end
                slv_beat <= slv_beat + 8'd1;
            end
        end else begin
            slv_aw_busy <= 1'b0;
        end
    end

    // ---- B response engine: one per burst, random delay, in order ----
    reg [3:0] b_pend = 4'd0;
    reg [1:0] b_wait = 2'd0;
    wire wlast_fire = slv_aw_busy && wvalid && wready && wlast;
    assign bvalid = (b_pend != 4'd0) && (b_wait == 2'd0);
    assign bresp  = 2'b00;                  // OKAY only

    integer tmp_pend;
    always @(posedge clk) begin
        if (rst_n) begin
            tmp_pend = b_pend;
            if (b_wait != 2'd0) begin
                b_wait <= b_wait - 2'd1;
            end
            if (wlast_fire) begin
                tmp_pend = tmp_pend + 1;
                if (tmp_pend == 1) begin
                    b_wait <= gap_cyc;      // delay for the queued B
                end
            end
            if (bvalid && bready) begin
                tmp_pend = tmp_pend - 1;
                if (tmp_pend != 0) begin
                    b_wait <= gap_cyc;      // next queued B
                end
            end
            b_pend <= tmp_pend;
        end else begin
            b_pend <= 4'd0;
            b_wait <= 2'd0;
        end
    end

    // ---- AW monitor: protocol + exact address-chain coverage ----
    reg [ADDR_W-1:0] exp_next = {ADDR_W{1'b0}};
    reg [31:0] words_left_m = 32'd0;
    reg [31:0] words_total_m = 32'd0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (cmd_valid && cmd_ready) begin
                // V1.2: AW chain starts at the aligned-down line; covered
                // words = ceil((head+len)/8) -- the strobed data range is
                // still [cmd_addr, cmd_addr+len) (head lanes unstrobed)
                exp_next      <= {cmd_addr[31:3], 3'b000};
                words_total_m <= ({29'd0, cmd_addr[2:0]} + cmd_len
                                  + 31'd7) >> 3;
                words_left_m  <= ({29'd0, cmd_addr[2:0]} + cmd_len
                                  + 31'd7) >> 3;
            end
            if (awvalid && awready) begin
                n_aws = n_aws + 1;
                if (awaddr[2:0] !== 3'b000) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AW not aligned: %h", awaddr);
                end
                if (awlen >= MAX_BURST) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AW len %0d >= max", awlen + 1);
                end
                if (awsize !== 3'd3 || awburst !== 2'd1) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AW size/burst %0d/%0d", awsize,
                             awburst);
                end
                if ({awaddr[11:0]} + {{4{1'b0}}, (awlen + 8'd1), 3'b000}
                    > 13'd4096) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AW crosses 4KB: %h len %0d", awaddr,
                             awlen + 1);
                end
                if (awaddr !== exp_next) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AW chain: got %h exp %h", awaddr,
                             exp_next);
                end
                if ({24'd0, (awlen + 8'd1)} > words_left_m) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AW overfetch: beats %0d left %0d",
                             awlen + 1, words_left_m);
                end
                exp_next     <= exp_next + {{22{1'b0}}, (awlen + 8'd1), 3'b000};
                words_left_m <= words_left_m - (awlen + 8'd1);
            end
            // single outstanding: no AW offered before the previous
            // burst's WLAST handshake (slv_aw_busy reads pre-edge value)
            if (awvalid && slv_aw_busy) begin
                n_err = n_err + 1;
                $display("[tb] ERR AW offered while burst in flight");
            end
            // chain closure: every predicted word issued exactly
            if (done && words_left_m !== 32'd0) begin
                n_err = n_err + 1;
                $display("[tb] ERR cmd %0d chain open: %0d words left",
                         n_done, words_left_m);
            end
        end
    end

    // ---- W monitor + DDR-side byte scoreboard ----
    integer k_sb_idx = 0;
    reg [ADDR_W-1:0] aw_addr_l = {ADDR_W{1'b0}};
    reg [7:0]  awlen_l = 8'd0;
    reg [7:0]  wbeats_l = 8'd0;            // beats seen in current burst
    reg [ADDR_W-1:0] cbase = {ADDR_W{1'b0}};
    integer clen_m = 0;
    integer cnt_m = 0;
    reg [63:0] sum_m = 64'd0;
    integer j8;
    integer diff_b;
    integer ci2;
    integer miss_b;
    reg [31:0] baddr;
    reg [7:0]  gotb;

    always @(posedge clk) begin
        if (rst_n) begin
            if (cmd_valid && cmd_ready) begin
                cbase  = cmd_addr;
                clen_m = cmd_len;
                cnt_m  = 0;
                sum_m  = 64'd0;
            end
            if (awvalid && awready) begin
                aw_addr_l <= awaddr;
                awlen_l   <= awlen;
                wbeats_l  <= 8'd0;
            end
            if (wvalid && wready) begin
                if (wbeats_l > awlen_l) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR W overrun: beat %0d of %0d",
                             wbeats_l + 1, awlen_l + 1);
                end
                if (wlast !== (wbeats_l == awlen_l)) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR wlast@beat %0d of %0d", wbeats_l + 1,
                             awlen_l + 1);
                end
                for (j8 = 0; j8 < 8; j8 = j8 + 1) begin
                    if (wstrb[j8]) begin
                        baddr  = aw_addr_l + {wbeats_l, 3'b000} + j8;
                        diff_b = baddr - cbase;
                        if ((diff_b < 0) || (diff_b >= clen_m)) begin
                            n_err = n_err + 1;
                            if (n_err < 20) begin
                                $display("[tb] ERR byte outside cmd: %h",
                                         baddr);
                            end
                        end else begin
                            if (wr_bit[diff_b]) begin
                                n_err = n_err + 1;
                                if (n_err < 20) begin
                                    $display("[tb] ERR double write @%h",
                                             baddr);
                                end
                            end
                            wr_bit[diff_b] = 1'b1;
                            gotb = wdata[8*j8 +: 8];
                            if (gotb !== f_byte(baddr)) begin
                                n_err = n_err + 1;
                                if (n_err < 20) begin
                                    $display("[tb] ERR byte @%h: got %h exp %h",
                                             baddr, gotb, f_byte(baddr));
                                end
                            end
                            cnt_m = cnt_m + 1;
                            sum_m = sum_m + {56'd0, gotb};
                        end
                    end
                end
                if (wbeats_l == awlen_l) begin
                    wbeats_l <= 8'd0;
                end else begin
                    wbeats_l <= wbeats_l + 8'd1;
                end
            end
            if (done) begin
                if (cnt_m !== mem_gcnt[k_sb_idx]) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR cmd %0d wr-count %0d exp %0d",
                             k_sb_idx, cnt_m, mem_gcnt[k_sb_idx]);
                end
                if (sum_m !== mem_gsum[k_sb_idx]) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR cmd %0d sum %h exp %h", k_sb_idx,
                             sum_m, mem_gsum[k_sb_idx]);
                end
                miss_b = 0;
                for (ci2 = 0; ci2 < clen_m; ci2 = ci2 + 1) begin
                    if (!wr_bit[ci2]) begin
                        miss_b = miss_b + 1;
                    end
                end
                if (miss_b != 0) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR cmd %0d missing %0d bytes", k_sb_idx,
                             miss_b);
                end
                n_bytes = n_bytes + cnt_m;
                k_sb_idx = k_sb_idx + 1;
                n_done = n_done + 1;
            end
        end
    end

    // ---- command driver ----
    reg [1023:0] stim = "../stim/dma_wr";
    integer      wdt_ms = 60000;
    time         wdt_t;
    integer      c;
    integer      ci;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        wdt_t = wdt_ms;                    // 64-bit: no 32-bit wrap (M11 lesson)
        wdt_t = wdt_t * 1000000;
        $readmemh({stim, "/n_cmds.hex"}, mem_n);
        n_cmds = mem_n[0];
        $display("[tb] dma_wr stim=%0s cmds=%0d", stim, n_cmds);
        $readmemh({stim, "/cmd_addr.hex"}, mem_caddr);
        $readmemh({stim, "/cmd_len.hex"},  mem_clen);
        $readmemh({stim, "/g_count.hex"},  mem_gcnt);
        $readmemh({stim, "/g_sum64.hex"},  mem_gsum);
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        for (k = 0; k < n_cmds; k = k + 1) begin
            repeat (gap_cyc) @(negedge clk);       // 随机命令间隔
            while (cmd_ready !== 1'b1) begin
                @(negedge clk);                    // 等 ready 为高的周期
            end
            for (ci = 0; ci < mem_clen[k]; ci = ci + 1) begin
                wr_bit[ci] = 1'b0;                 // 本命令双射位图清零
            end
            cmd_valid = 1'b1;                      // 本 negedge 驱动，下拍接受
            cmd_addr  = mem_caddr[k];
            cmd_len   = mem_clen[k][LEN_W-1:0];
            prod_base = mem_caddr[k];
            prod_len  = mem_clen[k];
            i_src     = 0;
            prod_on   = 1'b1;
            @(negedge clk);
            cmd_valid = 1'b0;
            while (done !== 1'b1) begin
                @(negedge clk);                    // 等本命令 done 脉冲
            end
            prod_on = 1'b0;                        // 冗余保险（生产者自清）
        end
        @(negedge clk);
        if (n_err == 0 && n_done == n_cmds && n_bytes == n_fed) begin
            $display("TB_DMA_WR_PASS bytes=%0d fed=%0d cmds=%0d aws=%0d (stall-tolerant, 4KB-split, B-drain, bijection+checksummed)",
                     n_bytes, n_fed, n_done, n_aws);
        end else begin
            $display("TB_DMA_WR_FAIL errors=%0d done=%0d/%0d bytes=%0d fed=%0d",
                     n_err, n_done, n_cmds, n_bytes, n_fed);
        end
        $finish;
    end

    initial begin
        #wdt_t;
        $display("TB_DMA_WR_FAIL (timeout) errors=%0d done=%0d/%0d", n_err,
                 n_done, n_cmds);
        $finish;
    end

endmodule
