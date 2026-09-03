/************************************************************************
 * File Name       : adv7511_cfg_top.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : adv7511_cfg_top
 * Description     : ADV7511 configuration top level containing control,
 *                   IIC data transfer and reused low-level IIC protocol.
 * Dependencies    : adv7511_controller, adv7511_iic_data_xfer
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

module adv7511_cfg_top #(
    parameter bit          FAST_SIM             = 1'b0      ,
    parameter int unsigned CLK_FREQ_HZ          = 25_175_000,
    parameter int unsigned POWER_UP_DELAY_MS    = 120       ,
    parameter logic [6:0]  DEVICE_ADDR          = 7'h39     ,
    parameter int unsigned IIC_CLOCK_DIVIDER    = 252       ,
    parameter int unsigned PROTOCOL_TIMEOUT_MS  = 3000
) (
    input  wire clk_i      ,
    input  wire rst_n_i    ,
    output wire cfg_done_o ,
    output wire cfg_error_o,
    output wire scl_o      ,
    inout  wire sda_io
);

    wire configuration_start;
    wire data_transfer_busy;
    wire data_transfer_done;
    wire data_transfer_error;

    adv7511_controller #(
        .FAST_SIM          (FAST_SIM)        ,
        .CLK_FREQ_HZ       (CLK_FREQ_HZ)     ,
        .POWER_UP_DELAY_MS (POWER_UP_DELAY_MS)
    ) u_adv7511_controller (
        .clk_i       (clk_i)              ,
        .rst_n_i     (rst_n_i)            ,
        .xfer_done_i (data_transfer_done) ,
        .xfer_error_i(data_transfer_error),
        .start_o     (configuration_start),
        .done_o      (cfg_done_o)         ,
        .error_o     (cfg_error_o)
    );

    adv7511_iic_data_xfer #(
        .DEVICE_ADDR         (DEVICE_ADDR)        ,
        .IIC_CLOCK_DIVIDER   (IIC_CLOCK_DIVIDER)  ,
        .CLK_FREQ_HZ         (CLK_FREQ_HZ)        ,
        .PROTOCOL_TIMEOUT_MS (PROTOCOL_TIMEOUT_MS)
    ) u_adv7511_iic_data_xfer (
        .clk_i  (clk_i)               ,
        .rst_n_i(rst_n_i)             ,
        .start_i(configuration_start) ,
        .busy_o (data_transfer_busy)  ,
        .done_o (data_transfer_done)  ,
        .error_o(data_transfer_error) ,
        .scl_o  (scl_o)               ,
        .sda_io (sda_io)
    );

endmodule
