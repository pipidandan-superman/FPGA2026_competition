//====================================================================
// File name   : action_command_executor.v
// Author      : Codex
// Create date : 2026-09-13
// Description : Apply an AXI action to LEDs and emit its PL UART frame
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module action_command_executor #(
    parameter integer clock_freq_hz = 50000000,
    parameter integer baud_rate     = 9600
) (
    input  wire        clk        ,
    input  wire        resetn     ,
    input  wire        start      ,
    input  wire [31:0] cmd_seq    ,
    input  wire [7:0]  action_code,
    output reg         done       ,
    output reg  [31:0] result     ,
    output reg  [31:0] error_code ,
    output wire        uart_tx    ,
    output reg  [6:0]  action_led ,
    output reg  [31:0] last_frame ,
    output wire        uart_busy
);

    localparam [2:0] STATE_IDLE   = 3'd0;
    localparam [2:0] STATE_LOAD   = 3'd1;
    localparam [2:0] STATE_LAUNCH = 3'd2;
    localparam [2:0] STATE_WAIT   = 3'd3;
    localparam [2:0] STATE_DONE   = 3'd4;

    reg [2:0]  state;
    reg [2:0]  next_state;
    reg [2:0]  byte_index;
    reg [7:0]  seq_snapshot;
    reg [7:0]  action_snapshot;
    reg [7:0]  crc_snapshot;
    reg        uart_start;
    reg [7:0]  uart_data;
    wire       uart_done;

    function [7:0] crc8_update;
        input [7:0] crc_in;
        input [7:0] data_in;
        integer bit_number;
        reg [7:0] work;
        begin
            work = crc_in ^ data_in;
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                if (work[7]) begin
                    work = (work << 1) ^ 8'h07;
                end else begin
                    work = work << 1;
                end
            end
            crc8_update = work;
        end
    endfunction

    action_uart_tx #(
        .clock_freq_hz (clock_freq_hz),
        .baud_rate     (baud_rate    )
    ) u_uart_tx (
        .clk    (clk       ),
        .resetn (resetn    ),
        .start  (uart_start),
        .data   (uart_data ),
        .tx     (uart_tx   ),
        .busy   (uart_busy ),
        .done   (uart_done )
    );

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
                    next_state = STATE_LOAD;
                end
            end
            STATE_LOAD: begin
                next_state = STATE_LAUNCH;
            end
            STATE_LAUNCH: begin
                next_state = STATE_WAIT;
            end
            STATE_WAIT: begin
                if (uart_done) begin
                    if (byte_index == 3'd6) begin
                        next_state = STATE_DONE;
                    end else begin
                        next_state = STATE_LAUNCH;
                    end
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
            byte_index     <= 3'b0;
            seq_snapshot   <= 8'b0;
            action_snapshot <= 8'b0;
            crc_snapshot   <= 8'b0;
            uart_start     <= 1'b0;
            uart_data      <= 8'b0;
            done           <= 1'b0;
            result         <= 32'b0;
            error_code     <= 32'b0;
            action_led     <= 7'b0;
            last_frame     <= 32'b0;
        end else begin
            uart_start <= 1'b0;
            done       <= 1'b0;
            case (state)
                STATE_IDLE: begin
                    byte_index <= 3'b0;
                    if (start) begin
                        seq_snapshot    <= cmd_seq[7:0];
                        action_snapshot <= action_code;
                        crc_snapshot    <= crc8_update(
                            crc8_update(
                                crc8_update(
                                    crc8_update(8'h00, 8'ha5),
                                    8'h5a),
                                cmd_seq[7:0]),
                            action_code);
                        case (action_code)
                            8'h00: action_led <= 7'b0000000;
                            8'h01: action_led <= 7'b0000001;
                            8'h02: action_led <= 7'b0000010;
                            8'h03: action_led <= 7'b0000100;
                            8'h04: action_led <= 7'b0001000;
                            8'h05: action_led <= 7'b0010000;
                            8'h06: action_led <= 7'b0100000;
                            8'h07: action_led <= 7'b1000000;
                            default: action_led <= 7'b0000000;
                        endcase
                    end
                end
                STATE_LOAD: begin
                    byte_index <= 3'b0;
                end
                STATE_LAUNCH: begin
                    case (byte_index)
                        3'd0: uart_data <= 8'ha5;
                        3'd1: uart_data <= 8'h5a;
                        3'd2: uart_data <= seq_snapshot;
                        3'd3: uart_data <= action_snapshot;
                        3'd4: uart_data <= crc_snapshot;
                        3'd5: uart_data <= 8'h0d;
                        3'd6: uart_data <= 8'h0a;
                        default: uart_data <= 8'hff;
                    endcase
                    uart_start <= 1'b1;
                end
                STATE_WAIT: begin
                    if (uart_done && (byte_index != 3'd6)) begin
                        byte_index <= byte_index + 1'b1;
                    end
                end
                STATE_DONE: begin
                    last_frame <= {8'b0, crc_snapshot, seq_snapshot, action_snapshot};
                    done       <= 1'b1;
                    result     <= {24'b0, action_snapshot};
                    error_code <= 32'b0;
                end
                default: begin
                    byte_index <= 3'b0;
                    error_code <= 32'h00000001;
                end
            endcase
        end
    end

endmodule
