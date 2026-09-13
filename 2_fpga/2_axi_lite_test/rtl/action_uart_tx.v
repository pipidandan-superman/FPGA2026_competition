//====================================================================
// File name   : action_uart_tx.v
// Author      : Codex
// Create date : 2026-09-13
// Description : Parameterized 8N1 UART transmitter for action frames
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module action_uart_tx #(
    parameter integer clock_freq_hz = 50000000,
    parameter integer baud_rate     = 9600
) (
    input  wire       clk  ,
    input  wire       resetn,
    input  wire       start,
    input  wire [7:0] data ,
    output reg        tx   ,
    output reg        busy ,
    output reg        done
);

    localparam integer clks_per_bit =
        (clock_freq_hz + (baud_rate / 2)) / baud_rate;

    localparam [2:0] STATE_IDLE  = 3'd0;
    localparam [2:0] STATE_START = 3'd1;
    localparam [2:0] STATE_DATA  = 3'd2;
    localparam [2:0] STATE_STOP  = 3'd3;
    localparam [2:0] STATE_DONE  = 3'd4;

    reg [2:0]  state;
    reg [2:0]  next_state;
    reg [31:0] baud_count;
    reg [2:0]  bit_index;
    reg [7:0]  data_latched;

    always @(posedge clk) begin
        if (!resetn) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE: begin
                if (start) begin
                    next_state = STATE_START;
                end
            end
            STATE_START: begin
                if (baud_count == clks_per_bit - 1) begin
                    next_state = STATE_DATA;
                end
            end
            STATE_DATA: begin
                if ((baud_count == clks_per_bit - 1) && (bit_index == 3'd7)) begin
                    next_state = STATE_STOP;
                end
            end
            STATE_STOP: begin
                if (baud_count == clks_per_bit - 1) begin
                    next_state = STATE_DONE;
                end
            end
            STATE_DONE: begin
                next_state = STATE_IDLE;
            end
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        if (!resetn) begin
            baud_count   <= 32'b0;
            bit_index    <= 3'b0;
            data_latched <= 8'b0;
            tx           <= 1'b1;
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                STATE_IDLE: begin
                    baud_count <= 32'b0;
                    bit_index  <= 3'b0;
                    tx         <= 1'b1;
                    busy       <= 1'b0;
                    if (start) begin
                        data_latched <= data;
                        busy         <= 1'b1;
                    end
                end
                STATE_START: begin
                    tx   <= 1'b0;
                    busy <= 1'b1;
                    if (baud_count == clks_per_bit - 1) begin
                        baud_count <= 32'b0;
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end
                STATE_DATA: begin
                    tx   <= data_latched[bit_index];
                    busy <= 1'b1;
                    if (baud_count == clks_per_bit - 1) begin
                        baud_count <= 32'b0;
                        if (bit_index != 3'd7) begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end
                STATE_STOP: begin
                    tx   <= 1'b1;
                    busy <= 1'b1;
                    if (baud_count == clks_per_bit - 1) begin
                        baud_count <= 32'b0;
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end
                STATE_DONE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;
                end
                default: begin
                    baud_count <= 32'b0;
                    bit_index  <= 3'b0;
                    tx         <= 1'b1;
                    busy       <= 1'b0;
                end
            endcase
        end
    end

endmodule
