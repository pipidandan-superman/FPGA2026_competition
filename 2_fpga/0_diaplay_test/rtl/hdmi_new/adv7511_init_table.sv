//====================================================================
// File name   : adv7511_init_table.sv
// Author      : LSL
// Create date : 2026-09-06
// Description : ADV7511 V2.1 register table for explicit instantiation
// Target      : FPGA/ASIC
// Revision    : V1.3
//====================================================================

module adv7511_init_table (
    input  wire        [6:0] init_index_i          ,
    input  wire        [2:0] readback_index_i      ,
    output logic       [7:0] init_address_o        ,
    output logic       [7:0] init_data_o           ,
    output logic       [7:0] readback_address_o    ,
    output logic       [7:0] readback_expected_o   ,
    output logic       [7:0] readback_mask_o       ,
    output logic       [6:0] last_init_index_o     ,
    output logic       [2:0] last_readback_index_o
);

    // 修改前：
// localparam logic [5:0] INIT_ENTRY_COUNT      = 6'd44;

// 修改后：
localparam logic [6:0] INIT_ENTRY_COUNT      = 7'd68;
    localparam logic [2:0] READBACK_ENTRY_COUNT  = 3'd6;

    always_comb begin
        last_init_index_o     = INIT_ENTRY_COUNT - 7'd1;
        last_readback_index_o = READBACK_ENTRY_COUNT - 3'd1;
        init_address_o        = 8'h00;
        init_data_o           = 8'h00;
        readback_address_o    = 8'h00;
        readback_expected_o   = 8'h00;
        readback_mask_o       = 8'h00;

        case (init_index_i)
            7'd0: begin
                init_address_o = 8'h98;
                init_data_o    = 8'h03;
            end
            7'd1: begin
                init_address_o = 8'h9A;
                init_data_o    = 8'hE0;
            end
            7'd2: begin
                init_address_o = 8'h9C;
                init_data_o    = 8'h30;
            end
            7'd3: begin
                init_address_o = 8'h9D;
                init_data_o    = 8'h61;
            end
            7'd4: begin
                init_address_o = 8'hA2;
                init_data_o    = 8'hA4;
            end
            7'd5: begin
                init_address_o = 8'hA3;
                init_data_o    = 8'hA4;
            end
            7'd6: begin
                init_address_o = 8'hD6;
                init_data_o    = 8'hC0;
            end
            7'd7: begin
                init_address_o = 8'h49;
                init_data_o    = 8'hA8;
            end
           7'd8: begin
                init_address_o = 8'h96;
                init_data_o    = 8'hC0;
            end
            7'd9: begin
                init_address_o = 8'h99;
                init_data_o    = 8'h02;
            end
            7'd10: begin
                init_address_o = 8'hDE;
                init_data_o    = 8'h10;
            end
            7'd11: begin
                init_address_o = 8'hE0;
                init_data_o    = 8'hD0;
            end
            7'd12: begin
                init_address_o = 8'hE4;
                init_data_o    = 8'h60;
            end
            7'd13: begin
                init_address_o = 8'hF9;
                init_data_o    = 8'h9C;
            end
            7'd14: begin
                init_address_o = 8'hDF;
                init_data_o    = 8'h01;
            end
            7'd15: begin
                init_address_o = 8'hFD;
                init_data_o    = 8'hE0;
            end
            7'd16: begin
                init_address_o = 8'hFE;
                init_data_o    = 8'h80;
            end
            7'd17: begin
                init_address_o = 8'h41;
                init_data_o    = 8'h10;
            end
            7'd18: begin
                init_address_o = 8'h40;
                init_data_o    = 8'h00;
            end
            7'd19: begin
                init_address_o = 8'h44;
                init_data_o    = 8'h10; // enable AVI packet
            end
            7'd20: begin
                init_address_o = 8'hBA;
                init_data_o    = 8'h60;
            end
            7'd21: begin
                init_address_o = 8'hBB;
                init_data_o    = 8'h00;
            end
            7'd22: begin
                init_address_o = 8'h4A;
                init_data_o    = 8'h40; // begin AVI update
            end
            7'd23: begin
                init_address_o = 8'h52;
                init_data_o    = 8'h02;
            end
            7'd24: begin
                init_address_o = 8'h53;
                init_data_o    = 8'h0D;
            end
            7'd25: begin
                init_address_o = 8'h54;
                init_data_o    = 8'hCB; // updated for RGB AVI byte R0x55=09
            end
//            6'd26: begin
//                init_address_o = 8'h55;
//                init_data_o    = 8'h29; // YCbCr422 format metadata
//            end
// 修改索引 26 (0x55 寄存器)，将 AVI InfoFrame 声明为 RGB 格式
        7'd26: begin
            init_address_o = 8'h55;
            init_data_o    = 8'h09; // 修改前为 8'h29
        end
            7'd27: begin
                init_address_o = 8'h56;
                init_data_o    = 8'h99;
            end
            7'd28: begin
                init_address_o = 8'h57;
                init_data_o    = 8'h01; // VIC 1: 640x480p60
            end
            7'd29: begin
                init_address_o = 8'h58;
                init_data_o    = 8'h01;
            end
            7'd30: begin
                init_address_o = 8'h59;
                init_data_o    = 8'h00;
            end
            7'd31: begin
                init_address_o = 8'h5A;
                init_data_o    = 8'h00;
            end
            7'd32: begin
                init_address_o = 8'h5B;
                init_data_o    = 8'h00;
            end
            7'd33: begin
                init_address_o = 8'h5C;
                init_data_o    = 8'h00;
            end
            7'd34: begin
                init_address_o = 8'h5D;
                init_data_o    = 8'h00;
            end
            7'd35: begin
                init_address_o = 8'h5E;
                init_data_o    = 8'h00;
            end
            'd36: begin
                init_address_o = 8'h4A;
                init_data_o    = 8'h00; // finish AVI update
            end
            'd37: begin
                init_address_o = 8'hD0;
                init_data_o    = 8'h03;
            end
            'd38: begin
                init_address_o = 8'hD1;
                init_data_o    = 8'hFF;
            end
            'd39: begin
                init_address_o = 8'hD2;
                init_data_o    = 8'hFF;
            end
            'd40: begin
                init_address_o = 8'h15;
                init_data_o    = 8'h01;
            end
            'd41: begin
                init_address_o = 8'h48;
                init_data_o    = 8'h08;
            end
//            6'd42: begin
//                init_address_o = 8'h16;
//                init_data_o    = 8'hB1;
//            end
// 修改索引 42 (0x16 寄存器)，将芯片物理输出配置为 RGB 4:4:4, 8-bit, Style 1
        'd42: begin
            init_address_o = 8'h16;
            // 0x38 selects 8-bit YCbCr422 with the same 16-bit mapping as
            // Style 3. The EES-331 board byte swap is applied in the top level.
            init_data_o    = 8'h38;
        end
            'd43: begin
                init_address_o = 8'hAF;
                init_data_o    = 8'h12;
            end
            // Signature: ADI_CSC601_LR_TO_RGB_V1_3
            'd44: begin init_address_o = 8'h18; init_data_o = 8'hAA; end
            'd45: begin init_address_o = 8'h19; init_data_o = 8'hF7; end
            'd46: begin init_address_o = 8'h1A; init_data_o = 8'h08; end
            'd47: begin init_address_o = 8'h1B; init_data_o = 8'h00; end
            'd48: begin init_address_o = 8'h1C; init_data_o = 8'h00; end
            'd49: begin init_address_o = 8'h1D; init_data_o = 8'h00; end
            'd50: begin init_address_o = 8'h1E; init_data_o = 8'h1A; end
            'd51: begin init_address_o = 8'h1F; init_data_o = 8'h84; end
            'd52: begin init_address_o = 8'h20; init_data_o = 8'h1A; end
            'd53: begin init_address_o = 8'h21; init_data_o = 8'h6A; end
            'd54: begin init_address_o = 8'h22; init_data_o = 8'h08; end
            'd55: begin init_address_o = 8'h23; init_data_o = 8'h00; end
            'd56: begin init_address_o = 8'h24; init_data_o = 8'h1D; end
            'd57: begin init_address_o = 8'h25; init_data_o = 8'h50; end
            'd58: begin init_address_o = 8'h26; init_data_o = 8'h04; end
            'd59: begin init_address_o = 8'h27; init_data_o = 8'h22; end
            'd60: begin init_address_o = 8'h28; init_data_o = 8'h00; end
            'd61: begin init_address_o = 8'h29; init_data_o = 8'h00; end
            'd62: begin init_address_o = 8'h2A; init_data_o = 8'h08; end
            'd63: begin init_address_o = 8'h2B; init_data_o = 8'h00; end
            'd64: begin init_address_o = 8'h2C; init_data_o = 8'h0D; end
            'd65: begin init_address_o = 8'h2D; init_data_o = 8'hDB; end
            'd66: begin init_address_o = 8'h2E; init_data_o = 8'h19; end
            'd67: begin init_address_o = 8'h2F; init_data_o = 8'h12; end
            default: begin
                init_address_o = 8'h00;
                init_data_o    = 8'h00;
            end
        endcase

        case (readback_index_i)
            3'd0: begin
                readback_address_o  = 8'h41;
                readback_expected_o = 8'h10;
                readback_mask_o     = 8'h70;
            end
            3'd1: begin
                readback_address_o  = 8'h15;
                readback_expected_o = 8'h01;
                readback_mask_o     = 8'h0F;
            end
            3'd2: begin
                readback_address_o  = 8'h16;
                readback_expected_o = 8'h30; // depth/style fields only
                readback_mask_o     = 8'h30;
            end
            3'd3: begin
                readback_address_o  = 8'h48;
                readback_expected_o = 8'h08;
                readback_mask_o     = 8'h18;
            end
            3'd4: begin
                readback_address_o  = 8'hAF;
                readback_expected_o = 8'h12;
                readback_mask_o     = 8'h12;
            end
            3'd5: begin
                readback_address_o  = 8'hDE;
                readback_expected_o = 8'h10;
                readback_mask_o     = 8'h10;
            end
            default: begin
                readback_address_o  = 8'h00;
                readback_expected_o = 8'h00;
                readback_mask_o     = 8'h00;
            end
        endcase
    end

endmodule
