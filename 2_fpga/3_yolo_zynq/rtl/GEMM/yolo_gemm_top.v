/************************************************************************
 * File Name       : yolo_gemm_top.v
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_gemm_top
 * Description     : GEMM engine top level for board integration (B1,
 *                   board plan 1_docs/yolo_gemm_board_test_plan_
 *                   20260919.md section 2).  Wraps yolo_gemm_core V1.1
 *                   (bank V2.0.1 + feeder + array V2.2 + tail V2.2,
 *                   run15/19 gate green, run20 100 MHz WNS=+1.392)
 *                   behind an AXI4-Lite register file so the PS can
 *                   stream-load W/X, set per-row requant parameters,
 *                   load the SiLU LUT, start a job and read results
 *                   back through a coordinate-indexed capture RAM.
 *
 *                   NOTE: this file is plain Verilog-2001 ON PURPOSE
 *                   (user directive): Block Design "Add Module" only
 *                   accepts Verilog top levels.  Same policy as
 *                   yolo_control_subsystem.v V2.1.  The .sv children
 *                   (yolo_gemm_core et al.) are legal to instantiate
 *                   from .v -- proven by the CSR subsystem on this
 *                   exact project (board L4 pass baseline).
 *
 *   Load-port packing convention (copied verbatim from the run15
 *   core TB -- the PS driver must match exactly):
 *     per k index, THREE beats:
 *       W beat : is_x=0 x_hi=0, data[8r+:8]=Wm[r][k] r=0..7,
 *                first=(k==k0), last=0
 *       X lo   : is_x=1 x_hi=0, data[8n+:8]=Xm[n][k]   n=0..7
 *       X hi   : is_x=1 x_hi=1, data[8n+:8]=Xm[n+8][k] n=0..7,
 *                last=(k==k_last);  ld_w_len=ld_x_len=len(k)
 *
 *   Register map (32-bit, word offsets; unmapped -> SLVERR):
 *     0x00 ID      RO  0x20260919
 *     0x04 CTRL    W   {0:start, 1:soft_rst, 2:err_clr}
 *                   start queues a feeder job (held until job_ready --
 *                   multi-block tiles may be queued while busy, run15
 *                   flow); refused with STATUS.start_err only when a
 *                   queued job is still unaccepted (double start).
 *                   A queued first=1 job clears tile_done_st when
 *                   ISSUED to the core, so queueing never disturbs
 *                   the in-flight tile.  YSTAT.y_count is the LATCHED
 *                   count of the last completed tile (captured on the
 *                   tile_done pulse -- the only y-stream-aligned tile
 *                   boundary, since a queued job is accepted as soon
 *                   as the feeder drains its words, before the tail
 *                   y beats of the previous tile).
 *     0x08 STATUS  RO  {0:busy, 1:job_pend, 2:wr_pend, 3:ld_done_st,
 *                       4:blk_done_st, 5:tile_done_st, 6:bank_err,
 *                       7:proto_err, 8:ld_pend_err, 9:start_err}
 *     0x0C GEOM    RW  {12:0 job_len}          (k count of the block)
 *     0x10 ROWVAL  RW  {7:0 row_valid}
 *     0x14 NMASK   RW  {15:0 n_mask}
 *     0x18 JOBCFG  RW  {0 act_en, 1 job_first, 2 job_last,
 *                       3 job_w_grp, 4 job_x_grp}
 *     0x1C LDGRP   RW  {0 ld_w_grp, 1 ld_x_grp}
 *     0x20 P_BIAS  W   bias_eff data (signed 32, held)
 *     0x24 P_M     W   M data (signed 32, held)
 *     0x28 P_SH    W   shift data [5:0] (held)
 *     0x2C PCTL    W   {2:0 p_row, 8 we} strobe: latch held params
 *                       into the array parameter store (idle only)
 *     0x30 WDATA   W   wr_data[31:0] held (low word)
 *     0x34 WDATA2  W   wr_data[63:32] held (high word)
 *     0x38 WCTL    W   {0 is_x, 1 x_hi, 9:2 be, 10 first, 11 last}
 *                       strobe: present one load-port beat; the beat
 *                       is held pending until wr_ready (group safe);
 *                       a WCTL while the slot is occupied is DROPPED
 *                       and flags STATUS.ld_pend_err
 *     0x3C LDSTAT  RO  {1:0 w_ld_ok, 3:2 x_ld_ok, 5:4 w_loaded,
 *                       7:6 x_loaded, 8 ld_done, 9 bank_err}
 *     0x40 LDLEN   RO  {12:0 ld_w_len, 25:13 ld_x_len}
 *     0x44 LUTD    W   {7:0 wd, 15:8 wa} strobe: one LUT entry
 *                       (broadcast to all lanes, idle only)
 *     0x48 YSTAT   RO  {15:0 y_count(last completed tile, latched
 *                       at tile_done), 16 busy, 17 tile_done_st}
 *     0x4C YADDR   W   {6:0 addr} strobe: set capture read address
 *     0x50 YDATA   RO  {7:0} capture readback (1-cycle RAM latency;
 *                       PS read spacing covers it, TB waits 2 cycles)
 *
 *   Capture RAM addressing: addr = y_row*16 + y_col (0..127); every
 *   emitted y writes its own coordinate slot exactly once per tile
 *   (single-pass stream), so masked-out slots keep their previous
 *   content and the PS only reads valid coordinates.  Capture RAM
 *   is a real blk_mem_gen IP gemm_bm_ycap (SDP 8 x 128, read
 *   latency 1) -- user IP mandate, instantiation checked
 *   port-by-port against its .veo.
 *
 *   Reset policy: external aresetn clears everything (config regs
 *   included).  CTRL.soft_rst pulses the core reset for 4 cycles
 *   and clears capture state + sticky status, but KEEPS config
 *   registers, parameter store content and LUT content (PS re-run
 *   convenience).  CTRL.start is refused only while a queued job is
 *   still unaccepted, and flags STATUS.start_err.
 *
 *   Timing: FCLK0 = 50 MHz (IO PLL 1000 /5 /4, board baseline) and
 *   the core closes 100 MHz with WNS = +1.392 -- 2x margin, no
 *   clocking changes to the verified CSR baseline.
 * Dependencies    : yolo_gemm_core.sv, blk_mem_gen IP gemm_bm_ycap
 * Revision History:
 *   - V1.0 (2026-09-19) by LSL : B1 initial release, gate run21.
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_gemm_top (
    input  wire        s_axi_aclk    ,
    input  wire        s_axi_aresetn ,
    // AXI4-Lite slave interface (names fixed by AXI/BD convention)
    input  wire [31:0] s_axi_awaddr  ,
    input  wire [2:0]  s_axi_awprot  ,
    input  wire        s_axi_awvalid ,
    output wire        s_axi_awready ,
    input  wire [31:0] s_axi_wdata   ,
    input  wire [3:0]  s_axi_wstrb   ,
    input  wire        s_axi_wvalid  ,
    output wire        s_axi_wready  ,
    output wire [1:0]  s_axi_bresp   ,
    output wire        s_axi_bvalid  ,
    input  wire        s_axi_bready  ,
    input  wire [31:0] s_axi_araddr  ,
    input  wire [2:0]  s_axi_arprot  ,
    input  wire        s_axi_arvalid ,
    output wire        s_axi_arready ,
    output wire [31:0] s_axi_rdata   ,
    output wire [1:0]  s_axi_rresp   ,
    output wire        s_axi_rvalid  ,
    input  wire        s_axi_rready
);

    // ------------------------------------------------------------ --
    // clock / reset domaining
    // ------------------------------------------------------------ --
    wire        clk  = s_axi_aclk;
    wire        rst  = ~s_axi_aresetn;      //core/阵列侧高有效同步复位

    // ------------------------------------------------------------ --
    // AXI4-Lite write channel (PS 单主、无乱序；AW/W 各自捕获后合并提交)
    // ------------------------------------------------------------ --
    reg         aw_busy, w_busy, b_valid_r;
    reg  [31:0] awaddr_r, wdata_r;
    reg  [1:0]  bresp_r;
    wire        aw_hs = s_axi_awvalid & ~aw_busy;
    wire        w_hs  = s_axi_wvalid  & ~w_busy;
    wire        wr_commit = aw_busy & w_busy;   //本拍执行寄存器写并出 bvalid

    assign s_axi_awready = ~aw_busy;
    assign s_axi_wready  = ~w_busy;
    assign s_axi_bvalid  = b_valid_r;
    assign s_axi_bresp   = bresp_r;

    // ------------------------------------------------------------ --
    // AXI4-Lite read channel
    // ------------------------------------------------------------ --
    reg         r_valid_r;
    reg  [31:0] rdata_r;
    reg  [1:0]  rresp_r;
    reg  [7:0]  araddr_r;
    wire        ar_hs = s_axi_arvalid & ~r_valid_r;
    wire [7:0]  araddr_sel = ar_hs ? s_axi_araddr[7:0] : araddr_r;

    assign s_axi_arready = ~r_valid_r;
    assign s_axi_rvalid  = r_valid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = rresp_r;

    // ------------------------------------------------------------ --
    // 配置寄存器（RW/保持）
    // ------------------------------------------------------------ --
    reg [12:0] geom_job_len_r;
    reg [7:0]  rowval_r;
    reg [15:0] nmask_r;
    reg        jobcfg_act_r, jobcfg_first_r, jobcfg_last_r;
    reg        jobcfg_wgrp_r, jobcfg_xgrp_r;
    reg        ldgrp_w_r, ldgrp_x_r;
    reg signed [31:0] pbias_r, pm_r;
    reg [5:0]  psh_r;
    reg [31:0] wdata_lo_r, wdata_hi_r;

    // ---- 动作/选通与单拍脉冲 ----
    reg        ctrl_start, ctrl_soft, ctrl_errclr;   //写提交拍采样(1 拍)
    reg        pctl_we, lutd_we, yaddr_we;           //写提交拍采样(1 拍)
    reg        wctl_we;                              //写提交拍采样(1 拍)
    reg [2:0]  pctl_row_r;
    reg [7:0]  lut_wa_r, lut_wd_r;
    reg [6:0]  yaddr_r;
    reg        wrp_is_x, wrp_x_hi, wrp_first, wrp_last;
    reg [7:0]  wrp_be_r;

    // ---- 装载 beat 槽（呈现→握手收账）----
    reg        wr_pend;
    wire       wr_ready_i;
    wire       wr_acc = wr_pend & wr_ready_i;

    // ---- 作业递交槽 ----
    reg        job_pend;
    wire       core_job_ready;
    wire       job_acc = job_pend & core_job_ready;
    reg [12:0] job_len_r;
    reg        job_first_r, job_last_r, job_wgrp_r, job_xgrp_r;

    // ---- 软复位计数（core 同步复位打 4 拍脉冲）----
    reg [2:0]  soft_cnt;

    // ---- core 状态/装载回读线（实连线）+ 同步副本拍（先声明后使用）----
    wire        core_busy_w, core_ld_done_w, core_blk_done_w, core_tile_done_w;
    wire        core_bank_err_w, core_proto_err_w;
    wire [1:0]  w_ld_ok_w, x_ld_ok_w, w_loaded_w, x_loaded_w;
    wire [12:0] ld_w_len_w, ld_x_len_w;
    reg  [1:0]  w_ld_ok_r, x_ld_ok_r, w_loaded_r, x_loaded_r;
    reg  [12:0] ld_w_len_r, ld_x_len_r;

    // ---- 粘滞状态 ----
    reg        st_ld_done, st_blk_done, st_tile_done;
    reg        err_ld_pend, err_start;

    // ---- Y 捕获 ----
    // y_count_r = 当前 tile 活计数；y_last_r = tile_done 拍锁存的末 tile
    // 计数（YSTAT 回读值）。core 的 job_ready=feeder 空闲即置位，而单块
    // tile 的全部 y 拍都在末字之后——递交拍清计数会跨 tile 误累计，
    // 故 tile 边界只能取 y 流对齐的 tile_done 脉冲（TAILW 出口=末 y 拍）。
    reg [15:0] y_count_r;
    reg [15:0] y_last_r;
    wire       core_y_valid;
    wire signed [7:0] core_y;
    wire [2:0] core_y_row;
    wire [3:0] core_y_col;
    wire [6:0] cap_wa = {core_y_row, core_y_col};   //row*16+col
    wire [7:0] cap_dout;
    reg        core_busy, core_ld_done, core_blk_done, core_tile_done;
    reg        core_bank_err, core_proto_err;
    wire       core_rst = rst | (soft_cnt != 3'd0);

    // ------------------------------------------------------------ --
    // AXI 写通道时序
    // ------------------------------------------------------------ --
    always @(posedge clk) begin
        if (rst) begin
            aw_busy <= 1'b0; w_busy <= 1'b0; b_valid_r <= 1'b0;
            awaddr_r <= 32'd0; wdata_r <= 32'd0; bresp_r <= 2'd0;
        end else begin
            // 默认：动作选通只在该提交拍为 1
            ctrl_start <= 1'b0; ctrl_soft  <= 1'b0; ctrl_errclr <= 1'b0;
            pctl_we    <= 1'b0; lutd_we    <= 1'b0; yaddr_we    <= 1'b0;
            wctl_we    <= 1'b0;
            if (aw_hs) begin awaddr_r <= s_axi_awaddr; aw_busy <= 1'b1; end
            if (w_hs)  begin wdata_r  <= s_axi_wdata;  w_busy  <= 1'b1; end
            if (wr_commit) begin
                aw_busy <= 1'b0; w_busy <= 1'b0;
                bresp_r <= 2'b00;                 //默认 OKAY，未映射改 SLVERR
                case (awaddr_r[7:0])
                8'h04: begin
                    ctrl_start  <= wdata_r[0];
                    ctrl_soft   <= wdata_r[1];
                    ctrl_errclr <= wdata_r[2];
                end
                8'h0C: geom_job_len_r <= wdata_r[12:0];
                8'h10: rowval_r        <= wdata_r[7:0];
                8'h14: nmask_r         <= wdata_r[15:0];
                8'h18: begin
                    jobcfg_act_r   <= wdata_r[0];
                    jobcfg_first_r <= wdata_r[1];
                    jobcfg_last_r  <= wdata_r[2];
                    jobcfg_wgrp_r  <= wdata_r[3];
                    jobcfg_xgrp_r  <= wdata_r[4];
                end
                8'h1C: begin
                    ldgrp_w_r <= wdata_r[0];
                    ldgrp_x_r <= wdata_r[1];
                end
                8'h20: pbias_r    <= wdata_r;
                8'h24: pm_r       <= wdata_r;
                8'h28: psh_r      <= wdata_r[5:0];
                8'h2C: begin
                    pctl_we   <= 1'b1;
                    pctl_row_r<= wdata_r[2:0];
                end
                8'h30: wdata_lo_r <= wdata_r;
                8'h34: wdata_hi_r <= wdata_r;
                8'h38: begin
                    wctl_we <= 1'b1;
                    wrp_is_x  <= wdata_r[0];
                    wrp_x_hi  <= wdata_r[1];
                    wrp_be_r   <= wdata_r[9:2];
                    wrp_first  <= wdata_r[10];
                    wrp_last   <= wdata_r[11];
                end
                8'h44: begin
                    lutd_we  <= 1'b1;
                    lut_wd_r <= wdata_r[7:0];
                    lut_wa_r <= wdata_r[15:8];
                end
                8'h4C: begin
                    yaddr_we <= 1'b1;
                    yaddr_r  <= wdata_r[6:0];
                end
                // 8'h00 ID / 只读寄存器：写忽略、OKAY
                default: bresp_r <= 2'b10;       //SLVERR
                endcase
                b_valid_r <= 1'b1;
            end else if (b_valid_r & s_axi_bready) begin
                b_valid_r <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------ --
    // AXI 读通道时序 + 读数据复用（组合译码、当拍锁 rdata）
    // ------------------------------------------------------------ --
    always @(posedge clk) begin
        if (rst) begin
            r_valid_r <= 1'b0; rdata_r <= 32'd0; rresp_r <= 2'd0;
            araddr_r  <= 8'd0;
        end else begin
            if (r_valid_r & s_axi_rready) r_valid_r <= 1'b0;
            if (ar_hs) begin
                araddr_r  <= s_axi_araddr[7:0];
                r_valid_r <= 1'b1;
                rresp_r   <= 2'b00;
                case (araddr_sel)
                8'h00: rdata_r <= 32'h2026_0919;
                8'h08: rdata_r <= {22'd0, err_start, err_ld_pend,
                                   core_proto_err, core_bank_err,
                                   st_tile_done, st_blk_done, st_ld_done,
                                   wr_pend, job_pend, core_busy};
                8'h0C: rdata_r <= {19'd0, geom_job_len_r};
                8'h10: rdata_r <= {24'd0, rowval_r};
                8'h14: rdata_r <= {16'd0, nmask_r};
                8'h18: rdata_r <= {27'd0, jobcfg_xgrp_r, jobcfg_wgrp_r,
                                   jobcfg_last_r, jobcfg_first_r,
                                   jobcfg_act_r};
                8'h1C: rdata_r <= {30'd0, ldgrp_x_r, ldgrp_w_r};
                8'h3C: rdata_r <= {22'd0, core_bank_err, core_ld_done,
                                   x_loaded_r, w_loaded_r,
                                   x_ld_ok_r, w_ld_ok_r};
                8'h40: rdata_r <= {6'd0, ld_x_len_r, ld_w_len_r};
                8'h48: rdata_r <= {14'd0, st_tile_done, core_busy, y_last_r};
                8'h50: rdata_r <= {24'd0, cap_dout};
                default: begin rdata_r <= 32'd0; rresp_r <= 2'b10; end
                endcase
            end
        end
    end

    // ------------------------------------------------------------ --
    // 动作执行：beat 槽（err_ld_pend 的置位在粘滞块，避免多驱动）--
    // ------------------------------------------------------------ --
    always @(posedge clk) begin
        if (rst) begin
            wr_pend <= 1'b0;
        end else begin
            if (wctl_we) begin
                if (!(wr_pend && !wr_acc))
                    wr_pend <= 1'b1;    //空槽或本拍正好收账→接续；占用→丢弃
            end else if (wr_acc) begin
                wr_pend <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            job_pend <= 1'b0; job_len_r <= 13'd0;
            job_first_r <= 1'b0; job_last_r <= 1'b0;
            job_wgrp_r <= 1'b0; job_xgrp_r <= 1'b0;
            err_start <= 1'b0;
            st_ld_done <= 1'b0; st_blk_done <= 1'b0; st_tile_done <= 1'b0;
            y_count_r <= 16'd0;
            y_last_r  <= 16'd0;
            soft_cnt <= 3'd0;
            err_ld_pend <= 1'b0;
        end else begin
            // ---- 软复位脉冲与粘滞清除 ----
            if (ctrl_soft) soft_cnt <= 3'd4;
            else if (soft_cnt != 3'd0) soft_cnt <= soft_cnt - 3'd1;
            if (ctrl_soft) begin
                st_ld_done <= 1'b0; st_blk_done <= 1'b0; st_tile_done <= 1'b0;
                y_count_r <= 16'd0;
                y_last_r  <= 16'd0;
                err_ld_pend <= 1'b0; err_start <= 1'b0;
            end
            if (ctrl_errclr) begin
                err_ld_pend <= 1'b0; err_start <= 1'b0;
            end
            // ---- WCTL 占用丢弃置错（beat 槽块只管 wr_pend）----
            if (wctl_we && wr_pend && !wr_acc)
                err_ld_pend <= 1'b1;
            // ---- start：仅当递交槽被占用时拒绝（多块 tile 允许在
            //      busy 中排队——feeder 握手串行化，run15 流程正典）----
            if (ctrl_start) begin
                if (job_pend) begin
                    err_start <= 1'b1;
                end else begin
                    job_pend    <= 1'b1;
                    job_len_r   <= geom_job_len_r;
                    job_first_r <= jobcfg_first_r;
                    job_last_r  <= jobcfg_last_r;
                    job_wgrp_r  <= jobcfg_wgrp_r;
                    job_xgrp_r  <= jobcfg_xgrp_r;
                    //y 计数不在本块处理（见下方 tile_done 锁存/清零）
                end
            end
            // ---- 作业握手收账 ----
            if (job_acc) job_pend <= 1'b0;
            // ---- 事件粘滞 ----
            if (core_ld_done)  st_ld_done  <= 1'b1;
            if (core_blk_done) st_blk_done <= 1'b1;
            if (core_tile_done) st_tile_done <= 1'b1;
            // ---- Y 捕获计数：活计 + tile_done 拍锁存/清零 ----
            if (core_y_valid) y_count_r <= y_count_r + 16'd1;
            if (core_tile_done) begin
                //脉冲与末 y 拍同拍则含末拍，晚一拍则活计已含——两式皆准
                y_last_r  <= core_y_valid ? (y_count_r + 16'd1) : y_count_r;
                y_count_r <= 16'd0;
            end
            // ---- tile 首块在【递交拍】清 tile 粘滞（新 tile 起点标志；
            //      递交早于上一 tile 的 y 窗，其 tile_done 会重新置位）----
            if (job_acc && job_first_r) begin
                st_tile_done <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------ --
    // core 状态同步副本拍（STATUS/LDSTAT 读路径全用寄存器）
    // ------------------------------------------------------------ --
    always @(posedge clk) begin
        if (rst) begin
            core_busy <= 1'b0; core_ld_done <= 1'b0;
            core_blk_done <= 1'b0; core_tile_done <= 1'b0;
            core_bank_err <= 1'b0; core_proto_err <= 1'b0;
            w_ld_ok_r <= 2'd0; x_ld_ok_r <= 2'd0;
            w_loaded_r <= 2'd0; x_loaded_r <= 2'd0;
            ld_w_len_r <= 13'd0; ld_x_len_r <= 13'd0;
        end else begin
            core_busy      <= core_busy_w;
            core_ld_done   <= core_ld_done_w;
            core_blk_done  <= core_blk_done_w;
            core_tile_done <= core_tile_done_w;
            core_bank_err  <= core_bank_err_w;
            core_proto_err <= core_proto_err_w;
            w_ld_ok_r      <= w_ld_ok_w;
            x_ld_ok_r      <= x_ld_ok_w;
            w_loaded_r     <= w_loaded_w;
            x_loaded_r     <= x_loaded_w;
            ld_w_len_r     <= ld_w_len_w;
            ld_x_len_r     <= ld_x_len_w;
        end
    end

    // ------------------------------------------------------------ --
    // 参数 / LUT 单拍选通（写提交拍之后恰一拍电平）
    // ------------------------------------------------------------ --
    wire        p_we_pl  = pctl_we;   //pctl_we 本身即提交次拍起 1 拍有效
    wire        lut_we_pl= lutd_we;

    // ------------------------------------------------------------ --
    // GEMM core 实例（.sv 子模块——CSR 子系统已证 .v 例化 .sv 合法）
    // 端口逐项对 yolo_gemm_core.sv V1.1 端口表核对
    // ------------------------------------------------------------ --
    yolo_gemm_core u_core (
        .clk_i         (clk),
        .rst_i         (core_rst),
        // 64b 流式装载口
        .wr_valid_i    (wr_pend),
        .wr_ready_o    (wr_ready_i),
        .wr_data_i     ({wdata_hi_r, wdata_lo_r}),
        .wr_is_x_i     (wrp_is_x),
        .wr_x_hi_i     (wrp_x_hi),
        .wr_be_i       (wrp_be_r),
        .wr_first_i    (wrp_first),
        .wr_last_i     (wrp_last),
        .ld_w_grp_i    (ldgrp_w_r),
        .ld_x_grp_i    (ldgrp_x_r),
        // 装载状态
        .w_ld_ok_o     (w_ld_ok_w),
        .x_ld_ok_o     (x_ld_ok_w),
        .w_loaded_o    (w_loaded_w),
        .x_loaded_o    (x_loaded_w),
        .ld_w_len_o    (ld_w_len_w),
        .ld_x_len_o    (ld_x_len_w),
        .ld_done_o     (core_ld_done_w),
        .bank_err_o    (core_bank_err_w),
        // feeder 作业口
        .job_valid_i   (job_pend),
        .job_ready_o   (core_job_ready),
        .job_len_i     (job_len_r),
        .job_first_i   (job_first_r),
        .job_last_i    (job_last_r),
        .job_w_grp_i   (job_wgrp_r),
        .job_x_grp_i   (job_xgrp_r),
        // 阵列 tile 常量/参数/LUT
        .row_valid_i   (rowval_r),
        .n_mask_i      (nmask_r),
        .act_en_i      (jobcfg_act_r),
        .p_we_i        (p_we_pl),
        .p_row_i       (pctl_row_r),
        .p_bias_i      (pbias_r),
        .p_m_i         (pm_r),
        .p_sh_i        (psh_r),
        .lut_we_i      (lut_we_pl),
        .lut_wa_i      (lut_wa_r),
        .lut_wd_i      (lut_wd_r),
        // 结果/状态
        .blk_done_o    (core_blk_done_w),
        .tile_done_o   (core_tile_done_w),
        .busy_o        (core_busy_w),
        .proto_err_o   (core_proto_err_w),
        .y_valid_o     (core_y_valid),
        .y_o           (core_y),
        .y_row_o       (core_y_row),
        .y_col_o       (core_y_col)
    );

    // ------------------------------------------------------------ --
    // Y 捕获 RAM：blk_mem_gen IP gemm_bm_ycap（SDP 8 x 128，读延迟 1）
    // 例化逐端口对 rtl/GEMM/ip/gemm_bm_ycap/gemm_bm_ycap.veo 核对：
    //   clka/ena/wea[0:0]/addra[6:0]/dina[7:0]/clkb/enb/addrb[6:0]/doutb[7:0]
    // 写口 = y 流（ena=y_valid 坐标唯一，无同址重写）；读口 = PS 回读窗
    //（enb 常开自由读，addrb 由 YADDR 保持，无同拍同址读写窗——SDP 且
    //  写只在 tile 计算期、读只在 tile_done 后，结构性无冲突）
    // ------------------------------------------------------------ --
    gemm_bm_ycap u_ycap (
        .clka  (clk),
        .ena   (core_y_valid),
        .wea   (1'b1),
        .addra (cap_wa),
        .dina  (core_y),
        .clkb  (clk),
        .enb   (1'b1),
        .addrb (yaddr_r),
        .doutb (cap_dout)
    );

endmodule
