/************************************************************************
 * File Name       : tb_yolo_dma.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_dma
 * Description     : M9 gate testbench for yolo_dma: AXI BFM slave +
 *                   protocol monitors + byte scoreboard.
 *                   BFM (golden): read data = F(word_addr) murmur-style
 *                   64-bit finalize (bit-identical to dma_vecgen.py);
 *                   random arready/rvalid stalls and sink backpressure
 *                   from a seeded xorshift32 (negedge-driven, stable at
 *                   the posedge; all handshakes captured with NBA).
 *                   Monitors: AR (alignment, arlen<=15, arsize, INCR,
 *                   no 4KB crossing, exact address-chain coverage of
 *                   [cmd_addr, cmd_addr+ceil(len/8)*8)), R (rlast
 *                   exactly on the last beat of each burst), sink
 *                   (every delivered byte == F byte, per-command count
 *                   + additive checksum mod 2^64 vs golden files).
 *                   Usage (from sim/msim, -novopt mandatory on 10.1c):
 *                     vsim -c -novopt +STIM=../stim/dma +WDT_MS=60000 \
 *                          -do "run -all; quit -f" work.tb_yolo_dma
 *                   Gate token: TB_DMA_PASS / TB_DMA_FAIL.
 * Dependencies    : rtl/yolo_dma.v, sim/dma_vecgen.py outputs
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M9)
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_dma;

    localparam ADDR_W    = 32;
    localparam LEN_W     = 24;
    localparam MAX_BURST = 16;
    localparam NCMDS_MAX = 1024;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg cmd_valid = 1'b0;
    wire cmd_ready;
    reg [ADDR_W-1:0] cmd_addr = {ADDR_W{1'b0}};
    reg [LEN_W-1:0]  cmd_len = {LEN_W{1'b0}};
    wire done;
    wire [ADDR_W-1:0] araddr;
    wire [7:0]  arlen;
    wire [2:0]  arsize;
    wire [1:0]  arburst;
    wire        arvalid;
    wire        arready;
    wire [63:0] rdata;
    wire        rlast;
    wire        rvalid;
    wire        rready;
    wire        out_valid;
    wire [7:0]  out_data;
    wire        out_ready;

    integer n_cmds = 0;
    reg [31:0] mem_n [0:0];
    reg [ADDR_W-1:0] mem_caddr [0:NCMDS_MAX-1];
    reg [31:0] mem_clen  [0:NCMDS_MAX-1];
    reg [31:0] mem_gcnt  [0:NCMDS_MAX-1];
    reg [63:0] mem_gsum  [0:NCMDS_MAX-1];

    integer k;
    integer n_err = 0;
    integer n_bytes = 0;
    integer n_ars = 0;
    integer n_done = 0;

    yolo_dma #(
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
        .araddr_o(araddr),
        .arlen_o(arlen),
        .arsize_o(arsize),
        .arburst_o(arburst),
        .arvalid_o(arvalid),
        .arready_i(arready),
        .rdata_i(rdata),
        .rlast_i(rlast),
        .rvalid_i(rvalid),
        .rready_o(rready),
        .out_valid_o(out_valid),
        .out_data_o(out_data),
        .out_ready_i(out_ready)
    );

    always #5 clk = ~clk;

    // ---- BFM data function: F(word_addr), bit-identical to dma_vecgen ----
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

    // ---- stall engine (negedge-driven: stable through the posedge) ----
    integer rng = 32'h5A5A0090;
    reg ar_stall = 1'b0;
    reg r_stall = 1'b0;
    reg sink_stall = 1'b0;
    reg [1:0] gap_cyc = 2'd0;

    always @(negedge clk) begin
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        ar_stall   <= ((rng % 100) < 30);
        r_stall    <= ((rng % 100) < 25);
        sink_stall <= ((rng % 100) < 30);
        gap_cyc    <= rng % 4;
    end

    // ---- BFM AXI slave (single outstanding) ----
    reg        pend = 1'b0;
    reg [ADDR_W-1:0] b_addr = {ADDR_W{1'b0}};
    reg [7:0]  b_len = 8'd0;
    reg [7:0]  b_beat = 8'd0;

    assign arready = ~pend && ~ar_stall;
    assign rvalid = pend && ~r_stall;
    assign rlast = (b_beat == b_len);
    assign rdata = f_word(b_addr + {21'd0, b_beat, 3'b000});
    assign out_ready = ~sink_stall;

    always @(posedge clk) begin
        if (rst_n) begin
            if (arvalid && arready) begin
                pend   <= 1'b1;
                b_addr <= araddr;
                b_len  <= arlen;
                b_beat <= 8'd0;
            end else if (pend && rvalid && rready) begin
                if (b_beat == b_len) begin
                    pend <= 1'b0;
                end
                b_beat <= b_beat + 8'd1;
            end
        end else begin
            pend <= 1'b0;
        end
    end

    // ---- AR monitor: protocol + exact address-chain coverage ----
    reg [ADDR_W-1:0] base = {ADDR_W{1'b0}};
    reg [ADDR_W-1:0] exp_next = {ADDR_W{1'b0}};
    reg [31:0] words_left_m = 32'd0;
    reg [31:0] words_total_m = 32'd0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (cmd_valid && cmd_ready) begin
                base          <= cmd_addr;
                exp_next      <= cmd_addr;
                words_total_m <= (cmd_len + 31'd7) >> 3;
                words_left_m  <= (cmd_len + 31'd7) >> 3;
            end
            if (arvalid && arready) begin
                n_ars = n_ars + 1;
                if (araddr[2:0] !== 3'b000) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AR not aligned: %h", araddr);
                end
                if (arlen >= MAX_BURST) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AR len %0d >= max", arlen + 1);
                end
                if (arsize !== 3'd3 || arburst !== 2'd1) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AR size/burst %0d/%0d", arsize,
                             arburst);
                end
                if ({araddr[11:0]} + {{4{1'b0}}, (arlen + 8'd1), 3'b000}
                    > 13'd4096) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AR crosses 4KB: %h len %0d", araddr,
                             arlen + 1);
                end
                if (araddr !== exp_next) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AR chain: got %h exp %h", araddr,
                             exp_next);
                end
                if ({24'd0, (arlen + 8'd1)} > words_left_m) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR AR overfetch: beats %0d left %0d",
                             arlen + 1, words_left_m);
                end
                exp_next     <= exp_next + {{22{1'b0}}, (arlen + 8'd1), 3'b000};
                words_left_m <= words_left_m - (arlen + 8'd1);
            end
        end
    end

    // ---- R monitor: rlast exactly on the final beat per burst ----
    reg [7:0] r_beats = 8'd0;      // beats seen in current burst
    reg [7:0] arlen_l = 8'd0;

    always @(posedge clk) begin
        if (rst_n && rvalid && rready) begin
            if (rlast && r_beats != arlen_l) begin
                n_err = n_err + 1;
                $display("[tb] ERR early rlast: beat %0d of %0d", r_beats + 1,
                         arlen_l + 1);
            end
            if (rlast) begin
                if (r_beats != arlen_l) begin
                    // counted above
                end
                r_beats <= 8'd0;
            end else begin
                r_beats <= r_beats + 8'd1;
            end
        end
        if (rst_n && arvalid && arready) begin
            arlen_l <= arlen;
        end
    end

    // ---- sink scoreboard: byte-exact + per-command count/checksum ----
    integer i_byte = 0;
    reg [63:0] sum_acc = 64'd0;
    integer k_sb = 0;
    reg [63:0] expb = 64'd0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (cmd_valid && cmd_ready) begin
                i_byte  = 0;
                sum_acc = 64'd0;
            end
            if (out_valid && out_ready) begin
                expb = (f_word(base + {25'd0, i_byte[31:3], 3'b000})
                        >> (8 * i_byte[2:0])) & 64'h00000000000000FF;
                if (out_data !== expb[7:0]) begin
                    n_err = n_err + 1;
                    if (n_err < 20) begin
                        $display("[tb] ERR byte @cmd%0d idx %0d: got %h exp %h",
                                 k_sb, i_byte, out_data, expb[7:0]);
                    end
                end
                sum_acc = sum_acc + {56'd0, out_data};
                i_byte  = i_byte + 1;
                n_bytes = n_bytes + 1;
            end
            if (done) begin
                if (i_byte !== mem_gcnt[k_sb]) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR cmd %0d count %0d exp %0d", k_sb,
                             i_byte, mem_gcnt[k_sb]);
                end
                if (sum_acc !== mem_gsum[k_sb]) begin
                    n_err = n_err + 1;
                    $display("[tb] ERR cmd %0d sum %h exp %h", k_sb, sum_acc,
                             mem_gsum[k_sb]);
                end
                k_sb   = k_sb + 1;
                n_done = n_done + 1;
            end
        end
    end

    // ---- command driver ----
    reg [1023:0] stim = "../stim/dma";
    integer      wdt_ms = 60000;
    integer      c;

    initial begin
        if ($value$plusargs("STIM=%s", stim)) begin
            // plusarg present, stim updated
        end
        if ($value$plusargs("WDT_MS=%d", wdt_ms)) begin
            // plusarg present, wdt updated
        end
        $readmemh({stim, "/n_cmds.hex"}, mem_n);
        n_cmds = mem_n[0];
        $display("[tb] dma stim=%0s cmds=%0d", stim, n_cmds);
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
            cmd_valid = 1'b1;                      // 本 negedge 驱动，下拍接受
            cmd_addr  = mem_caddr[k];
            cmd_len   = mem_clen[k][LEN_W-1:0];
            @(negedge clk);
            cmd_valid = 1'b0;
            while (done !== 1'b1) begin
                @(negedge clk);                    // 等本命令 done 脉冲
            end
        end
        @(negedge clk);
        if (n_err == 0 && n_done == n_cmds) begin
            $display("TB_DMA_PASS bytes=%0d cmds=%0d ars=%0d (stall-tolerant, 4KB-split, checksummed)",
                     n_bytes, n_done, n_ars);
        end else begin
            $display("TB_DMA_FAIL errors=%0d done=%0d/%0d", n_err, n_done,
                     n_cmds);
        end
        $finish;
    end

    initial begin
        #(wdt_ms * 1_000_000);
        $display("TB_DMA_FAIL (timeout) errors=%0d done=%0d/%0d", n_err,
                 n_done, n_cmds);
        $finish;
    end

endmodule
