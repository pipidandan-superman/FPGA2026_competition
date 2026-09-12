//====================================================================
// File name   : uart_tx.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Parameterized 8N1 UART transmitter
// Target      : Xilinx 7-series FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 9_600
) (
    input  wire       clk_i   ,
    input  wire       rst_n_i ,
    input  wire [7:0] data_i  ,
    input  wire       start_i ,
    output reg        tx_o    ,
    output reg        busy_o  ,
    output reg        done_o
);

    localparam integer CLOCKS_PER_BIT =
        (CLOCK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;

    localparam [2:0] STATE_IDLE  = 3'd0;
    localparam [2:0] STATE_START = 3'd1;
    localparam [2:0] STATE_DATA  = 3'd2;
    localparam [2:0] STATE_STOP  = 3'd3;

    reg [2:0]  current_state;
    reg [2:0]  next_state;
    reg [31:0] baud_counter;
    reg [2:0]  bit_index;
    reg [7:0]  data_latch;

    wire baud_tick;

    assign baud_tick = (baud_counter == (CLOCKS_PER_BIT - 1));

    //----------------------------------------------------------------
    // State register
    //----------------------------------------------------------------
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            current_state <= STATE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    //----------------------------------------------------------------
    // Next-state logic
    //----------------------------------------------------------------
    always @(*) begin
        next_state = current_state;

        case (current_state)
            STATE_IDLE: begin
                if (start_i) begin
                    next_state = STATE_START;
                end
            end

            STATE_START: begin
                if (baud_tick) begin
                    next_state = STATE_DATA;
                end
            end

            STATE_DATA: begin
                if (baud_tick && (bit_index == 3'd7)) begin
                    next_state = STATE_STOP;
                end
            end

            STATE_STOP: begin
                if (baud_tick) begin
                    next_state = STATE_IDLE;
                end
            end

            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    //----------------------------------------------------------------
    // Sequential output and datapath logic
    //----------------------------------------------------------------
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tx_o         <= 1'b1;
            busy_o       <= 1'b0;
            done_o       <= 1'b0;
            baud_counter <= 32'd0;
            bit_index    <= 3'd0;
            data_latch   <= 8'd0;
        end else begin
            done_o <= 1'b0;

            case (current_state)
                STATE_IDLE: begin
                    tx_o         <= 1'b1;
                    busy_o       <= 1'b0;
                    baud_counter <= 32'd0;
                    bit_index    <= 3'd0;
                    if (start_i) begin
                        tx_o       <= 1'b0;
                        busy_o     <= 1'b1;
                        data_latch <= data_i;
                    end
                end

                STATE_START: begin
                    tx_o   <= 1'b0;
                    busy_o <= 1'b1;
                    if (baud_tick) begin
                        tx_o         <= data_latch[0];
                        baud_counter <= 32'd0;
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                STATE_DATA: begin
                    busy_o <= 1'b1;
                    if (baud_tick) begin
                        baud_counter <= 32'd0;
                        if (bit_index == 3'd7) begin
                            tx_o      <= 1'b1;
                            bit_index <= 3'd0;
                        end else begin
                            tx_o      <= data_latch[bit_index + 1'b1];
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                STATE_STOP: begin
                    tx_o <= 1'b1;
                    if (baud_tick) begin
                        busy_o       <= 1'b0;
                        done_o       <= 1'b1;
                        baud_counter <= 32'd0;
                    end else begin
                        busy_o       <= 1'b1;
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                default: begin
                    tx_o         <= 1'b1;
                    busy_o       <= 1'b0;
                    baud_counter <= 32'd0;
                    bit_index    <= 3'd0;
                    data_latch   <= 8'd0;
                end
            endcase
        end
    end

endmodule
