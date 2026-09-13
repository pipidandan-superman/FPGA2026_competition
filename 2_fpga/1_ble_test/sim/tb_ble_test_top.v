//====================================================================
// File name   : tb_ble_test_top.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Self-checking PASS and timeout tests for Bluetooth RTL
// Target      : RTL simulation
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module tb_ble_test_top;

    localparam integer CLOCK_FREQ_HZ  = 1_000_000;
    localparam integer BAUD_RATE      = 10_000;
    localparam integer CLOCKS_PER_BIT = CLOCK_FREQ_HZ / BAUD_RATE;

    reg sys_clk;
    reg sys_rst_n;
    reg pass_bt_tx;
    reg timeout_bt_tx;

    wire       pass_bt_rx;
    wire       pass_power;
    wire       pass_reset_n;
    wire       pass_test_pass;
    wire       pass_test_fail;
    wire       pass_response_seen;
    wire       pass_frame_error;
    wire [3:0] pass_state;

    wire       timeout_bt_rx;
    wire       timeout_power;
    wire       timeout_reset_n;
    wire       timeout_test_pass;
    wire       timeout_test_fail;
    wire       timeout_response_seen;
    wire       timeout_frame_error;
    wire [3:0] timeout_state;

    wire [7:0] pass_command_data;
    wire       pass_command_done;
    wire       pass_command_error;
    wire [7:0] timeout_command_data;
    wire       timeout_command_done;
    wire       timeout_command_error;

    integer pass_command_count;
    integer timeout_command_count;
    integer pass_rx_count;
    integer error_count;
    reg     pass_error_seen;
    reg     timeout_error_seen;

    ble_test_top #(
        .CLOCK_FREQ_HZ       (CLOCK_FREQ_HZ),
        .BAUD_RATE           (BAUD_RATE),
        .POWER_DELAY_MS      (1),
        .STARTUP_DELAY_MS    (2),
        .RESPONSE_TIMEOUT_MS (20),
        .SEND_CRLF           (1),
        .ENABLE_ILA          (0)
    ) u_pass_dut (
        .SYS_CLK        (sys_clk),
        .SYS_RST_N      (sys_rst_n),
        .BT_TX          (pass_bt_tx),
        .BT_RX          (pass_bt_rx),
        .FPGA_BT_3V3    (pass_power),
        .BT_RESET_N     (pass_reset_n),
        .TEST_PASS      (pass_test_pass),
        .TEST_FAIL      (pass_test_fail),
        .RESPONSE_SEEN  (pass_response_seen),
        .RX_FRAME_ERROR (pass_frame_error),
        .DEBUG_STATE    (pass_state)
    );

    ble_test_top #(
        .CLOCK_FREQ_HZ       (CLOCK_FREQ_HZ),
        .BAUD_RATE           (BAUD_RATE),
        .POWER_DELAY_MS      (1),
        .STARTUP_DELAY_MS    (2),
        .RESPONSE_TIMEOUT_MS (20),
        .SEND_CRLF           (1),
        .ENABLE_ILA          (0)
    ) u_timeout_dut (
        .SYS_CLK        (sys_clk),
        .SYS_RST_N      (sys_rst_n),
        .BT_TX          (timeout_bt_tx),
        .BT_RX          (timeout_bt_rx),
        .FPGA_BT_3V3    (timeout_power),
        .BT_RESET_N     (timeout_reset_n),
        .TEST_PASS      (timeout_test_pass),
        .TEST_FAIL      (timeout_test_fail),
        .RESPONSE_SEEN  (timeout_response_seen),
        .RX_FRAME_ERROR (timeout_frame_error),
        .DEBUG_STATE    (timeout_state)
    );

    uart_rx #(
        .CLOCK_FREQ_HZ (CLOCK_FREQ_HZ),
        .BAUD_RATE     (BAUD_RATE)
    ) u_pass_command_monitor (
        .clk_i         (sys_clk),
        .rst_n_i       (sys_rst_n),
        .rx_i          (pass_bt_rx),
        .data_o        (pass_command_data),
        .done_o        (pass_command_done),
        .frame_error_o (pass_command_error)
    );

    uart_rx #(
        .CLOCK_FREQ_HZ (CLOCK_FREQ_HZ),
        .BAUD_RATE     (BAUD_RATE)
    ) u_timeout_command_monitor (
        .clk_i         (sys_clk),
        .rst_n_i       (sys_rst_n),
        .rx_i          (timeout_bt_rx),
        .data_o        (timeout_command_data),
        .done_o        (timeout_command_done),
        .frame_error_o (timeout_command_error)
    );

    always #500 sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            pass_command_count    <= 0;
            timeout_command_count <= 0;
            pass_rx_count         <= 0;
            error_count           <= 0;
            pass_error_seen       <= 1'b0;
            timeout_error_seen    <= 1'b0;
        end else begin
            if (pass_command_error || pass_frame_error) begin
                pass_error_seen <= 1'b1;
            end

            if (timeout_command_error || timeout_frame_error) begin
                timeout_error_seen <= 1'b1;
            end

            if (pass_command_done) begin
                check_command_byte(pass_command_count, pass_command_data);
                pass_command_count <= pass_command_count + 1;
            end

            if (timeout_command_done) begin
                check_command_byte(timeout_command_count, timeout_command_data);
                timeout_command_count <= timeout_command_count + 1;
            end

            if (u_pass_dut.rx_done) begin
                pass_rx_count <= pass_rx_count + 1;
            end
        end
    end

    task check_command_byte;
        input integer byte_index;
        input [7:0] byte_value;
        reg [7:0] expected_value;
        begin
            case (byte_index)
                0: expected_value = 8'h41;
                1: expected_value = 8'h54;
                2: expected_value = 8'h0d;
                3: expected_value = 8'h0a;
                default: expected_value = 8'hxx;
            endcase

            if ((byte_index > 3) || (byte_value !== expected_value)) begin
                error_count = error_count + 1;
                $display("COMMAND_MISMATCH index=%0d actual=%02h expected=%02h",
                         byte_index, byte_value, expected_value);
            end
        end
    endtask

    task send_uart_byte;
        input [7:0] data_value;
        integer bit_number;
        begin
            pass_bt_tx = 1'b0;
            repeat (CLOCKS_PER_BIT) @(posedge sys_clk);

            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                pass_bt_tx = data_value[bit_number];
                repeat (CLOCKS_PER_BIT) @(posedge sys_clk);
            end

            pass_bt_tx = 1'b1;
            repeat (CLOCKS_PER_BIT) @(posedge sys_clk);
        end
    endtask

    initial begin
        sys_clk       = 1'b0;
        sys_rst_n     = 1'b0;
        pass_bt_tx    = 1'b1;
        timeout_bt_tx = 1'b1;

        repeat (10) @(posedge sys_clk);
        sys_rst_n = 1'b1;

        wait ((pass_command_count == 4) && (timeout_command_count == 4));
        repeat (20) @(posedge sys_clk);
        send_uart_byte(8'h4f);
        send_uart_byte(8'h4b);

        wait (pass_test_pass && timeout_test_fail);
        repeat (5) @(posedge sys_clk);

        if (pass_test_pass && !pass_test_fail && pass_response_seen &&
            timeout_test_fail && !timeout_test_pass &&
            !timeout_response_seen && (pass_command_count == 4) &&
            (timeout_command_count == 4) && (pass_rx_count == 2) &&
            !pass_error_seen && !timeout_error_seen &&
            (error_count == 0) && pass_power && timeout_power &&
            pass_reset_n && timeout_reset_n) begin
            $display("BLE_RTL_SIM_PASS");
        end else begin
            $display("BLE_RTL_SIM_FAIL errors=%0d pass_state=%0d timeout_state=%0d",
                     error_count, pass_state, timeout_state);
        end

        $finish;
    end

    initial begin
        repeat (100_000) @(posedge sys_clk);
        $display("BLE_RTL_SIM_TIMEOUT pass_state=%0d timeout_state=%0d",
                 pass_state, timeout_state);
        $finish;
    end

endmodule
