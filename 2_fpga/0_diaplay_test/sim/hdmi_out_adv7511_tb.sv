/************************************************************************
 * File Name       : hdmi_out_adv7511_tb.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : hdmi_out_adv7511_tb
 * Description     : Self-checking testbench for 480p60 video alignment,
 *                   YCbCr packing, ADV7511 I2C delay and write sequence.
 * Dependencies    : hdmi_out_adv7511
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

`timescale 1ns / 1ps

module hdmi_out_adv7511_tb #(
    parameter bit FAST_SIM = 1'b0
);

    localparam int unsigned CLK_HALF_PERIOD_NS = 20;
    localparam int unsigned TEST_PIXEL_COUNT = 16;
    localparam int unsigned PIX_CLK_MODEL_HZ = 25_175_000;
    localparam int unsigned I2C_DELAY_MIN_NS = FAST_SIM ? 1_000_000 : 100_000_000;
    localparam int unsigned SIMULATION_TIMEOUT_NS = FAST_SIM ? 3_000_000 : 200_000_000;

    reg PIX_CLK;
    reg RST_N;
    reg [23:0] RGB888;
    reg DE;
    reg H_SYNC;
    reg V_SYNC;
    wire HDMI_SDA;
    wire [15:0] HDMI_DATA;
    wire HDMI_CLK;
    wire HDMI_HSYNC;
    wire HDMI_VSYNC;
    wire HDMI_DE;
    wire HDMI_SCL;

    reg sda_drive_tb;
    reg sda_previous;
    reg scl_previous;
    reg start_seen;
    reg ack_seen;
    reg [3:0] bit_count;
    reg [7:0] shift_byte;
    reg [7:0] write_address;
    reg [7:0] write_register;
    reg [7:0] write_value;
    int unsigned completed_writes;
    int unsigned input_pixel_count;
    int unsigned checked_pixels;
    realtime first_start_time;
    reg first_start_seen;

    reg [23:0] rgb_pipe [0:4];
    reg de_pipe [0:4];
    reg hsync_pipe [0:4];
    reg vsync_pipe [0:4];
    reg chroma_cb_pipe [0:4];
    int unsigned pixel_index;

    assign HDMI_SDA = sda_drive_tb ? 1'b0 : 1'bz;
    pullup(HDMI_SDA);

    hdmi_out_adv7511 #(
        .FAST_SIM       (FAST_SIM)        ,
        .PIX_CLK_FREQ_HZ(PIX_CLK_MODEL_HZ)
    ) u_dut (
        .PIX_CLK   (PIX_CLK)   ,
        .RST_N     (RST_N)     ,
        .RGB888    (RGB888)    ,
        .DE        (DE)        ,
        .H_SYNC    (H_SYNC)    ,
        .V_SYNC    (V_SYNC)    ,
        .HDMI_INT  (1'b0)      ,
        .HDMI_SDA  (HDMI_SDA)  ,
        .HDMI_DATA (HDMI_DATA) ,
        .HDMI_CLK  (HDMI_CLK)  ,
        .HDMI_HSYNC(HDMI_HSYNC),
        .HDMI_VSYNC(HDMI_VSYNC),
        .HDMI_DE   (HDMI_DE)   ,
        .HDMI_SCL  (HDMI_SCL)
    );

    always #CLK_HALF_PERIOD_NS PIX_CLK = ~PIX_CLK;

    function automatic logic [7:0] clip_scaled_value (
        input int signed scaled_value
    );
        begin
            if (scaled_value < 0) begin
                clip_scaled_value = 8'd0;
            end else if (scaled_value > 1044480) begin
                clip_scaled_value = 8'd255;
            end else begin
                clip_scaled_value = scaled_value[19:12];
            end
        end
    endfunction

    function automatic logic [15:0] expected_ycbcr422 (
        input logic [23:0] rgb_value,
        input logic chroma_is_cb
    );
        int signed y_value;
        int signed cb_value;
        int signed cr_value;
        logic [7:0] y_scaled;
        logic [7:0] cb_scaled;
        logic [7:0] cr_scaled;
        begin
            y_value = 752 * rgb_value[23:16] +
                      1588 * rgb_value[15:8] +
                      254 * rgb_value[7:0] +
                      65536;
            cb_value = -412 * rgb_value[23:16] -
                       1387 * rgb_value[15:8] +
                       1799 * rgb_value[7:0] +
                       524288;
            cr_value = 1799 * rgb_value[23:16] -
                       1633 * rgb_value[15:8] -
                       165 * rgb_value[7:0] +
                       524288;
            y_scaled = clip_scaled_value(y_value);
            cb_scaled = clip_scaled_value(cb_value);
            cr_scaled = clip_scaled_value(cr_value);
            expected_ycbcr422 = chroma_is_cb ? {y_scaled, cb_scaled} :
                                                {y_scaled, cr_scaled};
        end
    endfunction

    always @(posedge PIX_CLK or negedge RST_N) begin
        if (!RST_N) begin
            rgb_pipe[0] <= 24'd0;
            rgb_pipe[1] <= 24'd0;
            rgb_pipe[2] <= 24'd0;
            rgb_pipe[3] <= 24'd0;
            rgb_pipe[4] <= 24'd0;
            de_pipe[0] <= 1'b0;
            de_pipe[1] <= 1'b0;
            de_pipe[2] <= 1'b0;
            de_pipe[3] <= 1'b0;
            de_pipe[4] <= 1'b0;
            hsync_pipe[0] <= 1'b0;
            hsync_pipe[1] <= 1'b0;
            hsync_pipe[2] <= 1'b0;
            hsync_pipe[3] <= 1'b0;
            hsync_pipe[4] <= 1'b0;
            vsync_pipe[0] <= 1'b0;
            vsync_pipe[1] <= 1'b0;
            vsync_pipe[2] <= 1'b0;
            vsync_pipe[3] <= 1'b0;
            vsync_pipe[4] <= 1'b0;
            chroma_cb_pipe[0] <= 1'b0;
            chroma_cb_pipe[1] <= 1'b0;
            chroma_cb_pipe[2] <= 1'b0;
            chroma_cb_pipe[3] <= 1'b0;
            chroma_cb_pipe[4] <= 1'b0;
            input_pixel_count <= 0;
        end else begin
            rgb_pipe[0] <= RGB888;
            de_pipe[0] <= DE;
            hsync_pipe[0] <= H_SYNC;
            vsync_pipe[0] <= V_SYNC;
            if (DE == 1'b1) begin
                chroma_cb_pipe[0] <= (input_pixel_count[0] == 1'b0);
                input_pixel_count <= input_pixel_count + 1;
            end else begin
                chroma_cb_pipe[0] <= 1'b0;
            end
            rgb_pipe[1] <= rgb_pipe[0];
            rgb_pipe[2] <= rgb_pipe[1];
            rgb_pipe[3] <= rgb_pipe[2];
            rgb_pipe[4] <= rgb_pipe[3];
            de_pipe[1] <= de_pipe[0];
            de_pipe[2] <= de_pipe[1];
            de_pipe[3] <= de_pipe[2];
            de_pipe[4] <= de_pipe[3];
            hsync_pipe[1] <= hsync_pipe[0];
            hsync_pipe[2] <= hsync_pipe[1];
            hsync_pipe[3] <= hsync_pipe[2];
            hsync_pipe[4] <= hsync_pipe[3];
            vsync_pipe[1] <= vsync_pipe[0];
            vsync_pipe[2] <= vsync_pipe[1];
            vsync_pipe[3] <= vsync_pipe[2];
            vsync_pipe[4] <= vsync_pipe[3];
            chroma_cb_pipe[1] <= chroma_cb_pipe[0];
            chroma_cb_pipe[2] <= chroma_cb_pipe[1];
            chroma_cb_pipe[3] <= chroma_cb_pipe[2];
            chroma_cb_pipe[4] <= chroma_cb_pipe[3];

            if (HDMI_DE == 1'b1) begin
                checked_pixels <= checked_pixels + 1;
                if (HDMI_DATA !== expected_ycbcr422(rgb_pipe[3], chroma_cb_pipe[3])) begin
                    $error("YCbCr mismatch at pixel %0d: got %h expected %h",
                           checked_pixels, HDMI_DATA,
                           expected_ycbcr422(rgb_pipe[3], chroma_cb_pipe[3]));
                end
                if (HDMI_DE !== de_pipe[3]) begin
                    $error("DE pipeline mismatch");
                end
                if (HDMI_HSYNC !== hsync_pipe[3]) begin
                    $error("HSYNC pipeline mismatch");
                end
                if (HDMI_VSYNC !== vsync_pipe[3]) begin
                    $error("VSYNC pipeline mismatch");
                end
            end
        end
    end

    always @(posedge PIX_CLK or negedge RST_N) begin
        if (!RST_N) begin
            scl_previous <= 1'b0;
            start_seen <= 1'b0;
            ack_seen <= 1'b0;
            bit_count <= 4'd0;
            shift_byte <= 8'd0;
            sda_drive_tb <= 1'b0;
            first_start_seen <= 1'b0;
            first_start_time <= 0.0;
        end else begin
            scl_previous <= HDMI_SCL;
            if ((HDMI_SCL == 1'b1) && (scl_previous == 1'b1) &&
                (sda_previous == 1'b1) && (HDMI_SDA == 1'b0)) begin
                start_seen <= 1'b1;
                bit_count <= 4'd0;
                sda_drive_tb <= 1'b0;
                if (first_start_seen == 1'b0) begin
                    first_start_seen <= 1'b1;
                    first_start_time <= $realtime;
                end
            end
            if ((HDMI_SCL == 1'b1) && (scl_previous == 1'b0) && (start_seen == 1'b1)) begin
                if (bit_count != 4'd8) begin
                    shift_byte <= {shift_byte[6:0], HDMI_SDA};
                    bit_count <= bit_count + 4'd1;
                end else begin
                    ack_seen <= 1'b1;
                    if (HDMI_SDA !== 1'b0) begin
                        $error("I2C NACK received for byte %h", shift_byte);
                    end
                end
            end
            if ((HDMI_SCL == 1'b0) && (bit_count == 4'd8) && (ack_seen == 1'b0)) begin
                sda_drive_tb <= 1'b1;
            end
            if ((HDMI_SCL == 1'b0) && (ack_seen == 1'b1)) begin
                ack_seen <= 1'b0;
                bit_count <= 4'd0;
                sda_drive_tb <= 1'b0;
                if (write_address == 8'h00) begin
                    write_address <= shift_byte;
                end else if (write_register == 8'h00) begin
                    write_register <= shift_byte;
                end else begin
                    write_value <= shift_byte;
                    completed_writes <= completed_writes + 1;
                    write_address <= 8'h00;
                    write_register <= 8'h00;
                end
            end
        end
    end

    always @(posedge PIX_CLK) begin
        sda_previous <= HDMI_SDA;
    end

    initial begin
        PIX_CLK = 1'b0;
        RST_N = 1'b0;
        RGB888 = 24'h000000;
        DE = 1'b0;
        H_SYNC = 1'b0;
        V_SYNC = 1'b0;
        sda_drive_tb = 1'b0;
        scl_previous = 1'b0;
        start_seen = 1'b0;
        ack_seen = 1'b0;
        bit_count = 4'd0;
        shift_byte = 8'd0;
        write_address = 8'h00;
        write_register = 8'h00;
        write_value = 8'h00;
        completed_writes = 0;
        checked_pixels = 0;
        input_pixel_count = 0;
        first_start_seen = 1'b0;
        first_start_time = 0.0;
        pixel_index = 0;

        repeat (4) @(negedge PIX_CLK);
        RST_N = 1'b1;
        repeat (2) @(negedge PIX_CLK);

        for (pixel_index = 0; pixel_index < TEST_PIXEL_COUNT; pixel_index = pixel_index + 1) begin
            RGB888 <= (pixel_index * 24'h000101) + 24'h001020;
            DE <= 1'b1;
            H_SYNC <= 1'b0;
            V_SYNC <= 1'b0;
            @(negedge PIX_CLK);
        end
        DE <= 1'b0;
        RGB888 <= 24'h000000;

        wait ((completed_writes == 18) || ($realtime > SIMULATION_TIMEOUT_NS));
        if (completed_writes != 18) begin
            $error("I2C initialization did not complete: writes=%0d", completed_writes);
        end
        if (first_start_time < I2C_DELAY_MIN_NS) begin
            $error("I2C start before 100 ms: %0t", first_start_time);
        end

        repeat (20) @(posedge PIX_CLK);
        if (checked_pixels == TEST_PIXEL_COUNT) begin
            $display("TEST_PASS: pixels=%0d writes=%0d i2c_start_time=%0t",
                     checked_pixels, completed_writes, first_start_time);
        end else begin
            $error("Pixel check incomplete: checked=%0d expected=%0d",
                   checked_pixels, TEST_PIXEL_COUNT);
        end
        $finish;
    end

endmodule
