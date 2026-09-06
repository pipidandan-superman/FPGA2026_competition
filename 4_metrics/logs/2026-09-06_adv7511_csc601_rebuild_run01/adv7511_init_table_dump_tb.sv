module adv7511_init_table_dump_tb;
    reg  [6:0] init_index;
    reg  [2:0] readback_index;
    wire [7:0] init_address;
    wire [7:0] init_data;
    wire [7:0] readback_address;
    wire [7:0] readback_expected;
    wire [7:0] readback_mask;
    wire [6:0] last_init_index;
    wire [2:0] last_readback_index;
    integer i;

    adv7511_init_table u_table (
        .init_index_i        (init_index),
        .readback_index_i    (readback_index),
        .init_address_o      (init_address),
        .init_data_o         (init_data),
        .readback_address_o  (readback_address),
        .readback_expected_o (readback_expected),
        .readback_mask_o     (readback_mask),
        .last_init_index_o   (last_init_index),
        .last_readback_index_o(last_readback_index)
    );

    initial begin
        init_index = 7'd0;
        readback_index = 3'd0;
        if (last_init_index !== 7'd67) begin
            $display("TABLE_COUNT_FAIL last_init_index=%0d", last_init_index);
            $fatal(1, "TABLE_DUMP_FAIL");
        end
        for (i = 0; i < 68; i = i + 1) begin
            init_index = i[6:0];
            #1;
            $display("TABLE[%0d] addr=%02h data=%02h", i, init_address, init_data);
        end
        if ((init_address !== 8'h2F) || (init_data !== 8'h12)) begin
            $fatal(1, "ADI_CSC601_TABLE_FAIL");
        end
        $display("ADI_CSC601_TABLE_PASS entries=68");
        $finish;
    end
endmodule
