//====================================================================
// File name   : tb_ble_uart_debug_top.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Self-checking transparent UART bridge simulation
// Target      : Vivado XSim
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module tb_ble_uart_debug_top;

    localparam integer bit_ns = 100_000;
    reg        clk;
    reg        rst_n;
    reg        host_tx;
    reg        module_tx;
    wire       host_rx;
    wire       module_rx;
    wire       power_en;
    wire       reset_n;
    wire       ready;
    wire [7:0] host_data;
    wire [7:0] module_data;
    wire       host_done;
    wire       module_done;
    wire       host_error;
    wire       module_error;
    reg  [7:0] expected_host [0:255];
    reg  [7:0] expected_module [0:255];
    integer    host_count;
    integer    module_count;
    integer    host_expected_count;
    integer    module_expected_count;
    integer    index;
    integer    result_file;

    ble_uart_debug_top #(
        .clock_freq_hz    (1_000_000),
        .power_delay_ms   (1),
        .startup_delay_ms (1)
    ) dut (
        .SYS_CLK      (clk),
        .SYS_RST_N    (rst_n),
        .PL_RS232_RX  (host_tx),
        .BT_TX        (module_tx),
        .PL_RS232_TX  (host_rx),
        .BT_RX        (module_rx),
        .FPGA_BT_3V3  (power_en),
        .BT_RESET_N   (reset_n),
        .BRIDGE_READY (ready)
    );

    uart_rx #(
        .CLOCK_FREQ_HZ (1_000_000),
        .BAUD_RATE     (10_000)
    ) u_host_receiver (
        .clk_i         (clk),
        .rst_n_i       (rst_n),
        .rx_i          (host_rx),
        .data_o        (host_data),
        .done_o        (host_done),
        .frame_error_o (host_error)
    );

    uart_rx #(
        .CLOCK_FREQ_HZ (1_000_000),
        .BAUD_RATE     (10_000)
    ) u_module_receiver (
        .clk_i         (clk),
        .rst_n_i       (rst_n),
        .rx_i          (module_rx),
        .data_o        (module_data),
        .done_o        (module_done),
        .frame_error_o (module_error)
    );

    initial begin
        clk = 1'b0;
        forever #500 clk = ~clk;
    end

    task fail;
        input [511:0] message;
        begin
            $display("EES_VIVADO_RESULT FAIL: %0s", message);
            result_file = $fopen("tb_result.txt", "w");
            $fdisplay(result_file, "BLE_UART_BRIDGE_SIM_FAIL %0s", message);
            $fclose(result_file);
            $fatal(1, "%0s", message);
        end
    endtask

    task send_host;
        input [7:0] value;
        integer bit_index;
        begin
            expected_module[module_expected_count] = value;
            module_expected_count = module_expected_count + 1;
            @(negedge clk);
            host_tx = 1'b0;
            #(bit_ns);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                host_tx = value[bit_index];
                #(bit_ns);
            end
            host_tx = 1'b1;
            #(bit_ns);
        end
    endtask

    task send_module;
        input [7:0] value;
        integer bit_index;
        begin
            expected_host[host_expected_count] = value;
            host_expected_count = host_expected_count + 1;
            @(negedge clk);
            module_tx = 1'b0;
            #(bit_ns);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                module_tx = value[bit_index];
                #(bit_ns);
            end
            module_tx = 1'b1;
            #(bit_ns);
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            if ((^{host_rx, module_rx, power_en, reset_n, ready}) === 1'bx) begin
                fail("Unknown bridge output");
            end
            if (host_error || module_error) begin
                fail("UART frame error");
            end
            if (host_done) begin
                if ((host_count >= host_expected_count)
                    || (host_data !== expected_host[host_count])) begin
                    fail("Module-to-host byte mismatch or unexpected byte");
                end
                $display("MODULE_TO_HOST index=%0d data=%02h", host_count, host_data);
                host_count = host_count + 1;
            end
            if (module_done) begin
                if ((module_count >= module_expected_count)
                    || (module_data !== expected_module[module_count])) begin
                    fail("Host-to-module byte mismatch or unexpected byte");
                end
                $display("HOST_TO_MODULE index=%0d data=%02h", module_count, module_data);
                module_count = module_count + 1;
            end
        end
    end

    initial begin
        #100_000_000;
        fail("Watchdog timeout");
    end

    initial begin
        rst_n                 = 1'b0;
        host_tx               = 1'b1;
        module_tx             = 1'b1;
        host_count            = 0;
        module_count          = 0;
        host_expected_count   = 0;
        module_expected_count = 0;
        #2_000;
        if (dut.state !== 2'd0 || ready !== 1'b0 || reset_n !== 1'b0) begin
            fail("Reset did not enter IDLE");
        end
        @(negedge clk);
        rst_n = 1'b1;
        #500_000;
        if (ready !== 1'b0 || reset_n !== 1'b0 || power_en !== 1'b1) begin
            fail("Power/reset hold window incorrect");
        end
        wait (reset_n === 1'b1);
        if (ready !== 1'b0) begin
            fail("Bridge enabled before startup delay");
        end
        wait (ready === 1'b1);
        $display("EES_VIVADO_STAGE BRIDGE_READY");

        // Query bytes test transport only, not a claim about real firmware support.
        send_host("A");
        send_host("T");
        send_host("+");
        send_host("P");
        send_host("I");
        send_host("N");
        send_host(8'h0d);
        send_host(8'h0a);

        // Artificial response: 654321 is a simulation fixture, never the real PIN.
        send_module("+");
        send_module("P");
        send_module("I");
        send_module("N");
        send_module("=");
        send_module("6");
        send_module("5");
        send_module("4");
        send_module("3");
        send_module("2");
        send_module("1");
        send_module(8'h0d);
        send_module(8'h0a);

        $display("EES_VIVADO_STAGE FULL_DUPLEX");
        fork
            begin
                send_host(8'h00);
                send_host(8'hff);
                send_host(8'haa);
                send_host(8'h55);
            end
            begin
                send_module(8'h55);
                send_module(8'haa);
                send_module(8'h00);
                send_module(8'hff);
            end
        join
        #(2 * bit_ns);
        if (host_count != host_expected_count || module_count != module_expected_count) begin
            fail("Missing final bytes");
        end

        // Reset recovery must quiesce both directions and restore startup sequencing.
        @(negedge clk);
        rst_n = 1'b0;
        #2_000;
        if (host_rx !== 1'b1 || module_rx !== 1'b1 || dut.state !== 2'd0) begin
            fail("Reset recovery did not quiesce UART outputs");
        end
        @(negedge clk);
        rst_n = 1'b1;
        wait (ready === 1'b1);
        send_host(8'ha5);
        send_module(8'h5a);
        #(2 * bit_ns);
        if (host_count != host_expected_count || module_count != module_expected_count) begin
            fail("Missing post-reset bytes");
        end
        result_file = $fopen("tb_result.txt", "w");
        $fdisplay(result_file, "BLE_UART_BRIDGE_SIM_PASS host=%0d module=%0d",
                  host_count, module_count);
        $fclose(result_file);
        $display("BLE_UART_BRIDGE_SIM_PASS host=%0d module=%0d", host_count, module_count);
        $finish;
    end

endmodule
