/************************************************************************
 * File Name       : adv7511_i2c_init.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : adv7511_i2c_init
 * Description     : Bit-banged 100 kHz I2C master that waits for power
 *                   stabilization and writes the embedded ADV7511 table.
 * Dependencies    : adv7511_init_table_pkg
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

module adv7511_i2c_init #(
    parameter int unsigned CLK_FREQ_HZ        = 25_175_000,
    parameter int unsigned I2C_FREQ_HZ        = 100_000    ,
    parameter int unsigned POWER_UP_DELAY_MS  = 120
) (
    input  wire        clk_i     ,
    input  wire        rst_n_i   ,
    output reg         scl_o     ,
    inout  wire        sda_io    ,
    output reg         done_o    ,
    output reg         error_o
);

    import adv7511_init_table_pkg::ADV7511_INIT_ENTRY_COUNT;
    import adv7511_init_table_pkg::ADV7511_INIT_TABLE;

    typedef enum logic [2:0] {
        STATE_POWER_UP = 3'd0,
        STATE_IDLE     = 3'd1,
        STATE_START    = 3'd2,
        STATE_SEND     = 3'd3,
        STATE_ACK      = 3'd4,
        STATE_STOP     = 3'd5,
        STATE_DONE     = 3'd6
    } i2c_state_t;

    localparam int unsigned I2C_QUARTER_CYCLES =
        ((CLK_FREQ_HZ + (I2C_FREQ_HZ * 2) - 1) / (I2C_FREQ_HZ * 4));
    localparam [63:0] POWER_UP_DELAY_CYCLES =
        ((64'd0 + CLK_FREQ_HZ) * POWER_UP_DELAY_MS + 64'd999) / 64'd1000;
    localparam logic [7:0] ADV7511_WRITE_ADDRESS = 8'h72;
    localparam int unsigned LAST_TABLE_INDEX = ADV7511_INIT_ENTRY_COUNT - 1;

    i2c_state_t state;
    i2c_state_t next_state;
    logic [31:0] delay_counter;
    logic [31:0] quarter_counter;
    logic [1:0]  quarter_index;
    logic [2:0]  bit_index;
    logic [5:0]  table_index;
    logic [7:0]  current_byte;
    logic        quarter_tick;
    logic        sda_input;
    logic        sda_drive_low;
    logic        ack_nak;

    assign quarter_tick = (quarter_counter == I2C_QUARTER_CYCLES - 1);
    assign sda_input = sda_io;
    assign sda_io = sda_drive_low ? 1'b0 : 1'bz;

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
                if (delay_counter >= POWER_UP_DELAY_CYCLES[31:0]) begin
                    next_state = STATE_IDLE;
                end
            end

            STATE_IDLE: begin
                next_state = STATE_START;
            end

            STATE_START: begin
                if ((quarter_tick == 1'b1) && (quarter_index == 2'd3)) begin
                    next_state = STATE_SEND;
                end
            end

            STATE_SEND: begin
                if ((quarter_tick == 1'b1) &&
                    (quarter_index == 2'd3) &&
                    (bit_index == 3'd7)) begin
                    next_state = STATE_ACK;
                end
            end

            STATE_ACK: begin
                if ((quarter_tick == 1'b1) && (quarter_index == 2'd3)) begin
                    if ((table_index == LAST_TABLE_INDEX[4:0]) ||
                        (ack_nak == 1'b1)) begin
                        next_state = STATE_STOP;
                    end else begin
                        next_state = STATE_SEND;
                    end
                end
            end

            STATE_STOP: begin
                if ((quarter_tick == 1'b1) && (quarter_index == 2'd3)) begin
                    next_state = STATE_DONE;
                end
            end

            STATE_DONE: begin
                next_state = STATE_DONE;
            end

            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            delay_counter <= 32'd0;
            quarter_counter <= 32'd0;
            quarter_index <= 2'd0;
            bit_index <= 3'd0;
            table_index <= 6'd0;
            current_byte <= 8'd0;
            ack_nak <= 1'b0;
        end else begin
            if (delay_counter < POWER_UP_DELAY_CYCLES[31:0]) begin
                delay_counter <= delay_counter + 32'd1;
            end

            if (quarter_tick == 1'b1) begin
                quarter_counter <= 32'd0;
                if (quarter_index == 2'd3) begin
                    quarter_index <= 2'd0;
                end else begin
                    quarter_index <= quarter_index + 2'd1;
                end

                case (state)
                    STATE_START: begin
                        if (quarter_index == 2'd3) begin
                            bit_index <= 3'd0;
                        end
                    end

                    STATE_SEND: begin
                        if ((quarter_index == 2'd3) && (bit_index != 3'd7)) begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end

                    STATE_ACK: begin
                        if ((quarter_index == 2'd3) && (table_index != LAST_TABLE_INDEX[4:0])) begin
                            table_index <= table_index + 6'd1;
                            bit_index <= 3'd0;
                        end
                    end

                    default: begin
                        quarter_index <= quarter_index;
                    end
                endcase
            end else begin
                quarter_counter <= quarter_counter + 32'd1;
            end

            if ((state == STATE_START) && (next_state == STATE_SEND)) begin
                current_byte <= ADV7511_WRITE_ADDRESS;
            end

            if ((state == STATE_ACK) && (next_state == STATE_SEND)) begin
                current_byte <= ADV7511_INIT_TABLE[table_index].register_value;
            end

            if ((state == STATE_ACK) && (quarter_index == 2'd2) && (quarter_tick == 1'b0)) begin
                ack_nak <= sda_input;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            scl_o <= 1'b0;
            sda_drive_low <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            if (quarter_tick == 1'b1) begin
                case (state)
                    STATE_POWER_UP: begin
                        scl_o <= 1'b0;
                        sda_drive_low <= 1'b0;
                    end

                    STATE_IDLE: begin
                        scl_o <= 1'b0;
                        sda_drive_low <= 1'b0;
                    end

                    STATE_START: begin
                        case (quarter_index)
                            2'd0: begin
                                scl_o <= 1'b1;
                                sda_drive_low <= 1'b0;
                            end

                            2'd1: begin
                                scl_o <= 1'b1;
                                sda_drive_low <= 1'b1;
                            end

                            default: begin
                                scl_o <= 1'b0;
                                sda_drive_low <= 1'b1;
                            end
                        endcase
                    end

                    STATE_SEND: begin
                        case (quarter_index)
                            2'd0: begin
                                scl_o <= 1'b0;
                                sda_drive_low <= current_byte[3'd7-bit_index];
                            end

                            2'd1: begin
                                scl_o <= 1'b1;
                            end

                            2'd3: begin
                                scl_o <= 1'b0;
                            end

                            default: begin
                                scl_o <= scl_o;
                            end
                        endcase
                    end

                    STATE_ACK: begin
                        case (quarter_index)
                            2'd0: begin
                                scl_o <= 1'b0;
                                sda_drive_low <= 1'b0;
                            end

                            2'd1: begin
                                scl_o <= 1'b1;
                            end

                            2'd3: begin
                                scl_o <= 1'b0;
                            end

                            default: begin
                                scl_o <= scl_o;
                            end
                        endcase
                    end

                    STATE_STOP: begin
                        case (quarter_index)
                            2'd0: begin
                                scl_o <= 1'b0;
                                sda_drive_low <= 1'b1;
                            end

                            2'd1: begin
                                scl_o <= 1'b1;
                            end

                            2'd3: begin
                                scl_o <= 1'b1;
                                sda_drive_low <= 1'b0;
                            end

                            default: begin
                                scl_o <= 1'b1;
                            end
                        endcase
                    end

                    STATE_DONE: begin
                        scl_o <= 1'b1;
                        sda_drive_low <= 1'b0;
                    end

                    default: begin
                        scl_o <= 1'b0;
                        sda_drive_low <= 1'b0;
                    end
                endcase
            end

            if ((state == STATE_STOP) && (next_state == STATE_DONE)) begin
                done_o <= 1'b1;
            end

            if ((state == STATE_ACK) && (next_state == STATE_STOP) && (ack_nak == 1'b1)) begin
                error_o <= 1'b1;
            end
        end
    end

endmodule
