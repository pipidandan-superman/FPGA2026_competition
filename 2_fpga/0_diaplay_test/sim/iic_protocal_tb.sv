//====================================================================
// File name   : iic_protocal_tb.sv
// Author      : LSL / Codex
// Create date : 2026-09-05
// Description : Self-checking ADV7511 I2C test with FPGA-output SCL
// Target      : ModelSim
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module iic_protocal_tb;

    localparam integer CLK_HALF_PERIOD_NS = 5;
    localparam integer IIC_SPEED          = 8;

    reg        sys_clk;
    reg        sys_rst_n;
    reg        iic_start;
    reg [1:0]  iic_we;
    reg [7:0]  iic_addr;
    reg [7:0]  iic_wr_data;
    reg        slave_drive_low;
    wire [7:0] iic_rd_data;
    wire       iic_rd_data_valid;
    wire       iic_done;
    wire       scl;
    wire       sda;

    integer failure_count;
    integer start_count;
    integer stop_count;
    integer result_file;

    assign sda = slave_drive_low ? 1'b0 : 1'bz;
    pullup (scl);
    pullup (sda);

    iic_protocal #(
        .DEVICE_WR_ADDR(7'h39)   ,
        .IIC_SPEED     (IIC_SPEED)
    ) u_dut (
        .sys_clk          (sys_clk)          ,
        .sys_rst_n        (sys_rst_n)        ,
        .iic_start        (iic_start)        ,
        .iic_we           (iic_we)           ,
        .iic_addr         (iic_addr)         ,
        .iic_wr_data      (iic_wr_data)      ,
        .iic_rd_data      (iic_rd_data)      ,
        .iic_rd_data_valid(iic_rd_data_valid),
        .iic_done         (iic_done)         ,
        .scl              (scl)              ,
        .sda              (sda)
    );

    always #CLK_HALF_PERIOD_NS sys_clk = ~sys_clk;

    always @(negedge sda) begin
        if (scl === 1'b1) begin
            start_count = start_count + 1;
        end
    end

    always @(posedge sda) begin
        if (scl === 1'b1) begin
            stop_count = stop_count + 1;
        end
    end

    always @(scl or sda) begin
        if ((sys_rst_n == 1'b1) && ((scl === 1'bx) || (sda === 1'bx))) begin
            failure_count = failure_count + 1;
            $error("I2C bus contains X: scl=%b sda=%b time=%0t", scl, sda, $realtime);
        end
    end

    task automatic wait_for_start;
        begin : wait_for_start_block
            forever begin
                @(negedge sda);
                if (scl === 1'b1) begin
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
                    disable wait_for_stop_block;
                end
            end
        end
    endtask

    task automatic receive_byte(output reg [7:0] received_byte);
        integer bit_number;
        begin
            received_byte = 8'd0;
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                @(posedge scl);
                #1;
                received_byte[bit_number] = sda;
            end
        end
    endtask

    task automatic drive_ack;
        begin
            @(negedge scl);
            slave_drive_low = 1'b1;
            @(negedge scl);
            slave_drive_low = 1'b0;
        end
    endtask

    task automatic leave_nack;
        begin
            @(negedge scl);
            slave_drive_low = 1'b0;
            @(posedge scl);
            #1;
            if (sda !== 1'b1) begin
                failure_count = failure_count + 1;
                $error("Slave NACK was not observed high");
            end
            @(negedge scl);
        end
    endtask

    task automatic send_read_byte(input reg [7:0] transmit_byte);
        integer bit_number;
        begin
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                slave_drive_low = (transmit_byte[bit_number] == 1'b0);
                @(posedge scl);
                #1;
                @(negedge scl);
            end

            slave_drive_low = 1'b0;
            @(posedge scl);
            #1;
            if (sda !== 1'b1) begin
                failure_count = failure_count + 1;
                $error("Master did not NACK the single-byte read");
            end
            @(negedge scl);
        end
    endtask

    task automatic check_byte(
        input reg [7:0] actual_byte  ,
        input reg [7:0] expected_byte,
        input integer   check_id
    );
        begin
            if (actual_byte !== expected_byte) begin
                failure_count = failure_count + 1;
                $error("Byte check %0d failed: actual=%02h expected=%02h",
                       check_id, actual_byte, expected_byte);
            end
        end
    endtask

    task automatic pulse_request(
        input reg [1:0] request_we  ,
        input reg [7:0] request_addr,
        input reg [7:0] request_data
    );
        begin
            @(negedge sys_clk);
            iic_we      = request_we;
            iic_addr    = request_addr;
            iic_wr_data = request_data;
            iic_start   = 1'b1;
            @(negedge sys_clk);
            iic_start   = 1'b0;
        end
    endtask

    task automatic wait_for_result(
        input reg       expected_done ,
        input reg       expected_valid,
        input reg [7:0] expected_data
    );
        begin
            wait (iic_done == 1'b1);
            #1;

            if ((iic_done !== expected_done) ||
                (iic_rd_data_valid !== expected_valid)) begin
                failure_count = failure_count + 1;
                $error("Result mismatch: done=%b valid=%b",
                       iic_done, iic_rd_data_valid);
            end

            if ((expected_valid == 1'b1) && (iic_rd_data !== expected_data)) begin
                failure_count = failure_count + 1;
                $error("Read data mismatch: actual=%02h expected=%02h",
                       iic_rd_data, expected_data);
            end

            @(posedge sys_clk);
            wait ((scl === 1'b1) && (sda === 1'b1));
            repeat (2) @(posedge sys_clk);
        end
    endtask

    task automatic run_write_test;
        reg [7:0] device_byte;
        reg [7:0] register_byte;
        reg [7:0] data_byte;
        integer starts_before;
        integer stops_before;
        begin
            starts_before = start_count;
            stops_before  = stop_count;

            fork
                begin
                    wait_for_start();
                    receive_byte(device_byte);
                    drive_ack();
                    receive_byte(register_byte);
                    drive_ack();
                    receive_byte(data_byte);
                    drive_ack();
                    wait_for_stop();
                end

                begin
                    pulse_request(2'b00, 8'h16, 8'hBD);
                    wait_for_result(1'b1, 1'b0, 8'h00);
                end
            join

            check_byte(device_byte, 8'h72, 0);
            check_byte(register_byte, 8'h16, 1);
            check_byte(data_byte, 8'hBD, 2);

            if (((start_count - starts_before) != 1) ||
                ((stop_count - stops_before) != 1)) begin
                failure_count = failure_count + 1;
                $error("Write START/STOP count mismatch: starts=%0d stops=%0d",
                       start_count - starts_before, stop_count - stops_before);
            end
        end
    endtask

    task automatic run_read_test;
        reg [7:0] device_write_byte;
        reg [7:0] register_byte;
        reg [7:0] device_read_byte;
        integer starts_before;
        integer stops_before;
        begin
            starts_before = start_count;
            stops_before  = stop_count;

            fork
                begin
                    wait_for_start();
                    receive_byte(device_write_byte);
                    drive_ack();
                    receive_byte(register_byte);
                    drive_ack();
                    wait_for_start();
                    receive_byte(device_read_byte);
                    drive_ack();
                    send_read_byte(8'hA6);
                    wait_for_stop();
                end

                begin
                    pulse_request(2'b01, 8'h16, 8'h00);
                    wait_for_result(1'b1, 1'b1, 8'hA6);
                end
            join

            check_byte(device_write_byte, 8'h72, 3);
            check_byte(register_byte, 8'h16, 4);
            check_byte(device_read_byte, 8'h73, 5);

            if (((start_count - starts_before) != 2) ||
                ((stop_count - stops_before) != 1)) begin
                failure_count = failure_count + 1;
                $error("Read START/STOP count mismatch: starts=%0d stops=%0d",
                       start_count - starts_before, stop_count - stops_before);
            end
        end
    endtask

    task automatic run_timing_test;
        reg [7:0] device_byte;
        reg [7:0] register_byte;
        reg [7:0] data_byte;
        begin
            fork
                begin
                    wait_for_start();
                    receive_byte(device_byte);
                    drive_ack();
                    receive_byte(register_byte);
                    drive_ack();
                    receive_byte(data_byte);
                    drive_ack();
                    wait_for_stop();
                end

                begin
                    pulse_request(2'b00, 8'h48, 8'h08);
                    wait_for_result(1'b1, 1'b0, 8'h00);
                end
            join

            check_byte(device_byte, 8'h72, 6);
            check_byte(register_byte, 8'h48, 7);
            check_byte(data_byte, 8'h08, 8);
        end
    endtask

    initial begin
        sys_clk         = 1'b0;
        sys_rst_n       = 1'b0;
        iic_start       = 1'b0;
        iic_we          = 2'b00;
        iic_addr        = 8'd0;
        iic_wr_data     = 8'd0;
        slave_drive_low = 1'b0;
        failure_count   = 0;
        start_count     = 0;
        stop_count      = 0;

        repeat (5) @(posedge sys_clk);
        sys_rst_n = 1'b1;
        repeat (3) @(posedge sys_clk);

        run_write_test();
        run_read_test();
        run_timing_test();
        if (failure_count == 0) begin
            result_file = $fopen({
                "E:/competition/4_metrics/logs/2026-09-05_adv7511_i2c_original_run01/",
                "iic_protocol_result.txt"},
                "w"
            );
            $fdisplay(result_file,
                      "IIC_PROTOCOL_ALL_PASS: starts=%0d stops=%0d",
                      start_count,
                      stop_count);
            $fclose(result_file);
            $display("IIC_PROTOCOL_ALL_PASS: starts=%0d stops=%0d", start_count, stop_count);
        end else begin
            result_file = $fopen({
                "E:/competition/4_metrics/logs/2026-09-05_adv7511_i2c_original_run01/",
                "iic_protocol_result.txt"},
                "w"
            );
            $fdisplay(result_file,
                      "IIC_PROTOCOL_TEST_FAIL: failures=%0d",
                      failure_count);
            $fclose(result_file);
            $fatal(1, "IIC_PROTOCOL_TEST_FAIL: failures=%0d", failure_count);
        end

        $finish;
    end

endmodule
