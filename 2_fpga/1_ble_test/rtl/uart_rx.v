//====================================================================
// File name   : uart_rx.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Parameterized 8N1 UART receiver with stop-bit checking
// Target      : Xilinx 7-series FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 9_600
) (
    input  wire       clk_i         ,
    input  wire       rst_n_i       ,
    input  wire       rx_i          ,
    output reg  [7:0] data_o        ,
    output reg        done_o        ,
    output reg        frame_error_o
);

    localparam integer CLOCKS_PER_BIT =
        (CLOCK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer HALF_BIT_CLOCKS = CLOCKS_PER_BIT / 2;

    localparam [2:0] STATE_IDLE  = 3'd0;
    localparam [2:0] STATE_START = 3'd1;
    localparam [2:0] STATE_DATA  = 3'd2;
    localparam [2:0] STATE_STOP  = 3'd3;

    reg [2:0]  current_state;
    reg [2:0]  next_state;
    reg [31:0] sample_counter;
    reg [2:0]  bit_index;
    reg [7:0]  data_latch;
    reg        rx_meta;
    reg        rx_sync;

    wire start_sample_tick;
    wire data_sample_tick;

    assign start_sample_tick =
        (sample_counter == (HALF_BIT_CLOCKS - 1));
    assign data_sample_tick =
        (sample_counter == (CLOCKS_PER_BIT - 1));

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
                if (!rx_sync) begin
                    next_state = STATE_START;
                end
            end

            STATE_START: begin
                if (start_sample_tick) begin
                    if (!rx_sync) begin
                        next_state = STATE_DATA;
                    end else begin
                        next_state = STATE_IDLE;
                    end
                end
            end

            STATE_DATA: begin
                if (data_sample_tick && (bit_index == 3'd7)) begin
                    next_state = STATE_STOP;
                end
            end

            STATE_STOP: begin
                if (data_sample_tick) begin
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
            rx_meta        <= 1'b1;
            rx_sync        <= 1'b1;
            sample_counter <= 32'd0;
            bit_index      <= 3'd0;
            data_latch     <= 8'd0;
            data_o         <= 8'd0;
            done_o         <= 1'b0;
            frame_error_o  <= 1'b0;
        end else begin
            rx_meta       <= rx_i;
            rx_sync       <= rx_meta;
            done_o        <= 1'b0;
            frame_error_o <= 1'b0;

            case (current_state)
                STATE_IDLE: begin
                    sample_counter <= 32'd0;
                    bit_index      <= 3'd0;
                end

                STATE_START: begin
                    if (start_sample_tick) begin
                        sample_counter <= 32'd0;
                    end else begin
                        sample_counter <= sample_counter + 1'b1;
                    end
                end

                STATE_DATA: begin
                    if (data_sample_tick) begin
                        sample_counter       <= 32'd0;
                        data_latch[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            data_o    <= {rx_sync, data_latch[6:0]};
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        sample_counter <= sample_counter + 1'b1;
                    end
                end

                STATE_STOP: begin
                    if (data_sample_tick) begin
                        sample_counter <= 32'd0;
                        if (rx_sync) begin
                            done_o <= 1'b1;
                        end else begin
                            frame_error_o <= 1'b1;
                        end
                    end else begin
                        sample_counter <= sample_counter + 1'b1;
                    end
                end

                default: begin
                    sample_counter <= 32'd0;
                    bit_index      <= 3'd0;
                    data_latch     <= 8'd0;
                    data_o         <= 8'd0;
                end
            endcase
        end
    end

endmodule
