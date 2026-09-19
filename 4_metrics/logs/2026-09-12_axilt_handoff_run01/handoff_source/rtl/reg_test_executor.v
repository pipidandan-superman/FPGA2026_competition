//====================================================================
// File name   : reg_test_executor.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Independent PS-PL AXI-Lite register test
// Target      : FPGA
// Revision    : V1.0
//====================================================================
module reg_test_executor (
    input  wire        clk       ,
    input  wire        resetn    ,
    input  wire        start     ,
    input  wire [31:0] test_input,
    output reg         done      ,
    output reg  [31:0] result
);
    localparam [1:0] STATE_IDLE = 0, STATE_EXECUTE = 1, STATE_DONE = 2;
    reg [1:0] state, next_state;
    reg [31:0] input_snapshot;
    reg [3:0] wait_count;

    always @(posedge clk) begin
        if (!resetn) state <= STATE_IDLE;
        else state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE: if (start) next_state = STATE_EXECUTE;
            STATE_EXECUTE: if (wait_count == 0) next_state = STATE_DONE;
            STATE_DONE: next_state = STATE_IDLE;
            default: next_state = STATE_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!resetn) begin
            input_snapshot <= 0;
            wait_count <= 0;
            done <= 0;
            result <= 0;
        end else begin
            done <= 0;
            case (state)
                STATE_IDLE: if (start) begin
                    input_snapshot <= test_input;
                    wait_count <= 15;
                end
                STATE_EXECUTE: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else result <= ~input_snapshot;
                end
                STATE_DONE: done <= 1;
                default: begin
                    wait_count <= 0;
                    result <= 0;
                end
            endcase
        end
    end
endmodule

