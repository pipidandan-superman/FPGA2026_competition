/************************************************************************
 * File Name       : tb_yolo_control_subsystem.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_yolo_control_subsystem
 * Description     : Contract testbench for the YOLO CSR subsystem
 *                   (design doc yolo_axi_lite_csr_design_20260918).
 *                   Covers: identity/capability reads, RW readback,
 *                   AW-first / W-first / same-beat writes, W1C
 *                   semantics, table window write/read and DESC_BASE
 *                   window move, doorbell end-to-end frame flow with
 *                   ring window verification and RESULT_ACK consume,
 *                   running-write protection (LUT), ring overflow,
 *                   ack-on-empty protocol error, misaligned /
 *                   unmapped / read-only-window SLVERR paths.
 *                   Emits EES_VIVADO_STAGE / EES_VIVADO_RESULT markers
 *                   for the batch simulation launcher; no waveform
 *                   logging; watchdog protected; X/Z rejected.
 * Dependencies    : yolo_csr_pkg.sv, yolo_control_subsystem.sv
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release
 ************************************************************************/
`timescale 1ns / 1ps

module tb_yolo_control_subsystem;

    import yolo_csr_pkg::*;

    // ------------------------------------------------------------ --
    // clock / reset
    // ------------------------------------------------------------ --
    reg         aclk;
    reg         aresetn;

    localparam integer CLK_PERIOD = 10;   // 100 MHz

    // ------------------------------------------------------------ --
    // AXI4-Lite master side (drives DUT slave)
    // ------------------------------------------------------------ --
    reg  [31:0] s_axi_awaddr;
    reg  [2:0]  s_axi_awprot;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [31:0] s_axi_araddr;
    reg  [2:0]  s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    wire        irq;

    // ------------------------------------------------------------ --
    // bookkeeping
    // ------------------------------------------------------------ --
    integer error_count;
    integer check_count;
    reg  [1:0]  last_bresp;
    reg  [1:0]  last_rresp;
    reg  [31:0] rd_q;

    // ------------------------------------------------------------ --
    // DUT
    // ------------------------------------------------------------ --
    yolo_control_subsystem dut (
        .s_axi_aclk    (aclk),
        .s_axi_aresetn (aresetn),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awprot  (s_axi_awprot),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arprot  (s_axi_arprot),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .irq_o         (irq)
    );

    // ------------------------------------------------------------ --
    // clock generation
    // ------------------------------------------------------------ --
    initial aclk = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // ------------------------------------------------------------ --
    // watchdog: fail the run if the sequence stalls
    // ------------------------------------------------------------ --
    initial begin
        #5_000_000;   // 5 ms
        $display("EES_VIVADO_STAGE WATCHDOG_TIMEOUT");
        $display("EES_VIVADO_RESULT FAIL");
        $fatal(1, "watchdog timeout");
    end

    // ------------------------------------------------------------ --
    // check helpers
    // ------------------------------------------------------------ --
    task automatic check32(input string name,
                           input [31:0] got,
                           input [31:0] exp);
        begin
            check_count = check_count + 1;
            if ((^got) === 1'bx) begin
                $display("EES_CHECK FAIL %s : X/Z value", name);
                error_count = error_count + 1;
            end else if (got !== exp) begin
                $display("EES_CHECK FAIL %s : got %08h exp %08h",
                         name, got, exp);
                error_count = error_count + 1;
            end else begin
                $display("EES_CHECK PASS %s = %08h", name, got);
            end
        end
    endtask

    task automatic check_slv(input string name, input [1:0] resp);
        begin
            check_count = check_count + 1;
            if (resp === 2'b10) begin
                $display("EES_CHECK PASS %s : SLVERR as expected", name);
            end else begin
                $display("EES_CHECK FAIL %s : resp %b exp SLVERR",
                         name, resp);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic check_okay(input string name, input [1:0] resp);
        begin
            check_count = check_count + 1;
            if (resp === 2'b00) begin
                $display("EES_CHECK PASS %s : OKAY as expected", name);
            end else begin
                $display("EES_CHECK FAIL %s : resp %b exp OKAY",
                         name, resp);
                error_count = error_count + 1;
            end
        end
    endtask

    // ------------------------------------------------------------ --
    // AXI4-Lite driver tasks
    // ------------------------------------------------------------ --
    task automatic axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awprot  <= 3'h0;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;
            // one edge so the NBAs above are visible before polling
            @(posedge aclk);
            while (s_axi_awvalid || s_axi_wvalid) begin
                if (s_axi_awready) s_axi_awvalid <= 1'b0;
                if (s_axi_wready)  s_axi_wvalid  <= 1'b0;
                @(posedge aclk);
            end
            while (!s_axi_bvalid) @(posedge aclk);
            last_bresp = s_axi_bresp;
        end
    endtask

    // AW issued some beats before W (write ordering tolerance)
    task automatic axi_write_aw_first(input [31:0] addr,
                                      input [31:0] data,
                                      input integer gap);
        integer n;
        begin
            @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awprot  <= 3'h0;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            while (s_axi_awvalid) begin
                if (s_axi_awready) s_axi_awvalid <= 1'b0;
                @(posedge aclk);
            end
            for (n = 0; n < gap; n = n + 1) @(posedge aclk);
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;
            @(posedge aclk);
            while (s_axi_wvalid) begin
                if (s_axi_wready) s_axi_wvalid <= 1'b0;
                @(posedge aclk);
            end
            while (!s_axi_bvalid) @(posedge aclk);
            last_bresp = s_axi_bresp;
        end
    endtask

    // W issued some beats before AW
    task automatic axi_write_w_first(input [31:0] addr,
                                     input [31:0] data,
                                     input integer gap);
        integer n;
        begin
            @(posedge aclk);
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;
            @(posedge aclk);
            while (s_axi_wvalid) begin
                if (s_axi_wready) s_axi_wvalid <= 1'b0;
                @(posedge aclk);
            end
            for (n = 0; n < gap; n = n + 1) @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awprot  <= 3'h0;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            while (s_axi_awvalid) begin
                if (s_axi_awready) s_axi_awvalid <= 1'b0;
                @(posedge aclk);
            end
            while (!s_axi_bvalid) @(posedge aclk);
            last_bresp = s_axi_bresp;
        end
    endtask

    task automatic axi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge aclk);
            s_axi_araddr  <= addr;
            s_axi_arprot  <= 3'h0;
            s_axi_arvalid <= 1'b1;
            @(posedge aclk);
            while (s_axi_arvalid) begin
                if (s_axi_arready) s_axi_arvalid <= 1'b0;
                @(posedge aclk);
            end
            while (!s_axi_rvalid) @(posedge aclk);
            data        = s_axi_rdata;
            last_rresp  = s_axi_rresp;
        end
    endtask

    // poll a STATUS bit with a bounded number of CSR reads
    task automatic wait_status_bit(input integer bitn,
                                   input integer max_polls);
        reg [31:0] d;
        integer n;
        reg done_f;
        begin
            done_f = 1'b0;
            for (n = 0; (n < max_polls) && !done_f; n = n + 1) begin
                axi_read(32'h43C1_0000 + A_STATUS, d);
                if (d[bitn]) done_f = 1'b1;
            end
            check_count = check_count + 1;
            if (!done_f) begin
                $display("EES_CHECK FAIL STATUS[%0d] not set in %0d polls",
                         bitn, max_polls);
                error_count = error_count + 1;
            end
        end
    endtask

    // ------------------------------------------------------------ --
    // main sequence
    // ------------------------------------------------------------ --
    localparam [31:0] BASE = 32'h43C1_0000;

    reg [31:0] d;
    integer i;
    integer n;
    integer saved_errors;

    initial begin
        error_count = 0;
        check_count = 0;
        saved_errors = 0;

        s_axi_awaddr  = 32'h0;
        s_axi_awprot  = 3'h0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'h0;
        s_axi_wstrb   = 4'h0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b1;
        s_axi_araddr  = 32'h0;
        s_axi_arprot  = 3'h0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b1;
        aresetn       = 1'b0;

        repeat (20) @(posedge aclk);
        aresetn <= 1'b1;
        repeat (20) @(posedge aclk);

        $display("EES_VIVADO_STAGE TB_RUN");

        // -------------------------------------------------------- --
        // T1: identity / capability
        // -------------------------------------------------------- --
        $display("EES_TEST T1_identity");
        axi_read(BASE + A_ID, d);      check32("ID", d, YOLO_ID_VALUE);
        check_okay("ID_resp", last_rresp);
        axi_read(BASE + A_VERSION, d); check32("VERSION", d, YOLO_VERSION);
        axi_read(BASE + A_CAP0, d);    check32("CAP0", d, 32'h0710_0404);
        axi_read(BASE + A_CAP1, d);    check32("CAP1", d, 32'h0080_1007);

        // -------------------------------------------------------- --
        // T2: RW registers, all three write orders
        // -------------------------------------------------------- --
        $display("EES_TEST T2_rw_write_orders");
        axi_write(BASE + A_MODEL_ID, 32'hDEAD_BEEF);
        check_okay("MODEL_ID_wr", last_bresp);
        axi_read(BASE + A_MODEL_ID, d);
        check32("MODEL_ID", d, 32'hDEAD_BEEF);

        axi_write_aw_first(BASE + A_GRAPH_CRC, 32'h1234_5678, 5);
        check_okay("AW_first_wr", last_bresp);
        axi_read(BASE + A_GRAPH_CRC, d);
        check32("GRAPH_CRC_aw_first", d, 32'h1234_5678);

        axi_write_w_first(BASE + A_FRAME_ID, 32'h1122_3344, 5);
        check_okay("W_first_wr", last_bresp);
        axi_read(BASE + A_FRAME_ID, d);
        check32("FRAME_ID_w_first", d, 32'h1122_3344);

        // -------------------------------------------------------- --
        // T3: table windows (walker idle -> writable)
        // -------------------------------------------------------- --
        $display("EES_TEST T3_table_windows");
        axi_write(BASE + A_DESC_BASE, 32'h0000_0000);   // window base 0
        // descriptor item0 word0: opcode=1, valid, last
        axi_write(BASE + A_DESC_WIN + 32'h0000, 32'h0000_0301);
        // descriptor item0 word14: expected output bytes
        axi_write(BASE + A_DESC_WIN + 32'h0038, 32'h0002_46FC); // 149100
        axi_read(BASE + A_DESC_WIN + 32'h0000, d);
        check32("DESC_win_w0", d, 32'h0000_0301);
        axi_read(BASE + A_DESC_WIN + 32'h0038, d);
        check32("DESC_win_w14", d, 32'h0002_46FC);

        // buffer / quant / lut windows
        axi_write(BASE + A_BUF_WIN + 32'h0004, 32'h5555_AAAA);
        axi_read (BASE + A_BUF_WIN + 32'h0004, d);
        check32("BUF_win", d, 32'h5555_AAAA);
        axi_write(BASE + A_QUANT_WIN + 32'h0008, 32'h0F0F_0F0F);
        axi_read (BASE + A_QUANT_WIN + 32'h0008, d);
        check32("QUANT_win", d, 32'h0F0F_0F0F);
        axi_write(BASE + A_LUT_WIN + 32'h0500, 32'hCAFE_BABE);
        axi_read (BASE + A_LUT_WIN + 32'h0500, d);
        check32("LUT_win", d, 32'hCAFE_BABE);

        // DESC_BASE window move: base 0x800 maps the window onto
        // table words 2048..4095 (items 16..31)
        axi_write(BASE + A_DESC_BASE, 32'h0000_0800);
        axi_write(BASE + A_DESC_WIN + 32'h0000, 32'hAAAA_0000);
        axi_read (BASE + A_DESC_WIN + 32'h0000, d);
        check32("DESC_win_moved", d, 32'hAAAA_0000);
        axi_write(BASE + A_DESC_BASE, 32'h0000_0000);
        axi_read(BASE + A_DESC_WIN + 32'h0000, d);
        check32("DESC_win_restored", d, 32'h0000_0301);

        // -------------------------------------------------------- --
        // T4: doorbell end-to-end frame flow
        // -------------------------------------------------------- --
        $display("EES_TEST T4_doorbell_flow");
        axi_write(BASE + A_DESC_CFG,  32'h0000_0080);   // depth 128
        axi_write(BASE + A_DESC_TAIL, 32'h0000_0001);   // 1 item queued
        axi_write(BASE + A_DESC_DOORBELL, 32'h0000_0001); // commit
        axi_write(BASE + A_CTRL, 32'h0000_0005);        // ENABLE+START_FRAME
        wait_status_bit(2, 1000);                        // STATUS.FRAMED_DONE

        axi_read(BASE + A_RESULT_SEQ, d);
        check32("RESULT_SEQ", d, 32'h0000_0001);
        axi_read(BASE + A_HEAD_BYTES, d);
        check32("HEAD_BYTES", d, 32'h0002_46FC);
        axi_read(BASE + A_RESULT_RING_HEAD, d);
        check32("RING_HEAD", d, 32'h0000_0001);
        axi_read(BASE + A_RESULT_STATUS, d);
        check32("RESULT_STATUS", d, 32'h0000_0011);     // valid + ps_owned

        // ring window entry 0
        axi_read(BASE + A_RING_WIN + 32'h0004, d);      // w1 = seq
        check32("RING_w1_seq", d, 32'h0000_0001);
        axi_read(BASE + A_RING_WIN + 32'h0010, d);      // w4 = bytes
        check32("RING_w4_bytes", d, 32'h0002_46FC);
        axi_read(BASE + A_RING_WIN + 32'h0028, d);      // w10 flags
        check32("RING_w10_flags", d, 32'h0000_0011);

        // consume through RESULT_ACK
        axi_write(BASE + A_RESULT_ACK, 32'h0000_0001);
        axi_read(BASE + A_RESULT_RING_TAIL, d);
        check32("RING_TAIL_after_ack", d, 32'h0000_0001);
        axi_read(BASE + A_STATUS, d);
        check32("STATUS_ack_wait_cleared", d & 32'h0000_0080, 32'h0);
        // board l3r1 (2026-09-18): a legitimate ACK latched a false
        // E_BIT_PROTOCOL via a same-edge tail advance; masked checks let
        // it through.  Assert the full register after every ACK.
        axi_read(BASE + A_ERROR_STATUS, d);
        check32("ERRSTAT_after_ack_full", d, 32'h0000_0000);

        // -------------------------------------------------------- --
        // T5: running-write protection + frame_end doorbell
        // -------------------------------------------------------- --
        $display("EES_TEST T5_running_write_guard");
        // item0 becomes valid non-last: walker parks in W_CHK polling
        // word0 layout: opcode=[7:0], valid=bit8, last=bit9 -> 0x0101
        axi_write(BASE + A_DESC_WIN + 32'h0000, 32'h0000_0101);
        axi_write(BASE + A_DESC_WIN + 32'h0038, 32'h0000_0064); // 100 B
        axi_write(BASE + A_DESC_TAIL, 32'h0000_0001);
        axi_write(BASE + A_CTRL, 32'h0000_0005);        // new frame
        wait_status_bit(1, 1000);                        // STATUS.RUNNING

        // table write while running -> SLVERR + ERROR_STATUS.LUT
        axi_write(BASE + A_LUT_WIN + 32'h0000, 32'h1234_5678);
        check_slv("LUT_run_wr", last_bresp);
        axi_read(BASE + A_ERROR_STATUS, d);
        check32("ERRSTAT_lut_bit", d & 32'h0000_0040, 32'h0000_0040);
        axi_read(BASE + A_ERROR_INFO, d);
        check32("ERRINFO_lut_code", d & 32'h0000_00FF, E_CODE_TABLE_RUN);

        // frame_end doorbell completes the frame without a last flag
        axi_write(BASE + A_DESC_DOORBELL, 32'h0000_0002);
        wait_status_bit(2, 1000);                        // FRAME_DONE
        axi_read(BASE + A_HEAD_BYTES, d);
        check32("HEAD_BYTES_fend", d, 32'h0000_0064);

        // W1C clear of the lut error bit
        axi_write(BASE + A_ERROR_STATUS, 32'h0000_0040);
        axi_read(BASE + A_ERROR_STATUS, d);
        check32("ERRSTAT_w1c", d & 32'h0000_0040, 32'h0);

        // -------------------------------------------------------- --
        // T6: ring overflow (33 frames, no ack)
        // -------------------------------------------------------- --
        $display("EES_TEST T6_ring_overflow");
        // item0 valid+last again; after each frame head resets to 0 and
        // tail stays 1, so a bare START re-walks the same item
        axi_write(BASE + A_DESC_WIN + 32'h0000, 32'h0000_0301);
        axi_write(BASE + A_DESC_WIN + 32'h0038, 32'h0000_0064);
        for (i = 0; i < 33; i = i + 1) begin
            axi_write(BASE + A_CTRL, 32'h0000_0005);    // ENABLE+START
            wait_status_bit(2, 1000);                    // FRAME_DONE
        end
        axi_read(BASE + A_RESULT_RING_HEAD, d);
        check32("RING_HEAD_ovf", d, 32'h0000_0020);     // 32 kept
        axi_read(BASE + A_RESULT_SEQ, d);
        check32("RESULT_SEQ_ovf", d, 32'h0000_0023);    // 35 publishes total
        axi_read(BASE + A_RESULT_STATUS, d);
        check32("RESULT_STATUS_ovf", d & 32'h0000_0002, 32'h0000_0002);
        axi_read(BASE + A_ERROR_STATUS, d);
        check32("ERRSTAT_ovf_bit", d & 32'h0000_0100, 32'h0000_0100);

        // -------------------------------------------------------- --
        // T7: ack on empty ring (tail caught up) -> protocol error
        // -------------------------------------------------------- --
        $display("EES_TEST T7_ack_on_empty");
        // drain: ack until the ring reports empty (bounded); the
        // occupied count is data-dependent (T4 acked its entry), so a
        // fixed number of acks could push the tail past empty and
        // make the ring look non-empty again
        n = 0;
        axi_read(BASE + A_STATUS, d);
        while (d[7] && n < 40) begin
            axi_write(BASE + A_RESULT_ACK, 32'h0000_0001);
            n = n + 1;
            axi_read(BASE + A_STATUS, d);
        end
        axi_read(BASE + A_STATUS, d);
        check32("STATUS_ring_empty", d & 32'h0000_0080, 32'h0);
        // one more ack on the now-empty ring
        axi_write(BASE + A_RESULT_ACK, 32'h0000_0001);
        axi_read(BASE + A_ERROR_STATUS, d);
        check32("ERRSTAT_ack_empty", d & 32'h0000_0200, 32'h0000_0200);
        axi_read(BASE + A_ERROR_INFO, d);
        check32("ERRINFO_ack_code", d & 32'h0000_00FF, E_CODE_ACK_EMPTY);

        // -------------------------------------------------------- --
        // T8: SLVERR paths (misaligned, unmapped, ring RO, debug)
        // -------------------------------------------------------- --
        $display("EES_TEST T8_slverr_paths");
        // walker is idle after the last frame -> tables unlocked
        axi_write(BASE + 32'h0000_1002, 32'hFFFF_FFFF);  // misaligned
        check_slv("misaligned_wr", last_bresp);
        axi_read(BASE + 32'h0000_8000, d);               // unmapped region
        check_slv("unmapped_rd", last_rresp);
        axi_write(BASE + 32'h0000_6000, 32'hFFFF_FFFF);  // ring read-only
        check_slv("ring_ro_wr", last_bresp);
        axi_read(BASE + 32'h0000_7000, d);               // debug window
        check_okay("debug_rd_resp", last_rresp);
        check32("debug_rd_data", d, 32'h0);

        axi_read(BASE + A_ERROR_STATUS, d);
        check32("ERRSTAT_axi_bit", d & 32'h0000_0001, 32'h0000_0001);

        // -------------------------------------------------------- --
        // summary
        // -------------------------------------------------------- --
        $display("EES_VIVADO_STAGE TB_DONE");
        $display("EES_SUMMARY checks=%0d errors=%0d", check_count, error_count);
        if (error_count == 0) begin
            $display("EES_VIVADO_RESULT PASS");
        end else begin
            $display("EES_VIVADO_RESULT FAIL");
        end
        #100;
        $finish;
    end

endmodule
