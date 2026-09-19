/************************************************************************
 * File Name       : yolo_control_subsystem.v
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_control_subsystem
 * Description     : Top level of the YOLO PL control subsystem
 *                   (design doc 1_docs/yolo_axi_lite_csr_design_20260918).
 *                   AXI4-Lite slave at 0x43C1_0000, 64 KB space:
 *                     0x0000-0x02FF fixed registers (FF)
 *                     0x1000-0x2FFF descriptor window (BMG BRAM,
 *                                  windowed via DESC_BASE, table 16 KB)
 *                     0x3000-0x3FFF buffer table window (BMG BRAM)
 *                     0x4000-0x4FFF quant table window  (BMG BRAM)
 *                     0x5000-0x5FFF SiLU LUT window     (BMG BRAM)
 *                     0x6000-0x67FF result ring window  (BMG BRAM, RO)
 *                     0x7000-0x7FFF debug window (reads 0, writes OK)
 *                     everything else -> SLVERR
 *                   All tables are real Xilinx IP instances (Block
 *                   Memory Generator, output registers disabled ->
 *                   uniform 1-cycle read latency, TABLE_RD_LATENCY).
 *                   Write protection: tables are writable only while
 *                   the walker is idle (design doc section 5
 *                   shadow/commit realised as idle-window reload).
 *                   NOTE: this file is plain Verilog-2001 on purpose:
 *                   Block Design "Add Module" only accepts Verilog
 *                   top levels.  Constants mirrored from
 *                   yolo_csr_pkg.sv are marked "keep in sync"; the
 *                   sub-modules remain SystemVerilog and read them
 *                   from the package.
 * Dependencies    : yolo_axi_lite_slave.sv, yolo_reg_file.sv,
 *                   yolo_desc_walker.sv, yolo_result_ring.sv,
 *                   yolo_{desc,buf,quant,lut,ring}_table.sv (BMG IP
 *                   wrappers)
 * Revision History:
 *   - V2.1 (2026-09-18) by LSL : Converted to plain Verilog-2001 so
 *                                the module can be added to a Block
 *                                Design (user directive); package
 *                                constants inlined locally.
 *   - V2.0 (2026-09-18) by LSL : Coding-standards refactor; SOFT_RESET
 *                                now resets the register file.
 *   - V1.1 (2026-09-18) by LSL : Forward declarations, region decode.
 *   - V1.0 (2026-09-18) by LSL : Initial release
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_control_subsystem (
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
    input  wire        s_axi_rready  ,
    // interrupt (level: armed and (frame done or error))
    output wire        irq_o
);

    // ------------------------------------------------------------ --
    // constants mirrored from yolo_csr_pkg.sv -- keep in sync
    // ------------------------------------------------------------ --
    localparam integer TABLE_RD_LATENCY   = 1;

    localparam [7:0]   E_CODE_DESC_INVALID = 8'h01;
    localparam [7:0]   E_CODE_RING_OVF     = 8'h10;
    localparam [7:0]   E_CODE_RING_RO      = 8'h11;
    localparam [7:0]   E_CODE_TABLE_RUN    = 8'h12;
    localparam [7:0]   E_CODE_ADDR_ALIGN   = 8'h13;
    localparam [7:0]   E_CODE_ADDR_REGION  = 8'h14;
    localparam [7:0]   E_CODE_ACK_EMPTY    = 8'h15;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // region codes
    localparam [3:0] RGN_REGF  = 4'd0,
                     RGN_DESC  = 4'd1,
                     RGN_BUF   = 4'd2,
                     RGN_QUANT = 4'd3,
                     RGN_LUT   = 4'd4,
                     RGN_RING  = 4'd5,
                     RGN_DEBUG = 4'd6,
                     RGN_BAD   = 4'd7;

    // ------------------------------------------------------------ --
    // address region decode
    // ------------------------------------------------------------ --
    function [3:0] f_region(input [15:0] a);
        begin
            if      (a < 16'h0300)                    f_region = RGN_REGF;
            else if (a >= 16'h1000 && a < 16'h3000)   f_region = RGN_DESC;
            else if (a >= 16'h3000 && a < 16'h4000)   f_region = RGN_BUF;
            else if (a >= 16'h4000 && a < 16'h5000)   f_region = RGN_QUANT;
            else if (a >= 16'h5000 && a < 16'h6000)   f_region = RGN_LUT;
            else if (a >= 16'h6000 && a < 16'h6800)   f_region = RGN_RING;
            else if (a >= 16'h7000 && a < 16'h8000)   f_region = RGN_DEBUG;
            else                                      f_region = RGN_BAD;
        end
    endfunction

    // ------------------------------------------------------------ --
    // forward declarations
    // ------------------------------------------------------------ --
    // slave internal buses
    wire        wr_valid_w;
    wire        rd_valid_w;
    wire [15:0] wr_addr_w;
    wire [15:0] rd_addr_w;
    wire [31:0] wr_data_w;
    wire [3:0]  wr_strb_w;
    wire [1:0]  wr_rsp_w;
    wire [1:0]  rd_rsp_w;
    wire        rd_ack_w;
    wire [31:0] rd_data_w;
    wire        err_align_evt;
    // regfile <-> others
    wire        ctrl_enable;
    wire        ctrl_start;
    wire        ctrl_stop;
    wire        ctrl_abort;
    wire        ctrl_clr;
    wire        ctrl_flush;
    wire        ctrl_sreset;
    wire        ctrl_arm_irq;
    wire        dbell_commit;
    wire        frame_end_clear;
    wire        frame_end_pending_w;
    wire [15:0] desc_tail_w;
    wire [15:0] desc_count_w;
    wire [15:0] walker_head_w;
    wire [15:0] walker_cur_w;
    wire [15:0] walker_done_w;
    wire [15:0] walker_err_id_w;
    wire [7:0]  desc_depth_w;
    wire [7:0]  walker_opcode_w;
    wire        desc_circular_w;
    wire [11:0] desc_win_base_w;
    wire [7:0]  ring_head_ptr_w;
    wire [7:0]  ring_tail_ptr_w;
    wire        ring_not_empty_w;
    wire        ring_ack_consume_w;
    wire        ring_ack_drop_w;
    wire        ring_ack_retry_w;
    wire [31:0] ring_seq_w;
    wire [31:0] ring_frame_id_w;
    wire [31:0] ring_head_bytes_w;
    wire        ring_publish_evt_w;
    wire        ring_overflow_evt_w;
    wire        ring_ack_err_evt;
    wire [31:0] regf_rd_data_w;
    wire [9:0]  err_events_w;
    reg  [7:0]  err_code_w;
    reg  [7:0]  err_op_w;
    reg  [7:0]  err_desc_id_w;
    reg  [7:0]  err_port_w;
    wire [31:0] frame_id_w;
    wire [31:0] head_base_lo_w;
    wire [31:0] head_base_hi_w;
    wire [31:0] head_fmt_w;
    // walker
    wire        walker_idle_w;
    wire        walker_busy;
    wire        walker_frame_done_w;
    wire        walker_err_evt;
    wire [7:0]  walker_err_op_w;
    wire [7:0]  walker_err_desc_w;
    wire        pub_valid_w;
    wire        pub_ready_w;
    wire [31:0] pub_bytes_w;
    wire [11:0] walker_desc_addr_w;
    wire [31:0] walker_desc_data_w;
    // tables
    wire        wr_desc;
    wire        wr_buf;
    wire        wr_quant;
    wire        wr_lut;
    wire [31:0] desc_rd_data_w;
    wire [31:0] buf_rd_data_w;
    wire [31:0] quant_rd_data_w;
    wire [31:0] lut_rd_data_w;
    wire [31:0] ring_rd_data_w;

    // ------------------------------------------------------------ --
    // AXI4-Lite slave instance
    // ------------------------------------------------------------ --
    yolo_axi_lite_slave u_slave (
        .clk_i           (s_axi_aclk),
        .rst_n           (s_axi_aresetn),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        .wr_valid_o      (wr_valid_w),
        .wr_addr_o       (wr_addr_w),
        .wr_data_o       (wr_data_w),
        .wr_strb_o       (wr_strb_w),
        .wr_rsp_i        (wr_rsp_w),
        .rd_valid_o      (rd_valid_w),
        .rd_addr_o       (rd_addr_w),
        .rd_ack_i        (rd_ack_w),
        .rd_data_i       (rd_data_w),
        .rd_rsp_i        (rd_rsp_w),
        .err_axi_event_o (err_align_evt)
    );

    // ------------------------------------------------------------ --
    // write decode (sources are registered in the slave)
    // ------------------------------------------------------------ --
    wire [3:0]  wr_region  = f_region(wr_addr_w);
    wire [3:0]  rd_region  = f_region(rd_addr_w);
    wire        wr_aligned = (wr_addr_w[1:0] == 2'b00);
    wire        rd_aligned = (rd_addr_w[1:0] == 2'b00);

    // table lock: tables are writable only while the walker is idle
    wire tbl_locked  = walker_busy;
    wire wr_is_table = (wr_region == RGN_DESC) || (wr_region == RGN_BUF) ||
                       (wr_region == RGN_QUANT) || (wr_region == RGN_LUT);

    wire wr_illegal = !wr_aligned ||
                      (wr_region == RGN_BAD) ||
                      (wr_region == RGN_RING) ||        // ring is read-only
                      (wr_is_table && tbl_locked);      // reload in idle only
    assign wr_rsp_w = wr_illegal ? RESP_SLVERR : RESP_OKAY;

    // per-target write strobes (single beat, sources registered)
    wire wr_fire = wr_valid_w;                           // wr_ready is 1
    wire wr_regf = wr_fire && wr_aligned && (wr_region == RGN_REGF);
    assign wr_desc  = wr_fire && wr_aligned && (wr_region == RGN_DESC)  && !tbl_locked;
    assign wr_buf   = wr_fire && wr_aligned && (wr_region == RGN_BUF)   && !tbl_locked;
    assign wr_quant = wr_fire && wr_aligned && (wr_region == RGN_QUANT) && !tbl_locked;
    assign wr_lut   = wr_fire && wr_aligned && (wr_region == RGN_LUT)   && !tbl_locked;

    // write-path error events
    wire evt_region_bad  = wr_fire && (wr_region == RGN_BAD);
    wire evt_ring_ro     = wr_fire && wr_aligned && (wr_region == RGN_RING);
    wire evt_desc_guard  = wr_fire && wr_aligned && (wr_region == RGN_DESC)  && tbl_locked;
    wire evt_buf_guard   = wr_fire && wr_aligned && (wr_region == RGN_BUF)   && tbl_locked;
    wire evt_quant_guard = wr_fire && wr_aligned && (wr_region == RGN_QUANT) && tbl_locked;
    wire evt_lut_guard   = wr_fire && wr_aligned && (wr_region == RGN_LUT)   && tbl_locked;

    // ------------------------------------------------------------ --
    // read address mapping
    //
    // NOTE on window arithmetic: the descriptor aperture is 8 KB at
    // 0x1000 and its base has bit 12 set, so the window-relative word
    // offset must be formed by an explicit subtraction -- slicing the
    // raw address with [12:2] would leak the aperture base into the
    // offset (0x1000 -> offset 1024 instead of 0).  The 4 KB windows
    // below have all-zero low 12 base bits, so [11:2]/[10:2] are
    // already window-relative.
    //
    // NOTE on true dual port RAM: every table is one physical BRAM;
    // simultaneous same-address access from both ports is a collision
    // (undefined read on hardware, not modelled by the behavioral
    // sim).  Collisions are excluded structurally, not by timing:
    //   desc  - PS writes blocked while tbl_locked (walker outside
    //           W_IDLE), walker only reads via port B
    //   ring  - publisher writes only at head, PS reads only owned
    //           entries [tail, head), full ring drops instead of
    //           overwriting
    //   buf/quant/lut - port B idle (future compute path)
    // ------------------------------------------------------------ --
    wire [13:0] desc_wr_off = wr_addr_w[13:0] - 14'h1000;
    wire [13:0] desc_rd_off = rd_addr_w[13:0] - 14'h1000;
    wire [11:0] desc_wr_word = desc_win_base_w + {1'b0, desc_wr_off[12:2]};
    wire [11:0] desc_rd_word = desc_win_base_w + {1'b0, desc_rd_off[12:2]};
    wire [9:0]  buf_word     = rd_addr_w[11:2];
    wire [9:0]  quant_word   = rd_addr_w[11:2];
    wire [9:0]  lut_word     = rd_addr_w[11:2];
    wire [8:0]  ring_word    = rd_addr_w[10:2];

    wire rd_illegal = (rd_region == RGN_BAD);
    assign rd_rsp_w = (!rd_aligned || rd_illegal) ? RESP_SLVERR : RESP_OKAY;

    // ------------------------------------------------------------ --
    // register file
    // ------------------------------------------------------------ --
    yolo_reg_file u_regf (
        .clk_i               (s_axi_aclk),
        .rst_n               (s_axi_aresetn),
        .soft_reset_i        (ctrl_sreset),
        .csr_wr_valid_i      (wr_regf),
        .csr_wr_addr_i       (wr_addr_w),
        .csr_wr_data_i       (wr_data_w),
        .csr_rd_addr_i       (rd_addr_w),
        .csr_rd_data_o       (regf_rd_data_w),
        .walker_idle_i       (walker_idle_w),
        .walker_running_i    (walker_busy),
        .walker_frame_done_i (walker_frame_done_w),
        .walker_cur_opcode_i (walker_opcode_w),
        .walker_head_i       (walker_head_w),
        .walker_current_i    (walker_cur_w),
        .walker_done_i       (walker_done_w),
        .walker_error_id_i   (walker_err_id_w),
        .ctrl_enable_o       (ctrl_enable),
        .ctrl_start_frame_o  (ctrl_start),
        .ctrl_stop_o         (ctrl_stop),
        .ctrl_abort_o        (ctrl_abort),
        .ctrl_clr_status_o   (ctrl_clr),
        .ctrl_flush_cache_o  (ctrl_flush),
        .ctrl_soft_reset_o   (ctrl_sreset),
        .ctrl_arm_irq_o      (ctrl_arm_irq),
        .desc_count_o        (desc_count_w),
        .desc_tail_o         (desc_tail_w),
        .doorbell_commit_o   (dbell_commit),
        .frame_end_pending_o (frame_end_pending_w),
        .frame_end_clear_i   (frame_end_clear),
        .desc_depth_o        (desc_depth_w),
        .desc_circular_o     (desc_circular_w),
        .desc_win_base_o     (desc_win_base_w),
        .sched_cfg_o         (),
        .ring_head_ptr_i     (ring_head_ptr_w),
        .ring_not_empty_i    (ring_not_empty_w),
        .ring_seq_i          (ring_seq_w),
        .ring_frame_id_i     (ring_frame_id_w),
        .ring_head_bytes_i   (ring_head_bytes_w),
        .ring_publish_evt_i  (ring_publish_evt_w),
        .ring_overflow_evt_i (ring_overflow_evt_w),
        .ring_tail_ptr_o     (ring_tail_ptr_w),
        .ring_ack_consume_o  (ring_ack_consume_w),
        .ring_ack_drop_o     (ring_ack_drop_w),
        .ring_ack_retry_o    (ring_ack_retry_w),
        .frame_id_reg_o      (frame_id_w),
        .frame_cfg_o         (),
        .input_base_lo_o     (),
        .input_base_hi_o     (),
        .input_stride_o      (),
        .head_base_lo_o      (head_base_lo_w),
        .head_base_hi_o      (head_base_hi_w),
        .head_stride_o       (),
        .head_format_o       (head_fmt_w),
        .result_max_det_o    (),
        .result_conf_q_o     (),
        .model_id_o          (),
        .graph_crc_o         (),
        .err_events_i        (err_events_w),
        .err_code_i          (err_code_w),
        .err_op_i            (err_op_w),
        .err_desc_id_i       (err_desc_id_w),
        .err_port_i          (err_port_w),
        .error_status_o      (),
        .dma_cfg_o           (),
        .perf_cycles_o       (),
        .irq_o               (irq_o)
    );

    // ------------------------------------------------------------ --
    // error event aggregation (sticky bits + info priority mux)
    // ------------------------------------------------------------ --
    assign err_events_w[0] = err_align_evt || evt_region_bad;
    assign err_events_w[1] = 1'b0;
    assign err_events_w[2] = 1'b0;
    assign err_events_w[3] = walker_err_evt || evt_desc_guard;
    assign err_events_w[4] = evt_buf_guard;
    assign err_events_w[5] = evt_quant_guard;
    assign err_events_w[6] = evt_lut_guard;
    assign err_events_w[7] = 1'b0;
    assign err_events_w[8] = ring_overflow_evt_w;
    assign err_events_w[9] = evt_ring_ro || ring_ack_err_evt;

    always @(*) begin
        if (walker_err_evt) begin
            err_code_w    = E_CODE_DESC_INVALID;
            err_op_w      = walker_err_op_w;
            err_desc_id_w = walker_err_desc_w;
            err_port_w    = 4'd1;
        end else if (evt_lut_guard) begin
            err_code_w    = E_CODE_TABLE_RUN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd4;
        end else if (evt_quant_guard) begin
            err_code_w    = E_CODE_TABLE_RUN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd3;
        end else if (evt_buf_guard) begin
            err_code_w    = E_CODE_TABLE_RUN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd2;
        end else if (evt_desc_guard) begin
            err_code_w    = E_CODE_TABLE_RUN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd1;
        end else if (ring_overflow_evt_w) begin
            err_code_w    = E_CODE_RING_OVF;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd6;
        end else if (evt_ring_ro) begin
            err_code_w    = E_CODE_RING_RO;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd6;
        end else if (ring_ack_err_evt) begin
            err_code_w    = E_CODE_ACK_EMPTY;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd6;
        end else if (evt_region_bad) begin
            err_code_w    = E_CODE_ADDR_REGION;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd15;
        end else if (err_align_evt) begin
            err_code_w    = E_CODE_ADDR_ALIGN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd15;
        end else begin
            err_code_w    = 8'h0;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 8'h0;
        end
    end

    // ------------------------------------------------------------ --
    // tables (real Block Memory Generator IP instances)
    // ------------------------------------------------------------ --
    yolo_desc_table u_desc_tbl (
        .clk_i     (s_axi_aclk),
        .a_we_i    (wr_desc),
        .a_wstrb_i (wr_strb_w),
        .a_waddr_i (desc_wr_word),
        .a_wdata_i (wr_data_w),
        .a_raddr_i (desc_rd_word),
        .a_rdata_o (desc_rd_data_w),
        .b_raddr_i (walker_desc_addr_w),
        .b_rdata_o (walker_desc_data_w)
    );

    yolo_buf_table u_buf_tbl (
        .clk_i     (s_axi_aclk),
        .a_we_i    (wr_buf),
        .a_wstrb_i (wr_strb_w),
        .a_waddr_i (wr_addr_w[11:2]),
        .a_wdata_i (wr_data_w),
        .a_raddr_i (buf_word),
        .a_rdata_o (buf_rd_data_w)
    );

    yolo_quant_table u_quant_tbl (
        .clk_i     (s_axi_aclk),
        .a_we_i    (wr_quant),
        .a_wstrb_i (wr_strb_w),
        .a_waddr_i (wr_addr_w[11:2]),
        .a_wdata_i (wr_data_w),
        .a_raddr_i (quant_word),
        .a_rdata_o (quant_rd_data_w)
    );

    yolo_lut_table u_lut_tbl (
        .clk_i     (s_axi_aclk),
        .a_we_i    (wr_lut),
        .a_wstrb_i (wr_strb_w),
        .a_waddr_i (wr_addr_w[11:2]),
        .a_wdata_i (wr_data_w),
        .a_raddr_i (lut_word),
        .a_rdata_o (lut_rd_data_w),
        .b_raddr_i (10'h0),
        .b_rdata_o ()
    );

    // ------------------------------------------------------------ --
    // descriptor walker
    // ------------------------------------------------------------ --
    yolo_desc_walker u_walker (
        .clk_i               (s_axi_aclk),
        .rst_n               (s_axi_aresetn),
        .soft_reset_i        (ctrl_sreset),
        .enable_i            (ctrl_enable),
        .start_frame_i       (ctrl_start),
        .stop_i              (ctrl_stop),
        .abort_i             (ctrl_abort),
        .doorbell_commit_i   (dbell_commit),
        .frame_end_pending_i (frame_end_pending_w),
        .frame_end_clear_o   (frame_end_clear),
        .desc_tail_i         (desc_tail_w),
        .desc_count_i        (desc_count_w),
        .desc_depth_i        (desc_depth_w),
        .desc_circular_i     (desc_circular_w),
        .walker_head_o       (walker_head_w),
        .walker_current_o    (walker_cur_w),
        .walker_done_o       (walker_done_w),
        .walker_error_id_o   (walker_err_id_w),
        .cur_opcode_o        (walker_opcode_w),
        .walker_idle_o       (walker_idle_w),
        .walker_running_o    (walker_busy),
        .walker_frame_done_o (walker_frame_done_w),
        .desc_rd_addr_o      (walker_desc_addr_w),
        .desc_rd_data_i      (walker_desc_data_w),
        .pub_valid_o         (pub_valid_w),
        .pub_ready_i         (pub_ready_w),
        .pub_bytes_o         (pub_bytes_w),
        .err_evt_desc_o      (walker_err_evt),
        .err_op_o            (walker_err_op_w),
        .err_desc_id_o       (walker_err_desc_w)
    );

    // ------------------------------------------------------------ --
    // result ring
    // ------------------------------------------------------------ --
    yolo_result_ring u_ring (
        .clk_i               (s_axi_aclk),
        .rst_n               (s_axi_aresetn),
        .soft_reset_i        (ctrl_sreset),
        .pub_valid_i         (pub_valid_w),
        .pub_ready_o         (pub_ready_w),
        .pub_frame_id_i      (frame_id_w),
        .pub_head_base_i     ({head_base_hi_w, head_base_lo_w}),
        .pub_head_bytes_i    (pub_bytes_w),
        .pub_quant_profile_i (head_fmt_w[15:8]),
        .pub_stride_mask_i   (head_fmt_w[23:16]),
        .pub_done_evt_o      (ring_publish_evt_w),
        .pub_overflow_evt_o  (ring_overflow_evt_w),
        .tail_ptr_i          (ring_tail_ptr_w),
        .ack_consume_i       (ring_ack_consume_w),
        .ack_drop_i          (ring_ack_drop_w),
        .ack_err_evt_o       (ring_ack_err_evt),
        .head_ptr_o          (ring_head_ptr_w),
        .not_empty_o         (ring_not_empty_w),
        .seq_o               (ring_seq_w),
        .last_frame_id_o     (ring_frame_id_w),
        .last_head_bytes_o   (ring_head_bytes_w),
        .win_addr_i          (ring_word),
        .win_data_o          (ring_rd_data_w)
    );

    // ------------------------------------------------------------ --
    // read data mux + read ack alignment (TABLE_RD_LATENCY cycles)
    // ------------------------------------------------------------ --
    reg [31:0] rd_mux_q;
    always @(*) begin
        case (rd_region)
            RGN_REGF  : rd_mux_q = regf_rd_data_w;
            RGN_DESC  : rd_mux_q = desc_rd_data_w;
            RGN_BUF   : rd_mux_q = buf_rd_data_w;
            RGN_QUANT : rd_mux_q = quant_rd_data_w;
            RGN_LUT   : rd_mux_q = lut_rd_data_w;
            RGN_RING  : rd_mux_q = ring_rd_data_w;
            default   : rd_mux_q = 32'h0;   // DEBUG and unmapped
        endcase
    end
    assign rd_data_w = rd_mux_q;

    reg [TABLE_RD_LATENCY:1] rd_ack_pipe;
    integer j;
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            rd_ack_pipe <= {TABLE_RD_LATENCY{1'b0}};
        end else begin
            rd_ack_pipe[1] <= rd_valid_w;
            for (j = 2; j <= TABLE_RD_LATENCY; j = j + 1)
                rd_ack_pipe[j] <= rd_ack_pipe[j-1];
        end
    end
    assign rd_ack_w = rd_ack_pipe[TABLE_RD_LATENCY];

endmodule
