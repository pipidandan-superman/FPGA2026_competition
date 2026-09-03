/************************************************************************
 * File Name       : adv7511_controller.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : adv7511_controller
 * Description     : Controls ADV7511 configuration power-up delay, start
 *                   handshake and completion or error status.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

module adv7511_controller #(
    parameter bit          FAST_SIM           = 1'b0      ,
    parameter int unsigned CLK_FREQ_HZ        = 25_175_000,
    parameter int unsigned POWER_UP_DELAY_MS  = 120
) (
    input  wire clk_i       ,
    input  wire rst_n_i     ,
    input  wire xfer_done_i ,
    input  wire xfer_error_i,
    output reg  start_o     ,
    output reg  done_o      ,
    output reg  error_o
);

    typedef enum logic [1:0] {
        STATE_POWER_UP = 2'd0,
        STATE_RUNNING  = 2'd1,
        STATE_DONE     = 2'd2,
        STATE_ERROR    = 2'd3
    } controller_state_t;

    localparam logic [31:0] POWER_UP_DELAY_CYCLES =
        ((64'd0 + CLK_FREQ_HZ) * (FAST_SIM ? 32'd1 : POWER_UP_DELAY_MS) + 64'd999) / 64'd1000;

    controller_state_t state;
    controller_state_t next_state;
    logic [31:0] delay_counter;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state <= STATE_POWER_UP;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            STATE_POWER_UP: begin
                if (delay_counter >= POWER_UP_DELAY_CYCLES) begin
                    next_state = STATE_RUNNING;
                end
            end

            STATE_RUNNING: begin
                if (xfer_error_i == 1'b1) begin
                    next_state = STATE_ERROR;
                end else if (xfer_done_i == 1'b1) begin
                    next_state = STATE_DONE;
                end
            end

            STATE_DONE: begin
                next_state = STATE_DONE;
            end

            STATE_ERROR: begin
                next_state = STATE_ERROR;
            end

            default: begin
                next_state = STATE_POWER_UP;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            delay_counter <= 32'd0;
        end else if ((state == STATE_POWER_UP) &&
                     (delay_counter < POWER_UP_DELAY_CYCLES)) begin
            delay_counter <= delay_counter + 32'd1;
        end else begin
            delay_counter <= 32'd0;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            start_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            if ((state == STATE_POWER_UP) && (next_state == STATE_RUNNING)) begin
                start_o <= 1'b1;
            end else begin
                start_o <= 1'b0;
            end

            if ((state == STATE_RUNNING) && (next_state == STATE_DONE)) begin
                done_o <= 1'b1;
            end

            if ((state == STATE_RUNNING) && (next_state == STATE_ERROR)) begin
                error_o <= 1'b1;
            end
        end
    end

endmodule
