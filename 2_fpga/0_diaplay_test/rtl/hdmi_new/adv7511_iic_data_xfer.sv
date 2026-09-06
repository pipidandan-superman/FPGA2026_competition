/************************************************************************
 * File Name       : adv7511_iic_data_xfer.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : adv7511_iic_data_xfer
 * Description     : Writes the ADV7511 initialization table, then reads
 *                   back and checks the critical configuration registers.
 * Dependencies    : adv7511_init_table, iic_protocal
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 *   - V1.1 (2026-09-05) by LSL : Add masked critical-register readback
 *   - V1.2 (2026-09-05) by LSL : Preserve all raw readback values and
 *                                 complete every read before reporting error
 *   - V1.3 (2026-09-05) by LSL : Restore compatibility with the original
 *                                 iic_protocal state machine
 *   - V1.4 (2026-09-05) by LSL : Match board interface with FPGA-output SCL
 *   - V1.5 (2026-09-06) by LSL : Instantiate the table module explicitly
 ************************************************************************/

module adv7511_iic_data_xfer #(
    parameter bit          ENABLE_READBACK      = 1'b1      ,
    parameter logic [6:0]  DEVICE_ADDR          = 7'h39     ,
    parameter int unsigned IIC_CLOCK_DIVIDER    = 252       ,
    parameter int unsigned CLK_FREQ_HZ          = 25_175_000,
    parameter int unsigned PROTOCOL_TIMEOUT_MS  = 3000
) (
    input  wire        clk_i            ,
    input  wire        rst_n_i          ,
    input  wire        start_i          ,
    output reg         busy_o           ,
    output reg         done_o           ,
    output reg         error_o          ,
    output reg  [ 5:0] readback_match_o ,
    output reg  [47:0] readback_data_o  ,
    output wire        scl_o            ,
    inout  wire        sda_io
);

    typedef enum logic [3:0] {
        STATE_IDLE        = 4'd0 ,
        STATE_WRITE_LOAD  = 4'd1 ,
        STATE_WRITE_START = 4'd2 ,
        STATE_WRITE_WAIT  = 4'd3 ,
        STATE_WRITE_NEXT  = 4'd4 ,
        STATE_READ_LOAD   = 4'd5 ,
        STATE_READ_START  = 4'd6 ,
        STATE_READ_WAIT   = 4'd7 ,
        STATE_READ_CHECK  = 4'd8 ,
        STATE_READ_NEXT   = 4'd9 ,
        STATE_DONE        = 4'd10,
        STATE_ERROR       = 4'd11
    } data_xfer_state_t;

    localparam logic [31:0] PROTOCOL_TIMEOUT_CYCLES =
        ((64'd0 + CLK_FREQ_HZ) * PROTOCOL_TIMEOUT_MS + 64'd999) / 64'd1000;

    data_xfer_state_t state;
    data_xfer_state_t next_state;

    logic [6:0]  write_index;
    logic [2:0]  read_index;
    logic [7:0]  protocol_register_address;
    logic [7:0]  protocol_write_data;
    logic [1:0]  protocol_write_enable;
    logic        protocol_start;
    logic [7:0]  protocol_read_data;
    logic        protocol_read_data_valid;
    logic        protocol_done;
    logic [7:0]  captured_read_data;
    logic [31:0] timeout_counter;
    logic        current_read_matches;
    logic        readback_error_seen;
    logic [7:0]  table_init_address;
    logic [7:0]  table_init_data;
    logic [7:0]  table_readback_address;
    logic [7:0]  table_readback_expected;
    logic [7:0]  table_readback_mask;
    logic [6:0]  table_last_init_index;
    logic [2:0]  table_last_readback_index;

    assign current_read_matches =
        ((captured_read_data & table_readback_mask) ==
         (table_readback_expected & table_readback_mask));

    adv7511_init_table u_adv7511_init_table (
        .init_index_i          (write_index)               ,
        .readback_index_i      (read_index)                ,
        .init_address_o        (table_init_address)        ,
        .init_data_o           (table_init_data)           ,
        .readback_address_o    (table_readback_address)    ,
        .readback_expected_o   (table_readback_expected)   ,
        .readback_mask_o       (table_readback_mask)       ,
        .last_init_index_o     (table_last_init_index)     ,
        .last_readback_index_o (table_last_readback_index)
    );

    iic_protocal #(
        .DEVICE_WR_ADDR (DEVICE_ADDR)       ,
        .IIC_SPEED      (IIC_CLOCK_DIVIDER)
    ) u_iic_protocal (
        .sys_clk          (clk_i)                    ,
        .sys_rst_n        (rst_n_i)                  ,
        .iic_start        (protocol_start)           ,
        .iic_we           (protocol_write_enable)    ,
        .iic_addr         (protocol_register_address),
        .iic_wr_data      (protocol_write_data)      ,
        .iic_rd_data      (protocol_read_data)       ,
        .iic_rd_data_valid(protocol_read_data_valid) ,
        .iic_done         (protocol_done)            ,
        .scl              (scl_o)                    ,
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
                    next_state = STATE_WRITE_LOAD;
                end
            end

            STATE_WRITE_LOAD: begin
                next_state = STATE_WRITE_START;
            end

            STATE_WRITE_START: begin
                next_state = STATE_WRITE_WAIT;
            end

            STATE_WRITE_WAIT: begin
                if (protocol_done == 1'b1) begin
                if (write_index == table_last_init_index) begin
                        if (ENABLE_READBACK == 1'b1) begin
                            next_state = STATE_READ_LOAD;
                        end else begin
                            next_state = STATE_DONE;
                        end
                    end else begin
                        next_state = STATE_WRITE_NEXT;
                    end
                end else if (timeout_counter >= PROTOCOL_TIMEOUT_CYCLES) begin
                    next_state = STATE_ERROR;
                end
            end

            STATE_WRITE_NEXT: begin
                next_state = STATE_WRITE_LOAD;
            end

            STATE_READ_LOAD: begin
                next_state = STATE_READ_START;
            end

            STATE_READ_START: begin
                next_state = STATE_READ_WAIT;
            end

            STATE_READ_WAIT: begin
                if (protocol_done == 1'b1) begin
                    next_state = STATE_READ_CHECK;
                end else if (timeout_counter >= PROTOCOL_TIMEOUT_CYCLES) begin
                    next_state = STATE_ERROR;
                end
            end

            STATE_READ_CHECK: begin
                if (read_index == table_last_readback_index) begin
                    if ((current_read_matches == 1'b0) ||
                        (readback_error_seen == 1'b1)) begin
                        next_state = STATE_ERROR;
                    end else begin
                        next_state = STATE_DONE;
                    end
                end else begin
                    next_state = STATE_READ_NEXT;
                end
            end

            STATE_READ_NEXT: begin
                next_state = STATE_READ_LOAD;
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

    always @(*) begin
        busy_o         = 1'b0;
        done_o         = 1'b0;
        error_o        = 1'b0;
        protocol_start = 1'b0;

        case (state)
            STATE_WRITE_LOAD,
            STATE_WRITE_START,
            STATE_WRITE_WAIT,
            STATE_WRITE_NEXT,
            STATE_READ_LOAD,
            STATE_READ_START,
            STATE_READ_WAIT,
            STATE_READ_CHECK,
            STATE_READ_NEXT: begin
                busy_o = 1'b1;
            end

            STATE_DONE: begin
                done_o = 1'b1;
            end

            STATE_ERROR: begin
                error_o = 1'b1;
            end

            default: begin
                busy_o  = 1'b0;
                done_o  = 1'b0;
                error_o = 1'b0;
            end
        endcase

        if ((state == STATE_WRITE_START) || (state == STATE_READ_START)) begin
            protocol_start = 1'b1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_index               <= 7'd0;
            read_index                <= 3'd0;
            protocol_register_address <= 8'd0;
            protocol_write_data       <= 8'd0;
            protocol_write_enable     <= 2'b00;
            captured_read_data        <= 8'd0;
            timeout_counter           <= 32'd0;
            readback_match_o          <= 6'd0;
            readback_data_o           <= 48'd0;
            readback_error_seen       <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    timeout_counter <= 32'd0;
                    if (start_i == 1'b1) begin
                        write_index         <= 7'd0;
                        read_index          <= 3'd0;
                        readback_match_o    <= 6'd0;
                        readback_data_o     <= 48'd0;
                        readback_error_seen <= 1'b0;
                    end
                end

                STATE_WRITE_LOAD: begin
                    protocol_register_address <= table_init_address;
                    protocol_write_data       <= table_init_data;
                    protocol_write_enable <= 2'b00;
                    timeout_counter <= 32'd0;
                end

                STATE_WRITE_WAIT: begin
                    if (protocol_done == 1'b1) begin
                        timeout_counter <= 32'd0;
                    end else begin
                        timeout_counter <= timeout_counter + 32'd1;
                    end
                end

                STATE_WRITE_NEXT: begin
                    write_index <= write_index + 7'd1;
                end

                STATE_READ_LOAD: begin
                    protocol_register_address <= table_readback_address;
                    protocol_write_data   <= 8'd0;
                    protocol_write_enable <= 2'b01;
                    captured_read_data    <= 8'd0;
                    timeout_counter       <= 32'd0;
                end

                STATE_READ_WAIT: begin
                    if (protocol_read_data_valid == 1'b1) begin
                        captured_read_data <= protocol_read_data;
                    end

                    if (protocol_done == 1'b1) begin
                        timeout_counter <= 32'd0;
                    end else begin
                        timeout_counter <= timeout_counter + 32'd1;
                    end
                end

                STATE_READ_CHECK: begin
                    case (read_index)
                        3'd0: readback_data_o[ 7: 0] <= captured_read_data;
                        3'd1: readback_data_o[15: 8] <= captured_read_data;
                        3'd2: readback_data_o[23:16] <= captured_read_data;
                        3'd3: readback_data_o[31:24] <= captured_read_data;
                        3'd4: readback_data_o[39:32] <= captured_read_data;
                        3'd5: readback_data_o[47:40] <= captured_read_data;
                        default: readback_data_o <= readback_data_o;
                    endcase

                    if (current_read_matches == 1'b1) begin
                        readback_match_o[read_index] <= 1'b1;
                    end else begin
                        readback_error_seen <= 1'b1;
                    end
                end

                STATE_READ_NEXT: begin
                    read_index <= read_index + 3'd1;
                end

                default: begin
                    timeout_counter <= 32'd0;
                end
            endcase
        end
    end

endmodule
