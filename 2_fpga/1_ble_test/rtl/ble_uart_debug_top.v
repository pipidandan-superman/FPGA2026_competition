//====================================================================
// File name   : ble_uart_debug_top.v
// Author      : Codex
// Create date : 2026-09-12
// Description : PL USB UART to Bluetooth UART transparent debug bridge
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module ble_uart_debug_top #(
    parameter integer clock_freq_hz    = 100_000_000,
    parameter integer power_delay_ms   = 100,
    parameter integer startup_delay_ms = 1_000
) (
    input  wire       SYS_CLK      ,
    input  wire       SYS_RST_N    ,
    input  wire       PL_RS232_RX  ,
    input  wire       BT_TX        ,
    output reg        PL_RS232_TX  ,
    output reg        BT_RX        ,
    output reg        FPGA_BT_3V3  ,
    output reg        BT_RESET_N   ,
    output reg        BRIDGE_READY
);

    localparam [1:0] STATE_IDLE    = 2'd0;
    localparam [1:0] STATE_POWER   = 2'd1;
    localparam [1:0] STATE_STARTUP = 2'd2;
    localparam [1:0] STATE_READY   = 2'd3;
    localparam integer power_ticks_raw = (clock_freq_hz / 1_000) * power_delay_ms;
    localparam integer boot_ticks_raw  = (clock_freq_hz / 1_000) * startup_delay_ms;
    localparam integer power_ticks    = (power_ticks_raw > 0) ? power_ticks_raw : 1;
    localparam integer boot_ticks     = (boot_ticks_raw > 0) ? boot_ticks_raw : 1;

    reg [1:0]  state;
    reg [1:0]  next_state;
    reg [31:0] delay_count;
    (* ASYNC_REG = "TRUE" *) reg [1:0] host_rx_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] bt_tx_sync;

    // Independent synchronizers. No baud conversion: both UART endpoints must match.
    always @(posedge SYS_CLK or negedge SYS_RST_N) begin
        if (!SYS_RST_N) begin
            host_rx_sync <= 2'b11;
            bt_tx_sync   <= 2'b11;
        end else begin
            host_rx_sync <= {host_rx_sync[0], PL_RS232_RX};
            bt_tx_sync   <= {bt_tx_sync[0], BT_TX};
        end
    end

    // FSM process 1: state register, reset state is always IDLE.
    always @(posedge SYS_CLK or negedge SYS_RST_N) begin
        if (!SYS_RST_N) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // FSM process 2: next-state decisions only.
    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE: begin
                next_state = STATE_POWER;
            end
            STATE_POWER: begin
                if (delay_count == power_ticks - 1) begin
                    next_state = STATE_STARTUP;
                end
            end
            STATE_STARTUP: begin
                if (delay_count == boot_ticks - 1) begin
                    next_state = STATE_READY;
                end
            end
            STATE_READY: begin
                next_state = STATE_READY;
            end
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    // FSM process 3: all state outputs, UART forwarding and timer are registered.
    always @(posedge SYS_CLK or negedge SYS_RST_N) begin
        if (!SYS_RST_N) begin
            delay_count  <= 32'd0;
            PL_RS232_TX  <= 1'b1;
            BT_RX        <= 1'b1;
            FPGA_BT_3V3  <= 1'b0;
            BT_RESET_N   <= 1'b0;
            BRIDGE_READY <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    delay_count  <= 32'd0;
                    PL_RS232_TX  <= 1'b1;
                    BT_RX        <= 1'b1;
                    FPGA_BT_3V3  <= 1'b0;
                    BT_RESET_N   <= 1'b0;
                    BRIDGE_READY <= 1'b0;
                end
                STATE_POWER: begin
                    delay_count  <= (delay_count == power_ticks - 1)
                                    ? 32'd0 : delay_count + 1'b1;
                    PL_RS232_TX  <= 1'b1;
                    BT_RX        <= 1'b1;
                    FPGA_BT_3V3  <= 1'b1;
                    BT_RESET_N   <= 1'b0;
                    BRIDGE_READY <= 1'b0;
                end
                STATE_STARTUP: begin
                    delay_count  <= (delay_count == boot_ticks - 1)
                                    ? 32'd0 : delay_count + 1'b1;
                    PL_RS232_TX  <= 1'b1;
                    BT_RX        <= 1'b1;
                    FPGA_BT_3V3  <= 1'b1;
                    BT_RESET_N   <= 1'b1;
                    BRIDGE_READY <= 1'b0;
                end
                STATE_READY: begin
                    delay_count  <= 32'd0;
                    PL_RS232_TX  <= bt_tx_sync[1];
                    BT_RX        <= host_rx_sync[1];
                    FPGA_BT_3V3  <= 1'b1;
                    BT_RESET_N   <= 1'b1;
                    BRIDGE_READY <= 1'b1;
                end
                default: begin
                    delay_count  <= 32'd0;
                    PL_RS232_TX  <= 1'b1;
                    BT_RX        <= 1'b1;
                    FPGA_BT_3V3  <= 1'b0;
                    BT_RESET_N   <= 1'b0;
                    BRIDGE_READY <= 1'b0;
                end
            endcase
        end
    end

endmodule
