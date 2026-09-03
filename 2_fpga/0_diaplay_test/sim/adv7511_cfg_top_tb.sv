/************************************************************************
 * File Name       : adv7511_cfg_top_tb.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : adv7511_cfg_top_tb
 * Description     : Fast self-checking testbench for the ADV7511 control,
 *                   data transfer and reused low-level IIC protocol layers.
 * Dependencies    : adv7511_cfg_top
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

`timescale 1ns / 1ps

module adv7511_cfg_top_tb #(
    parameter bit          FAST_SIM           = 1'b1,
    parameter int unsigned POWER_UP_DELAY_MS  = 1  ,
    parameter int unsigned IIC_CLOCK_DIVIDER = 4
);

    localparam int unsigned CLK_HALF_PERIOD_NS = 20;

    reg clk_i;
    reg rst_n_i;
    wire cfg_done;
    wire cfg_error;
    wire scl;
    wire sda;

    reg sda_drive_tb;
    reg sda_previous;
    reg scl_previous;
    reg ack_phase;
    reg in_transaction;
    reg [3:0] bit_count;
    reg [1:0] captured_byte_count;
    reg [7:0] shift_byte;
    reg [7:0] transaction_bytes [0:2];
    int unsigned completed_transactions;
    int unsigned expected_table_index;
    int unsigned ack_error_count;
    int unsigned compare_error_count;
    int unsigned start_count;
    int unsigned stop_count;

    assign sda = sda_drive_tb ? 1'b0 : 1'bz;
    pullup(sda);

    adv7511_cfg_top #(
        .FAST_SIM            (FAST_SIM)        ,
        .CLK_FREQ_HZ         (25_175_000)      ,
        .POWER_UP_DELAY_MS   (POWER_UP_DELAY_MS),
        .DEVICE_ADDR         (7'h39)     ,
        .IIC_CLOCK_DIVIDER   (IIC_CLOCK_DIVIDER),
        .PROTOCOL_TIMEOUT_MS (2)
    ) u_dut (
        .clk_i      (clk_i)   ,
        .rst_n_i    (rst_n_i) ,
        .cfg_done_o (cfg_done),
        .cfg_error_o(cfg_error),
        .scl_o      (scl)     ,
        .sda_io     (sda)
    );

    always #CLK_HALF_PERIOD_NS clk_i = ~clk_i;

    import adv7511_init_table_pkg::ADV7511_INIT_ENTRY_COUNT;
    import adv7511_init_table_pkg::ADV7511_INIT_TABLE;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sda_previous <= 1'b1;
            scl_previous <= 1'b0;
            ack_phase <= 1'b0;
            in_transaction <= 1'b0;
            bit_count <= 4'd0;
            captured_byte_count <= 2'd0;
            shift_byte <= 8'd0;
            sda_drive_tb <= 1'b0;
            transaction_bytes[0] <= 8'd0;
            transaction_bytes[1] <= 8'd0;
            transaction_bytes[2] <= 8'd0;
        end else begin
            sda_previous <= sda;
            scl_previous <= scl;

            if ((scl == 1'b1) && (scl_previous == 1'b1) &&
                (sda_previous == 1'b1) && (sda == 1'b0)) begin
                in_transaction <= 1'b1;
                bit_count <= 4'd0;
                captured_byte_count <= 2'd0;
                ack_phase <= 1'b0;
                start_count <= start_count + 1;
            end

            if ((scl == 1'b1) && (scl_previous == 1'b0) &&
                (in_transaction == 1'b1)) begin
                if (bit_count != 4'd8) begin
                    shift_byte <= {shift_byte[6:0], sda};
                    bit_count <= bit_count + 4'd1;
                end else begin
                    ack_phase <= 1'b1;
                    if (sda != 1'b0) begin
                        ack_error_count <= ack_error_count + 1;
                    end
                    case (captured_byte_count)
                        2'd0: transaction_bytes[0] <= shift_byte;
                        2'd1: transaction_bytes[1] <= shift_byte;
                        default: transaction_bytes[2] <= shift_byte;
                    endcase
                    captured_byte_count <= captured_byte_count + 2'd1;
                end
            end

            if ((scl == 1'b0) && (bit_count == 4'd8) && (ack_phase == 1'b0)) begin
                sda_drive_tb <= 1'b1;
            end

            if ((scl == 1'b0) && (ack_phase == 1'b1)) begin
                sda_drive_tb <= 1'b0;
                ack_phase <= 1'b0;
                bit_count <= 4'd0;
            end

            if ((scl == 1'b1) && (scl_previous == 1'b1) &&
                (sda_previous == 1'b0) && (sda == 1'b1)) begin
                stop_count <= stop_count + 1;
                if (in_transaction == 1'b1) begin
                    in_transaction <= 1'b0;
                    captured_byte_count <= 2'd0;
                    completed_transactions <= completed_transactions + 1;
                end
            end
        end
    end

    always @(posedge clk_i) begin
        if ((scl == 1'b1) && (scl_previous == 1'b1) &&
            (sda_previous == 1'b0) && (sda == 1'b1)) begin
            if ((completed_transactions == expected_table_index) &&
                (captured_byte_count == 2'd3)) begin
                if ((transaction_bytes[0] !== 8'h72) ||
                    (transaction_bytes[1] !== ADV7511_INIT_TABLE[expected_table_index].register_address) ||
                    (transaction_bytes[2] !== ADV7511_INIT_TABLE[expected_table_index].register_value)) begin
                    compare_error_count <= compare_error_count + 1;
                    $error("Config mismatch index=%0d bytes=%h %h %h",
                           expected_table_index,
                           transaction_bytes[0],
                           transaction_bytes[1],
                           transaction_bytes[2]);
                end
                expected_table_index <= expected_table_index + 1;
            end
        end
    end

    initial begin
        clk_i = 1'b0;
        rst_n_i = 1'b0;
        sda_drive_tb = 1'b0;
        sda_previous = 1'b1;
        scl_previous = 1'b0;
        ack_phase = 1'b0;
        in_transaction = 1'b0;
        bit_count = 4'd0;
        captured_byte_count = 2'd0;
        shift_byte = 8'd0;
        transaction_bytes[0] = 8'd0;
        transaction_bytes[1] = 8'd0;
        transaction_bytes[2] = 8'd0;
        completed_transactions = 0;
        expected_table_index = 0;
        ack_error_count = 0;
        compare_error_count = 0;
        start_count = 0;
        stop_count = 0;

        repeat (4) @(negedge clk_i);
        rst_n_i = 1'b1;

        wait ((cfg_done == 1'b1) || (cfg_error == 1'b1) || ($realtime > 2ms));
        if ((cfg_done != 1'b1) || (cfg_error != 1'b0)) begin
            $error("Configuration failed: done=%b error=%b", cfg_done, cfg_error);
        end
        if (completed_transactions != ADV7511_INIT_ENTRY_COUNT) begin
            $error("Transaction count mismatch: got=%0d expected=%0d",
                   completed_transactions, ADV7511_INIT_ENTRY_COUNT);
        end
        if ((ack_error_count != 0) || (compare_error_count != 0) ||
            (expected_table_index != ADV7511_INIT_ENTRY_COUNT)) begin
            $error("Configuration checks failed: ack=%0d compare=%0d checked=%0d",
                   ack_error_count, compare_error_count, expected_table_index);
        end

        if ((completed_transactions == ADV7511_INIT_ENTRY_COUNT) &&
            (ack_error_count == 0) && (compare_error_count == 0) &&
            (expected_table_index == ADV7511_INIT_ENTRY_COUNT)) begin
            $display("CFG_TEST_PASS: transactions=%0d starts=%0d stops=%0d",
                     completed_transactions, start_count, stop_count);
        end
        $finish;
    end

endmodule
