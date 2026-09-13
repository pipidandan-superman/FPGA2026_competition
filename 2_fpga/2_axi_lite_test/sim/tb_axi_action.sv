//====================================================================
// File name   : tb_axi_action.sv
// Author      : Codex
// Create date : 2026-09-12
// Description : Independent PS-PL AXI-Lite register test
// Target      : FPGA
// Revision    : V1.0
//====================================================================
`timescale 1ns/1ps
module tb_axi_action;
    reg          clk = 0;
    reg          resetn = 0;
    reg  [11:0]  s_axi_awaddr = 0;
    reg  [2:0]   s_axi_awprot = 0;
    reg          s_axi_awvalid = 0;
    wire         s_axi_awready;
    reg  [31:0]  s_axi_wdata = 0;
    reg  [3:0]   s_axi_wstrb = 0;
    reg          s_axi_wvalid = 0;
    wire         s_axi_wready;
    wire [1:0]   s_axi_bresp;
    wire         s_axi_bvalid;
    reg          s_axi_bready = 0;
    reg  [11:0]  s_axi_araddr = 0;
    reg  [2:0]   s_axi_arprot = 0;
    reg          s_axi_arvalid = 0;
    wire         s_axi_arready;
    wire [31:0]  s_axi_rdata;
    wire [1:0]   s_axi_rresp;
    wire         s_axi_rvalid;
    reg          s_axi_rready = 0;
    localparam integer divisor = 16;
    wire uart_tx;
    wire [6:0] action_led;
    always #10 clk = ~clk;
    axi_action_control_top #(.clock_freq_hz(153600), .baud_rate(9600)) dut (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .s_axi_awaddr   (s_axi_awaddr  ),
        .s_axi_awprot   (s_axi_awprot  ),
        .s_axi_awvalid  (s_axi_awvalid ),
        .s_axi_awready  (s_axi_awready ),
        .s_axi_wdata    (s_axi_wdata   ),
        .s_axi_wstrb    (s_axi_wstrb   ),
        .s_axi_wvalid   (s_axi_wvalid  ),
        .s_axi_wready   (s_axi_wready  ),
        .s_axi_bresp    (s_axi_bresp   ),
        .s_axi_bvalid   (s_axi_bvalid  ),
        .s_axi_bready   (s_axi_bready  ),
        .s_axi_araddr   (s_axi_araddr  ),
        .s_axi_arprot   (s_axi_arprot  ),
        .s_axi_arvalid  (s_axi_arvalid ),
        .s_axi_arready  (s_axi_arready ),
        .s_axi_rdata    (s_axi_rdata   ),
        .s_axi_rresp    (s_axi_rresp   ),
        .s_axi_rvalid   (s_axi_rvalid  ),
        .s_axi_rready   (s_axi_rready  ),
        .uart_tx        (uart_tx       ),
        .action_led     (action_led    )
    );

    integer checks = 0;
    integer aw_count = 0, w_count = 0, b_count = 0, ar_count = 0, r_count = 0;
    reg prev_bstall = 0, prev_rstall = 0;
    reg [1:0] prev_bresp, prev_rresp;
    reg [31:0] prev_rdata;

    task automatic fail(input string reason);
        $display("AXI_ACTION_FAIL %s time=%0t", reason, $time);
        $display("VITA_VIVADO_RESULT FAIL");
        $fatal(1, "%s", reason);
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            aw_count = 0; w_count = 0; b_count = 0; ar_count = 0; r_count = 0;
            prev_bstall = 0; prev_rstall = 0;
        end else begin
            if ($isunknown({s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_bresp,
                            s_axi_arready,s_axi_rvalid,s_axi_rresp,s_axi_rdata}))
                fail("X/Z at AXI outputs");
            if (prev_bstall && (!s_axi_bvalid || s_axi_bresp !== prev_bresp))
                fail("B response changed under backpressure");
            if (prev_rstall && (!s_axi_rvalid || s_axi_rresp !== prev_rresp ||
                               s_axi_rdata !== prev_rdata))
                fail("R response changed under backpressure");
            if (s_axi_awvalid && s_axi_awready) aw_count = aw_count + 1;
            if (s_axi_wvalid && s_axi_wready) w_count = w_count + 1;
            if (s_axi_bvalid && s_axi_bready) b_count = b_count + 1;
            if (s_axi_arvalid && s_axi_arready) ar_count = ar_count + 1;
            if (s_axi_rvalid && s_axi_rready) r_count = r_count + 1;
            if (b_count > aw_count || b_count > w_count || r_count > ar_count)
                fail("Unsolicited or duplicate response");
            if ((aw_count-b_count)>1 || (w_count-b_count)>1 || (ar_count-r_count)>1)
                fail("More than one outstanding transaction");
            prev_bstall = s_axi_bvalid && !s_axi_bready;
            prev_rstall = s_axi_rvalid && !s_axi_rready;
            prev_bresp = s_axi_bresp; prev_rresp = s_axi_rresp; prev_rdata = s_axi_rdata;
        end
    end

    task automatic reset_dut;
        @(negedge clk);
        resetn = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_arvalid = 0;
        s_axi_bready = 0; s_axi_rready = 0;
        repeat (5) @(negedge clk);
        resetn = 1;
        repeat (3) @(negedge clk);
    endtask

    task automatic send_aw(input [11:0] addr, input integer delay_cycles);
        repeat (delay_cycles) @(negedge clk);
        @(negedge clk); s_axi_awaddr = addr; s_axi_awvalid = 1;
        do @(posedge clk); while (s_axi_awready !== 1);
        @(negedge clk); s_axi_awvalid = 0;
    endtask

    task automatic send_w(input [31:0] data, input [3:0] strb, input integer delay_cycles);
        repeat (delay_cycles) @(negedge clk);
        @(negedge clk); s_axi_wdata = data; s_axi_wstrb = strb; s_axi_wvalid = 1;
        do @(posedge clk); while (s_axi_wready !== 1);
        @(negedge clk); s_axi_wvalid = 0;
    endtask

    task automatic write_reg(input [11:0] addr, input [31:0] data,
                             input [3:0] strb, input integer aw_delay,
                             input integer w_delay, input integer stall,
                             input [1:0] expected_response);
        fork
            send_aw(addr, aw_delay);
            send_w(data, strb, w_delay);
        join
        wait (s_axi_bvalid === 1);
        repeat (stall) @(negedge clk);
        if (s_axi_bresp !== expected_response) fail($sformatf("Write response @%h", addr));
        @(negedge clk); s_axi_bready = 1;
        @(posedge clk);
        @(negedge clk); s_axi_bready = 0;
        checks = checks + 1;
    endtask

    task automatic read_reg(input [11:0] addr, input integer stall,
                            input [1:0] expected_response, output [31:0] data);
        @(negedge clk); s_axi_araddr = addr; s_axi_arvalid = 1;
        do @(posedge clk); while (s_axi_arready !== 1);
        @(negedge clk); s_axi_arvalid = 0;
        wait (s_axi_rvalid === 1);
        repeat (stall) @(negedge clk);
        if (s_axi_rresp !== expected_response) fail($sformatf("Read response @%h", addr));
        data = s_axi_rdata;
        @(negedge clk); s_axi_rready = 1;
        @(posedge clk);
        @(negedge clk); s_axi_rready = 0;
        checks = checks + 1;
    endtask

    task automatic expect_read(input [11:0] addr, input [31:0] expected);
        reg [31:0] data;
        read_reg(addr, 2, 0, data);
        if (data !== expected)
            fail($sformatf("Read @%h got=%h expected=%h", addr, data, expected));
    endtask

    task automatic wait_done;
        reg [31:0] status;
        integer polls;
        status = 0; polls = 0;
        while (!status[2] && polls < 10000) begin
            read_reg(12'h01c, 0, 0, status);
            polls = polls + 1;
        end
        if (!status[2] || status[1]) fail("Command did not complete");
    endtask


    integer byte_count = 0;
    reg [7:0] received [0:20000];
    reg [7:0] rx_byte;
    integer bit_number;
    // Independent line decoder samples the middle of each bit. A frame is
    // counted only after the complete stop bit, before CSR DONE may publish.
    initial forever begin
        @(negedge uart_tx);
        if (resetn) begin
            repeat (divisor / 2) @(negedge clk);
            if (uart_tx !== 0) fail("UART start bit");
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                repeat (divisor) @(negedge clk);
                rx_byte[bit_number] = uart_tx;
            end
            repeat (divisor) @(negedge clk);
            if (uart_tx !== 1) fail("UART stop bit");
            repeat (divisor / 2) @(negedge clk);
            received[byte_count] = rx_byte;
            byte_count = byte_count + 1;
        end
    end

    function automatic [7:0] reference_crc(input [31:0] message);
        reg [15:0] polynomial_work;
        integer b;
        begin
            // Polynomial division independent of DUT's per-byte crc routine.
            polynomial_work = 0;
            for (b = 31; b >= 0; b = b - 1) begin
                polynomial_work = (polynomial_work << 1) | message[b];
                if (polynomial_work[8]) polynomial_work = polynomial_work ^ 16'h107;
            end
            for (b = 0; b < 8; b = b + 1) begin
                polynomial_work = polynomial_work << 1;
                if (polynomial_work[8]) polynomial_work = polynomial_work ^ 16'h107;
            end
            reference_crc = polynomial_work[7:0];
        end
    endfunction

    task automatic execute_action(input [31:0] seq, input [7:0] action,
                                   input [31:0] count);
        integer before_bytes;
        reg [31:0] status;
        reg [7:0] crc;
        reg [6:0] led_expected;
        begin
            before_bytes = byte_count;
            crc = reference_crc({16'ha55a, seq[7:0], action});
            write_reg('h010, action, 15, 0, 5, 0, 0);
            write_reg('h014, seq, 15, 5, 0, 0, 0);
            write_reg('h018, 1, 15, 0, 0, 3, 0);
            led_expected = action == 0 ? 0 : (7'b1 << (action - 1));
            if (action_led !== led_expected) fail("LED mapping/start snapshot");
            // Rejected writes while sending must not change the snapshot.
            write_reg('h010, 7-action, 15, 0, 0, 0, 2);
            write_reg('h014, seq+1, 15, 0, 0, 0, 2);
            write_reg('h018, 1, 15, 0, 0, 0, 2);
            write_reg('h018, 2, 15, 0, 0, 0, 2);
            expect_read('h020, seq);
            wait_done();
            if (byte_count != before_bytes+7) fail("DONE before full frame or extra UART bytes");
            if (received[before_bytes] !== 8'ha5 ||
                received[before_bytes+1] !== 8'h5a ||
                received[before_bytes+2] !== seq[7:0] ||
                received[before_bytes+3] !== action ||
                received[before_bytes+4] !== crc ||
                received[before_bytes+5] !== 8'h0d ||
                received[before_bytes+6] !== 8'h0a) fail("UART frame/CRC mismatch");
            expect_read('h024, seq);
            expect_read('h028, action);
            expect_read('h02c, 0);
            expect_read('h030, count);
            expect_read('h034, {8'b0, crc, seq[7:0], action});
            expect_read('h038, 1);
            expect_read('h03c, count);
            expect_read('h01c, 4);
            repeat (20) @(negedge clk);
            expect_read('h028, action);
            write_reg('h018, 1, 15, 0, 0, 0, 2);
            write_reg('h018, 2, 15, 0, 0, 0, 0);
            expect_read('h01c, 1);
            write_reg('h018, 1, 15, 0, 0, 0, 2);
            if (byte_count != before_bytes+7 || action_led !== led_expected)
                fail("Rejected duplicate changed outputs");
        end
    endtask

    integer i, lane, seed, dummy;
    reg [31:0] data, value, model;
    reg [3:0] strobe;
    integer file_handle;
    initial begin
        $display("VITA_VIVADO_STAGE AXI_ACTION");
        seed = 3312026;
        dummy = $urandom(seed);
        reset_dut();
        expect_read(0, 32'h4143544c);
        expect_read(4, 'h10000);
        expect_read(8, 7);
        expect_read('h01c, 1);
        if (action_led !== 0 || uart_tx !== 1) fail("Reset outputs");
        write_reg('h018, 1, 15, 0, 0, 0, 2);
        write_reg('h018, 2, 15, 0, 0, 0, 2);
        model = 0;
        for (i=0; i<256; i=i+1) begin
            strobe = i % 16;
            value = $urandom;
            write_reg('h00c, value, strobe, (i%3==1)?7:0, (i%3==2)?9:0,
                      $urandom_range(0,8), 0);
            for (lane=0; lane<4; lane=lane+1)
                if (strobe[lane]) model[lane*8 +: 8] = value[lane*8 +: 8];
            expect_read('h00c, model);
            write_reg('h010, i, 15, 0, 0, 0, (i>7)?2:0);
        end
        for (i=0; i<4096; i=i+1) begin
            if (i%4 != 0 || i>'h03c) begin
                write_reg(i, 'hffffffff, 15, 0, 0, 0, 2);
                read_reg(i, 0, 2, data);
                if (data !== 0) fail("Invalid read data");
            end
        end
        for (i=0; i<= 'h03c; i=i+4)
            if (i != 'h00c && i != 'h010 && i != 'h014 && i != 'h018)
                write_reg(i, 'hffff, 15, 0, 0, 0, 2);
        for (i=0; i<15; i=i+1) begin
            write_reg('h010, 1, i, 0, 0, 0, 2);
            write_reg('h014, 1, i, 0, 0, 0, 2);
            write_reg('h018, 1, i, 0, 0, 0, 2);
        end
        write_reg('h010, 'h100, 15, 0, 0, 0, 2);
        fork
            write_reg('h00c, 'h1234, 15, 0, 0, 50, 0);
            begin wait(s_axi_bvalid); expect_read(0, 'h4143544c); end
        join
        for (i=1; i<=1000; i=i+1) begin
            execute_action(i, (i-1)%8, i);
        end
        execute_action('hffffffff, 7, 1001);
        write_reg('h014, 1, 15, 0, 0, 0, 0);
        write_reg('h018, 1, 15, 0, 0, 0, 2);
        send_aw('h00c, 0); reset_dut(); expect_read('h00c, 0);
        send_w('h1234, 15, 0); reset_dut(); expect_read('h00c, 0);
        fork send_aw('h00c, 0); send_w('h1234, 15, 0); join
        wait(s_axi_bvalid); reset_dut(); expect_read('h00c, 0);
        @(negedge clk); s_axi_arvalid=1;
        do @(posedge clk); while(!s_axi_arready);
        @(negedge clk); s_axi_arvalid=0;
        wait(s_axi_rvalid); reset_dut();
        execute_action(1, 4, 1);
        // Reset interrupts a frame. The receiver ignores this final partial
        // frame; reset must quiesce TX/LED immediately and leave no completion.
        write_reg('h014, 2, 15, 0, 0, 0, 0);
        write_reg('h018, 1, 15, 0, 0, 0, 0);
        repeat (25) @(negedge clk);
        reset_dut();
        if (uart_tx !== 1 || action_led !== 0) fail("Active command reset");
        expect_read('h01c, 1);
        expect_read('h030, 0);
        expect_read('h034, 0);
        file_handle = $fopen("action_sim_result.txt", "w");
        $fdisplay(file_handle, "AXI_ACTION_RTL_PASS commands=1002 checks=%0d", checks);
        $fclose(file_handle);
        $display("AXI_ACTION_RTL_PASS commands=1002 checks=%0d", checks);
        $display("VITA_VIVADO_RESULT PASS");
        $display("EES_VIVADO_RESULT PASS");
        $finish;
    end
    initial begin
        #50000000;
        fail("Simulation watchdog");
    end
endmodule

