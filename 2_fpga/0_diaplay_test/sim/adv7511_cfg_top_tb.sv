//====================================================================
// File name   : adv7511_cfg_top_tb.sv
// Author      : LSL
// Create date : 2026-09-05
// Description : ADV7511 write/readback self-checking I2C testbench
// Target      : ModelSim
// Revision    : V2.3
//====================================================================

`timescale 1ns / 1ps

module adv7511_cfg_top_tb #(
    parameter bit INJECT_READBACK_ERROR = 1'b0
);

    localparam int unsigned CLK_HALF_PERIOD_NS    = 20;
    localparam int unsigned IIC_CLOCK_DIVIDER     = 252;
    localparam int unsigned SIMULATION_TIMEOUT_NS = 20_000_000;
    localparam int unsigned CORRUPT_READ_INDEX    = 2;
    logic [47:0] expected_readback;
    logic [47:0] expected_readback_corrupt;

    reg        clk_i;
    reg        rst_n_i;
    reg        sda_drive_low_tb;
    wire       cfg_done;
    wire       cfg_error;
    wire [5:0] readback_match;
    wire [47:0] readback_data;
    wire       scl;
    wire       sda;

    reg [7:0] register_model [0:255];
    integer model_index;
    integer write_index;
    integer read_index;
    integer failure_count;
    integer completed_transactions;
    integer start_count;
    integer stop_count;
    integer result_file;
    realtime first_start_time;

    assign sda = sda_drive_low_tb ? 1'b0 : 1'bz;
    pullup(scl);
    pullup(sda);

    adv7511_cfg_top #(
        .FAST_SIM            (1'b1)              ,
        .ENABLE_READBACK     (1'b1)              ,
        .CLK_FREQ_HZ         (25_175_000)        ,
        .POWER_UP_DELAY_MS   (1)                 ,
        .DEVICE_ADDR         (7'h39)             ,
        .IIC_CLOCK_DIVIDER   (IIC_CLOCK_DIVIDER) ,
        .PROTOCOL_TIMEOUT_MS (2)
    ) u_dut (
        .clk_i             (clk_i)          ,
        .rst_n_i           (rst_n_i)        ,
        .cfg_done_o        (cfg_done)       ,
        .cfg_error_o       (cfg_error)      ,
        .readback_match_o  (readback_match) ,
        .readback_data_o   (readback_data)  ,
        .scl_o             (scl)            ,
        .sda_io            (sda)
    );

    always #CLK_HALF_PERIOD_NS clk_i = ~clk_i;

    task automatic wait_for_start;
        begin : wait_for_start_block
            forever begin
                @(negedge sda);
                if (scl === 1'b1) begin
                    start_count = start_count + 1;
                    if (first_start_time == 0.0) begin
                        first_start_time = $realtime;
                    end
                    disable wait_for_start_block;
                end
            end
        end
    endtask

    task automatic wait_for_stop;
        begin : wait_for_stop_block
            forever begin
                @(posedge sda);
                if (scl === 1'b1) begin
                    stop_count = stop_count + 1;
                    completed_transactions = completed_transactions + 1;
                    disable wait_for_stop_block;
                end
            end
        end
    endtask

    task automatic receive_byte(output logic [7:0] received_byte);
        integer bit_index;
        begin
            received_byte = 8'd0;
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                @(posedge scl);
                #1;
                received_byte[bit_index] = sda;
            end
        end
    endtask

    task automatic drive_ack;
        begin
            @(negedge scl);
            sda_drive_low_tb = 1'b1;
            @(negedge scl);
            sda_drive_low_tb = 1'b0;
        end
    endtask

    task automatic send_byte(input logic [7:0] transmit_byte);
        integer bit_index;
        begin
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                sda_drive_low_tb = (transmit_byte[bit_index] == 1'b0);
                @(posedge scl);
                @(negedge scl);
            end

            sda_drive_low_tb = 1'b0;
            @(posedge scl);
            #1;
            if (sda !== 1'b1) begin
                failure_count = failure_count + 1;
                $error("Master did not send NACK after read byte");
            end
            @(negedge scl);
        end
    endtask

    task automatic check_byte(
        input logic [7:0] actual_byte      ,
        input logic [7:0] expected_byte    ,
        input integer     byte_kind        ,
        input integer     transaction_index
    );
        begin
            if (actual_byte !== expected_byte) begin
                failure_count = failure_count + 1;
                case (byte_kind)
                    0: $error("Write device mismatch at transaction %0d: actual=%02h expected=%02h",
                              transaction_index, actual_byte, expected_byte);
                    1: $error("Write register mismatch at transaction %0d: actual=%02h expected=%02h",
                              transaction_index, actual_byte, expected_byte);
                    2: $error("Write data mismatch at transaction %0d: actual=%02h expected=%02h",
                              transaction_index, actual_byte, expected_byte);
                    3: $error("Read-pointer device mismatch at transaction %0d: actual=%02h expected=%02h",
                              transaction_index, actual_byte, expected_byte);
                    4: $error("Read register mismatch at transaction %0d: actual=%02h expected=%02h",
                              transaction_index, actual_byte, expected_byte);
                    default: $error("Read device mismatch at transaction %0d: actual=%02h expected=%02h",
                                    transaction_index, actual_byte, expected_byte);
                endcase
            end
        end
    endtask

    initial begin : i2c_slave_model
        logic [7:0] device_byte;
        logic [7:0] register_byte;
        logic [7:0] write_byte;
        logic [7:0] read_byte;

        wait (rst_n_i == 1'b1);

        for (write_index = 0;
             write_index <= u_dut.u_adv7511_iic_data_xfer.table_last_init_index;
             write_index = write_index + 1) begin
            wait_for_start();
            receive_byte(device_byte);
            drive_ack();
            receive_byte(register_byte);
            drive_ack();
            receive_byte(write_byte);
            drive_ack();

            check_byte(device_byte, 8'h72, 0, write_index);
            check_byte(register_byte,
                       u_dut.u_adv7511_iic_data_xfer.table_init_address,
                       1, write_index);
            check_byte(write_byte,
                       u_dut.u_adv7511_iic_data_xfer.table_init_data,
                       2, write_index);

            register_model[register_byte] = write_byte;
            wait_for_stop();
        end

        for (read_index = 0;
             read_index <= u_dut.u_adv7511_iic_data_xfer.table_last_readback_index;
             read_index = read_index + 1) begin
            wait_for_start();
            receive_byte(device_byte);
            drive_ack();
            receive_byte(register_byte);
            drive_ack();

            check_byte(device_byte, 8'h72, 3, read_index);
            check_byte(register_byte,
                       u_dut.u_adv7511_iic_data_xfer.table_readback_address,
                       4, read_index);

            wait_for_start();
            receive_byte(device_byte);
            drive_ack();
            check_byte(device_byte, 8'h73, 5, read_index);

            read_byte = register_model[register_byte];
            if ((INJECT_READBACK_ERROR == 1'b1) &&
                (read_index == CORRUPT_READ_INDEX)) begin
                // Corrupt R0x16 depth/style bit 4, which is inside mask 0x30.
                // Corrupt R0x16[5], inside the 0x30 depth/style check mask.
                read_byte = read_byte ^ 8'h20;
            end
            send_byte(read_byte);
            wait_for_stop();

            $display("READBACK[%0d]: reg=%02h sent=%02h captured=%02h expected=%02h mask=%02h",
                     read_index,
                     register_byte,
                     read_byte,
                     u_dut.u_adv7511_iic_data_xfer.captured_read_data,
                     u_dut.u_adv7511_iic_data_xfer.table_readback_expected,
                     u_dut.u_adv7511_iic_data_xfer.table_readback_mask);

        end
    end

    initial begin
        clk_i                  = 1'b0;
        rst_n_i                = 1'b0;
        sda_drive_low_tb       = 1'b0;
        failure_count          = 0;
        completed_transactions = 0;
        start_count            = 0;
        stop_count             = 0;
        first_start_time       = 0.0;

        for (model_index = 0; model_index < 256; model_index = model_index + 1) begin
            register_model[model_index] = 8'd0;
        end

        repeat (4) @(negedge clk_i);
        rst_n_i = 1'b1;

        wait ((cfg_done == 1'b1) || (cfg_error == 1'b1) ||
              ($realtime > SIMULATION_TIMEOUT_NS));
        repeat (10) @(posedge clk_i);

        // Raw checks retain the written register value. The success and
        // mismatch cases therefore derive this aggregate after the run.
        expected_readback = {
            register_model[8'hDE],
            register_model[8'hAF],
            register_model[8'h48],
            register_model[8'h16],
            register_model[8'h15],
            register_model[8'h41]
        };
        expected_readback_corrupt =
            expected_readback ^ (48'h20 << (8 * CORRUPT_READ_INDEX));

        if (first_start_time < 1_000_000) begin
            failure_count = failure_count + 1;
            $error("I2C start occurred before the required power-up delay: %0t",
                   first_start_time);
        end

        if (INJECT_READBACK_ERROR == 1'b0) begin
            if ((cfg_done !== 1'b1) || (cfg_error !== 1'b0)) begin
                failure_count = failure_count + 1;
                $error("Success case status mismatch: done=%b error=%b",
                       cfg_done, cfg_error);
            end
            if (readback_match !== 6'b11_1111) begin
                failure_count = failure_count + 1;
                $error("Success case readback bitmap mismatch: %b", readback_match);
            end
            // The bus packs the first readback byte at bit 0, so the display
            // literal is written from the final AF read down to the first 41 read.
            if (readback_data !== expected_readback) begin
                failure_count = failure_count + 1;
                $error("Success case raw readback mismatch: %012h", readback_data);
            end
            if (completed_transactions !=
                (u_dut.u_adv7511_iic_data_xfer.table_last_init_index +
                 u_dut.u_adv7511_iic_data_xfer.table_last_readback_index + 2)) begin
                failure_count = failure_count + 1;
                $error("Success transaction count mismatch: %0d", completed_transactions);
            end
        end else begin
            if ((cfg_done !== 1'b0) || (cfg_error !== 1'b1)) begin
                failure_count = failure_count + 1;
                $error("Mismatch case status mismatch: done=%b error=%b",
                       cfg_done, cfg_error);
            end
            if (readback_match !== 6'b11_1011) begin
                failure_count = failure_count + 1;
                $error("Mismatch case readback bitmap mismatch: %b", readback_match);
            end
            if (readback_data !== expected_readback_corrupt) begin
                failure_count = failure_count + 1;
                $error("Mismatch case raw readback mismatch: %012h", readback_data);
            end
            if (completed_transactions !=
                (u_dut.u_adv7511_iic_data_xfer.table_last_init_index +
                 u_dut.u_adv7511_iic_data_xfer.table_last_readback_index + 2)) begin
                failure_count = failure_count + 1;
                $error("Mismatch transaction count mismatch: %0d", completed_transactions);
            end
        end

        if (failure_count == 0) begin
            if (INJECT_READBACK_ERROR == 1'b0) begin
                result_file = $fopen({
                    "E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/",
                    "cfg_success_result.txt"},
                    "w"
                );
                $fdisplay(result_file,
                          "CFG_READBACK_SUCCESS_PASS: transactions=%0d starts=%0d stops=%0d bitmap=%b raw=%012h",
                          completed_transactions,
                          start_count,
                          stop_count,
                          readback_match,
                          readback_data);
                $fclose(result_file);
                $display("CFG_READBACK_SUCCESS_PASS: transactions=%0d starts=%0d stops=%0d bitmap=%b",
                         completed_transactions, start_count, stop_count, readback_match);
            end else begin
                result_file = $fopen({
                    "E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/",
                    "cfg_mismatch_result.txt"},
                    "w"
                );
                $fdisplay(result_file,
                          "CFG_READBACK_MISMATCH_PASS: transactions=%0d bitmap=%b raw=%012h",
                          completed_transactions,
                          readback_match,
                          readback_data);
                $fclose(result_file);
                $display("CFG_READBACK_MISMATCH_PASS: transactions=%0d bitmap=%b",
                         completed_transactions, readback_match);
            end
        end else begin
            $fatal(1, "CFG_READBACK_TEST_FAIL: failures=%0d", failure_count);
        end

        $finish;
    end

endmodule

module adv7511_cfg_top_success_tb;

    adv7511_cfg_top_tb #(
        .INJECT_READBACK_ERROR(1'b0)
    ) u_test ();

endmodule

module adv7511_cfg_top_mismatch_tb;

    adv7511_cfg_top_tb #(
        .INJECT_READBACK_ERROR(1'b1)
    ) u_test ();

endmodule
