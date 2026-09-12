//====================================================================
// File name   : ble_at_test_ctrl.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Power-up, AT command, response, and timeout controller
// Target      : Xilinx 7-series FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module ble_at_test_ctrl #(
    parameter integer CLOCK_FREQ_HZ       = 100_000_000,
    parameter integer POWER_DELAY_MS      = 100,
    parameter integer STARTUP_DELAY_MS    = 1_000,
    parameter integer RESPONSE_TIMEOUT_MS = 500,
    parameter integer SEND_CRLF           = 1
) (
    input  wire       clk_i              ,
    input  wire       rst_n_i            ,
    input  wire       tx_done_i          ,
    input  wire [7:0] rx_data_i          ,
    input  wire       rx_done_i          ,
    output reg  [7:0] tx_data_o          ,
    output reg        tx_start_o         ,
    output reg        bt_power_enable_o  ,
    output reg        bt_reset_n_o       ,
    output reg        test_pass_o        ,
    output reg        test_fail_o        ,
    output reg        response_seen_o    ,
    output reg        test_timeout_o     ,
    output reg  [3:0] state_o
);

    localparam integer CLOCKS_PER_MS = CLOCK_FREQ_HZ / 1_000;
    localparam integer POWER_DELAY_CYCLES =
        CLOCKS_PER_MS * POWER_DELAY_MS;
    localparam integer STARTUP_DELAY_CYCLES =
        CLOCKS_PER_MS * STARTUP_DELAY_MS;
    localparam integer RESPONSE_TIMEOUT_CYCLES =
        CLOCKS_PER_MS * RESPONSE_TIMEOUT_MS;
    localparam [2:0] LAST_TX_INDEX = (SEND_CRLF != 0) ? 3'd3 : 3'd1;

    localparam [3:0] STATE_IDLE       = 4'd0;
    localparam [3:0] STATE_POWER_WAIT = 4'd1;
    localparam [3:0] STATE_STARTUP    = 4'd2;
    localparam [3:0] STATE_TX_START   = 4'd3;
    localparam [3:0] STATE_TX_WAIT    = 4'd4;
    localparam [3:0] STATE_RX_WAIT    = 4'd5;
    localparam [3:0] STATE_PASS       = 4'd6;
    localparam [3:0] STATE_FAIL       = 4'd7;

    reg [3:0]  current_state;
    reg [3:0]  next_state;
    reg [31:0] delay_counter;
    reg [31:0] timeout_counter;
    reg [2:0]  tx_index;
    reg        saw_letter_o;

    //----------------------------------------------------------------
    // First process: state register
    //----------------------------------------------------------------
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            current_state <= STATE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    //----------------------------------------------------------------
    // Second process: combinational next-state logic
    //----------------------------------------------------------------
    always @(*) begin
        next_state = current_state;

        case (current_state)
            STATE_IDLE: begin
                next_state = STATE_POWER_WAIT;
            end

            STATE_POWER_WAIT: begin
                if (delay_counter >= (POWER_DELAY_CYCLES - 1)) begin
                    next_state = STATE_STARTUP;
                end
            end

            STATE_STARTUP: begin
                if (delay_counter >= (STARTUP_DELAY_CYCLES - 1)) begin
                    next_state = STATE_TX_START;
                end
            end

            STATE_TX_START: begin
                next_state = STATE_TX_WAIT;
            end

            STATE_TX_WAIT: begin
                if (tx_done_i) begin
                    if (tx_index == LAST_TX_INDEX) begin
                        next_state = STATE_RX_WAIT;
                    end else begin
                        next_state = STATE_TX_START;
                    end
                end
            end

            STATE_RX_WAIT: begin
                if (rx_done_i && saw_letter_o && (rx_data_i == 8'h4b)) begin
                    next_state = STATE_PASS;
                end else if (timeout_counter >=
                             (RESPONSE_TIMEOUT_CYCLES - 1)) begin
                    next_state = STATE_FAIL;
                end
            end

            STATE_PASS: begin
                next_state = STATE_PASS;
            end

            STATE_FAIL: begin
                next_state = STATE_FAIL;
            end

            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    //----------------------------------------------------------------
    // Third process: sequential output and datapath logic
    //----------------------------------------------------------------
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tx_data_o          <= 8'h00;
            tx_start_o         <= 1'b0;
            bt_power_enable_o  <= 1'b0;
            bt_reset_n_o       <= 1'b0;
            test_pass_o        <= 1'b0;
            test_fail_o        <= 1'b0;
            response_seen_o    <= 1'b0;
            test_timeout_o     <= 1'b0;
            state_o            <= STATE_IDLE;
            delay_counter      <= 32'd0;
            timeout_counter    <= 32'd0;
            tx_index           <= 3'd0;
            saw_letter_o       <= 1'b0;
        end else begin
            tx_start_o         <= 1'b0;
            bt_power_enable_o  <= 1'b1;
            bt_reset_n_o       <= 1'b1;
            test_pass_o        <= 1'b0;
            test_fail_o        <= 1'b0;
            test_timeout_o     <= 1'b0;
            state_o            <= current_state;

            case (current_state)
                STATE_IDLE: begin
                    tx_data_o       <= 8'h00;
                    bt_reset_n_o    <= 1'b0;
                    delay_counter   <= 32'd0;
                    timeout_counter <= 32'd0;
                    tx_index        <= 3'd0;
                    saw_letter_o    <= 1'b0;
                    response_seen_o <= 1'b0;
                end

                STATE_POWER_WAIT: begin
                    bt_reset_n_o    <= 1'b0;
                    timeout_counter <= 32'd0;
                    if (delay_counter >= (POWER_DELAY_CYCLES - 1)) begin
                        delay_counter <= 32'd0;
                    end else begin
                        delay_counter <= delay_counter + 1'b1;
                    end
                end

                STATE_STARTUP: begin
                    timeout_counter <= 32'd0;
                    if (delay_counter >= (STARTUP_DELAY_CYCLES - 1)) begin
                        delay_counter <= 32'd0;
                    end else begin
                        delay_counter <= delay_counter + 1'b1;
                    end
                end

                STATE_TX_START: begin
                    delay_counter   <= 32'd0;
                    timeout_counter <= 32'd0;
                    tx_start_o      <= 1'b1;
                    case (tx_index)
                        3'd0: tx_data_o <= 8'h41;
                        3'd1: tx_data_o <= 8'h54;
                        3'd2: tx_data_o <= 8'h0d;
                        3'd3: tx_data_o <= 8'h0a;
                        default: tx_data_o <= 8'h00;
                    endcase
                end

                STATE_TX_WAIT: begin
                    timeout_counter <= 32'd0;
                    if (tx_done_i && (tx_index < LAST_TX_INDEX)) begin
                        tx_index <= tx_index + 1'b1;
                    end
                end

                STATE_RX_WAIT: begin
                    if (timeout_counter < RESPONSE_TIMEOUT_CYCLES) begin
                        timeout_counter <= timeout_counter + 1'b1;
                    end
                    if (rx_done_i) begin
                        response_seen_o <= 1'b1;
                        if (rx_data_i == 8'h4f) begin
                            saw_letter_o <= 1'b1;
                        end
                    end
                end

                STATE_PASS: begin
                    test_pass_o <= 1'b1;
                end

                STATE_FAIL: begin
                    test_fail_o    <= 1'b1;
                    test_timeout_o <= 1'b1;
                end

                default: begin
                    tx_data_o          <= 8'h00;
                    bt_reset_n_o       <= 1'b0;
                    response_seen_o    <= 1'b0;
                    delay_counter      <= 32'd0;
                    timeout_counter    <= 32'd0;
                    tx_index           <= 3'd0;
                    saw_letter_o       <= 1'b0;
                end
            endcase
        end
    end

endmodule
