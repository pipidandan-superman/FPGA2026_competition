/************************************************************************
 * File Name       : adv7511_iic_data_xfer.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : adv7511_iic_data_xfer
 * Description     : Feeds each configuration table entry to the reused
 *                   single-byte IIC protocol engine and tracks completion.
 * Dependencies    : adv7511_init_table_pkg, iic_protocal
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

module adv7511_iic_data_xfer #(
    parameter logic [6:0]  DEVICE_ADDR          = 7'h39      ,
    parameter int unsigned IIC_CLOCK_DIVIDER    = 252        ,
    parameter int unsigned CLK_FREQ_HZ          = 25_175_000 ,
    parameter int unsigned PROTOCOL_TIMEOUT_MS  = 3000
) (
    input  wire        clk_i            ,
    input  wire        rst_n_i          ,
    input  wire        start_i          ,
    output reg         busy_o           ,
    output reg         done_o           ,
    output reg         error_o          ,
    output wire        scl_o            ,
    inout  wire        sda_io
);

    import adv7511_init_table_pkg::ADV7511_INIT_ENTRY_COUNT;
    import adv7511_init_table_pkg::ADV7511_INIT_TABLE;

    typedef enum logic [2:0] {
        STATE_IDLE  = 3'd0,
        STATE_LOAD  = 3'd1,
        STATE_START = 3'd2,
        STATE_WAIT  = 3'd3,
        STATE_NEXT  = 3'd4,
        STATE_DONE  = 3'd5,
        STATE_ERROR = 3'd6
    } data_xfer_state_t;

    localparam int unsigned LAST_TABLE_INDEX = ADV7511_INIT_ENTRY_COUNT - 1;
    localparam logic [31:0] PROTOCOL_TIMEOUT_CYCLES =
        ((64'd0 + CLK_FREQ_HZ) * PROTOCOL_TIMEOUT_MS + 64'd999) / 64'd1000;

    data_xfer_state_t state;
    data_xfer_state_t next_state;
    logic [5:0]  entry_index;
    logic [7:0]  protocol_register_address;
    logic [7:0]  protocol_write_data;
    logic        protocol_start;
    logic        protocol_done_previous;
    logic [31:0] timeout_counter;
    wire         protocol_done;

    iic_protocal #(
        .DEVICE_WR_ADDR(DEVICE_ADDR)      ,
        .IIC_SPEED     (IIC_CLOCK_DIVIDER)
    ) u_iic_protocal (
        .sys_clk          (clk_i)       ,
        .sys_rst_n        (rst_n_i)     ,
        .iic_start        (protocol_start),
        .iic_we           (2'b00)       ,
        .iic_addr         (protocol_register_address),
        .iic_wr_data      (protocol_write_data)     ,
        .iic_rd_data      ()            ,
        .iic_rd_data_valid()            ,
        .iic_done         (protocol_done),
        .scl              (scl_o)       ,
        .sda              (sda_io)
    );

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            STATE_IDLE: begin
                if (start_i == 1'b1) begin
                    next_state = STATE_LOAD;
                end
            end

            STATE_LOAD: begin
                next_state = STATE_START;
            end

            STATE_START: begin
                next_state = STATE_WAIT;
            end

            STATE_WAIT: begin
                if (protocol_done == 1'b1) begin
                    if (entry_index == LAST_TABLE_INDEX) begin
                        next_state = STATE_DONE;
                    end else begin
                        next_state = STATE_NEXT;
                    end
                end else if (timeout_counter >= PROTOCOL_TIMEOUT_CYCLES) begin
                    next_state = STATE_ERROR;
                end
            end

            STATE_NEXT: begin
                next_state = STATE_LOAD;
            end

            STATE_DONE: begin
                next_state = STATE_IDLE;
            end

            STATE_ERROR: begin
                next_state = STATE_IDLE;
            end

            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            entry_index <= 5'd0;
            protocol_register_address <= 8'd0;
            protocol_write_data <= 8'd0;
            protocol_start <= 1'b0;
            protocol_done_previous <= 1'b0;
            timeout_counter <= 32'd0;
        end else begin
            protocol_done_previous <= protocol_done;

            case (state)
                STATE_IDLE: begin
                    if (start_i == 1'b1) begin
                        entry_index <= 5'd0;
                    end
                    timeout_counter <= 32'd0;
                end

                STATE_LOAD: begin
                    protocol_register_address <= ADV7511_INIT_TABLE[entry_index].register_address;
                    protocol_write_data <= ADV7511_INIT_TABLE[entry_index].register_value;
                    timeout_counter <= 32'd0;
                end

                STATE_START: begin
                    protocol_start <= 1'b1;
                end

                STATE_WAIT: begin
                    protocol_start <= 1'b0;
                    if (protocol_done == 1'b0) begin
                        timeout_counter <= timeout_counter + 32'd1;
                    end else begin
                        timeout_counter <= 32'd0;
                    end
                end

                STATE_NEXT: begin
                    entry_index <= entry_index + 5'd1;
                end

                default: begin
                    protocol_start <= 1'b0;
                    timeout_counter <= 32'd0;
                end
            endcase
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            busy_o <= (next_state != STATE_IDLE);

            if ((state == STATE_WAIT) && (next_state == STATE_DONE)) begin
                done_o <= 1'b1;
            end else begin
                done_o <= 1'b0;
            end

            if ((state == STATE_WAIT) && (next_state == STATE_ERROR)) begin
                error_o <= 1'b1;
            end
        end
    end

endmodule
