//====================================================================
// File name   : adv7511_cfg_top_nack_tb.sv
// Author      : LSL / Codex
// Create date : 2026-09-05
// Description : Verify immediate ADV7511 configuration failure on address NACK
// Target      : ModelSim
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module adv7511_cfg_top_nack_tb;

    localparam integer CLK_HALF_PERIOD_NS = 20;
    localparam integer ERROR_LIMIT_NS      = 1_100_000;

    reg         clk_i;
    reg         rst_n_i;
    wire        cfg_done;
    wire        cfg_error;
    wire [5:0]  readback_match;
    wire [47:0] readback_data;
    wire        scl;
    wire        sda;

    realtime error_time;
    integer  result_file;

    pullup (scl);
    pullup (sda);

    adv7511_cfg_top #(
        .FAST_SIM            (1'b1)      ,
        .ENABLE_READBACK     (1'b1)      ,
        .CLK_FREQ_HZ         (25_175_000),
        .POWER_UP_DELAY_MS   (1)         ,
        .DEVICE_ADDR         (7'h39)     ,
        .IIC_CLOCK_DIVIDER   (4)         ,
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

    initial begin
        clk_i   = 1'b0;
        rst_n_i = 1'b0;

        repeat (4) @(posedge clk_i);
        rst_n_i = 1'b1;

        wait (cfg_error == 1'b1);
        error_time = $realtime;

        if (cfg_done !== 1'b0) begin
            $fatal(1, "CFG_NACK_TEST_FAIL: cfg_done unexpectedly asserted");
        end

        if (error_time > ERROR_LIMIT_NS) begin
            $fatal(1, "CFG_NACK_TEST_FAIL: error was not immediate, time=%0t", error_time);
        end

        if ((scl !== 1'b1) || (sda !== 1'b1)) begin
            $fatal(1, "CFG_NACK_TEST_FAIL: bus not released, scl=%b sda=%b", scl, sda);
        end

        result_file = $fopen({
            "E:/competition/4_metrics/logs/2026-09-05_adv7511_i2c_rewrite_run01/",
            "cfg_nack_result.txt"},
            "w"
        );
        $fdisplay(result_file, "CFG_NACK_FAST_ERROR_PASS: error_time=%0t", error_time);
        $fclose(result_file);
        $display("CFG_NACK_FAST_ERROR_PASS: error_time=%0t", error_time);
        $finish;
    end

endmodule
