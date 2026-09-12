//====================================================================
// File name   : ble_test_top.v
// Author      : Codex
// Create date : 2026-09-12
// Description : EES-331 PL Bluetooth UART AT self-test top module
// Target      : Xilinx 7-series FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module ble_test_top #(
    parameter integer CLOCK_FREQ_HZ       = 100_000_000,
    parameter integer BAUD_RATE           = 9_600,
    parameter integer POWER_DELAY_MS      = 100,
    parameter integer STARTUP_DELAY_MS    = 1_000,
    parameter integer RESPONSE_TIMEOUT_MS = 500,
    parameter integer SEND_CRLF           = 1,
    parameter integer ENABLE_ILA          = 1
) (
    input  wire       SYS_CLK         ,
    input  wire       SYS_RST_N       ,
    input  wire       BT_TX           ,
    output wire       BT_RX           ,
    output wire       FPGA_BT_3V3     ,
    output wire       BT_RESET_N      ,
    output wire       TEST_PASS       ,
    output wire       TEST_FAIL       ,
    output wire       RESPONSE_SEEN   ,
    output wire       RX_FRAME_ERROR  ,
    output wire [3:0] DEBUG_STATE
);

    wire       uart_tx_serial;
    wire       uart_rx_serial;
    wire [7:0] tx_data;
    wire [7:0] rx_data;
    wire       tx_start;
    wire       tx_busy;
    wire       tx_done;
    wire       rx_done;
    wire       rx_frame_error;
    wire       bt_power_enable;
    wire       bt_reset_n;
    wire       test_pass;
    wire       test_fail;
    wire       response_seen;
    wire       test_timeout;
    wire [3:0] test_state;

    assign uart_rx_serial = BT_TX;
    assign BT_RX          = uart_tx_serial;
    assign FPGA_BT_3V3    = bt_power_enable;
    assign BT_RESET_N     = bt_reset_n;
    assign TEST_PASS      = test_pass;
    assign TEST_FAIL      = test_fail;
    assign RESPONSE_SEEN  = response_seen;
    assign RX_FRAME_ERROR = rx_frame_error;
    assign DEBUG_STATE    = test_state;

    uart_tx #(
        .CLOCK_FREQ_HZ (CLOCK_FREQ_HZ),
        .BAUD_RATE     (BAUD_RATE)
    ) u_uart_tx (
        .clk_i   (SYS_CLK),
        .rst_n_i (SYS_RST_N),
        .data_i  (tx_data),
        .start_i (tx_start),
        .tx_o    (uart_tx_serial),
        .busy_o  (tx_busy),
        .done_o  (tx_done)
    );

    uart_rx #(
        .CLOCK_FREQ_HZ (CLOCK_FREQ_HZ),
        .BAUD_RATE     (BAUD_RATE)
    ) u_uart_rx (
        .clk_i         (SYS_CLK),
        .rst_n_i       (SYS_RST_N),
        .rx_i          (uart_rx_serial),
        .data_o        (rx_data),
        .done_o        (rx_done),
        .frame_error_o (rx_frame_error)
    );

    ble_at_test_ctrl #(
        .CLOCK_FREQ_HZ       (CLOCK_FREQ_HZ),
        .POWER_DELAY_MS      (POWER_DELAY_MS),
        .STARTUP_DELAY_MS    (STARTUP_DELAY_MS),
        .RESPONSE_TIMEOUT_MS (RESPONSE_TIMEOUT_MS),
        .SEND_CRLF           (SEND_CRLF)
    ) u_ble_at_test_ctrl (
        .clk_i             (SYS_CLK),
        .rst_n_i           (SYS_RST_N),
        .tx_done_i         (tx_done),
        .rx_data_i         (rx_data),
        .rx_done_i         (rx_done),
        .tx_data_o         (tx_data),
        .tx_start_o        (tx_start),
        .bt_power_enable_o (bt_power_enable),
        .bt_reset_n_o      (bt_reset_n),
        .test_pass_o       (test_pass),
        .test_fail_o       (test_fail),
        .response_seen_o   (response_seen),
        .test_timeout_o    (test_timeout),
        .state_o           (test_state)
    );

    generate
        if (ENABLE_ILA != 0) begin : generate_ila
            ila_0 u_ila (
                .clk     (SYS_CLK),
                .probe0  (uart_tx_serial),
                .probe1  (uart_rx_serial),
                .probe2  (tx_data),
                .probe3  (rx_data),
                .probe4  (tx_start),
                .probe5  (rx_done),
                .probe6  (tx_busy),
                .probe7  (tx_done),
                .probe8  (rx_frame_error),
                .probe9  (test_state),
                .probe10 (response_seen),
                .probe11 (test_timeout),
                .probe12 (bt_power_enable),
                .probe13 (bt_reset_n)
            );
        end
    endgenerate

endmodule
