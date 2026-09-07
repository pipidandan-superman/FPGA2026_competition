//====================================================================
// File name   : adv7511_init_table_pkg.sv
// Author      : LSL
// Create date : 2026-09-06
// Description : ADV7511 16-bit YCbCr422 input to HDMI YCbCr422 output
// Target      : FPGA/ASIC
// Revision    : V2.1
//====================================================================

package adv7511_init_table_pkg;

    localparam int ADV7511_INIT_ENTRY_COUNT = 44;
    localparam int ADV7511_READBACK_ENTRY_COUNT = 6;

    // The FPGA byte-swaps logical Style 3 {Y, Cb/Cr}; the physical bus is
    // therefore UG Rev. D Table 7 Style 1 {Cb/Cr, Y}. ADI API maps UG Style 1
    // to R0x16[3:2]=0. R0x16=0xB1 requests YCbCr422 HDMI output and leaves
    // the uncertain RGB CSC stage disabled.
    localparam logic [7:0] ADV7511_VIDEO_INPUT_ID   = 8'h01;
    localparam logic [7:0] ADV7511_VIDEO_INPUT_CFG1 = 8'hB1;
    localparam logic [7:0] ADV7511_VIDEO_INPUT_CFG2 = 8'h08;
    localparam logic [7:0] ADV7511_HDMI_MODE_CFG    = 8'h12;

    function automatic logic [7:0] adv7511_init_address(input int unsigned index);
        case (index)
            0:  adv7511_init_address = 8'h98;
            1:  adv7511_init_address = 8'h9A;
            2:  adv7511_init_address = 8'h9C;
            3:  adv7511_init_address = 8'h9D;
            4:  adv7511_init_address = 8'hA2;
            5:  adv7511_init_address = 8'hA3;
            6:  adv7511_init_address = 8'hD6;
            7:  adv7511_init_address = 8'h49;
            8:  adv7511_init_address = 8'h96;
            9:  adv7511_init_address = 8'h99;
            10: adv7511_init_address = 8'hDE;
            11: adv7511_init_address = 8'hE0;
            12: adv7511_init_address = 8'hE4;
            13: adv7511_init_address = 8'hF9;
            14: adv7511_init_address = 8'hDF;
            15: adv7511_init_address = 8'hFD;
            16: adv7511_init_address = 8'hFE;
            17: adv7511_init_address = 8'h41;
            18: adv7511_init_address = 8'h40;
            19: adv7511_init_address = 8'h44;
            20: adv7511_init_address = 8'hBA;
            21: adv7511_init_address = 8'hBB;
            22: adv7511_init_address = 8'h4A;
            23: adv7511_init_address = 8'h52;
            24: adv7511_init_address = 8'h53;
            25: adv7511_init_address = 8'h54;
            26: adv7511_init_address = 8'h55;
            27: adv7511_init_address = 8'h56;
            28: adv7511_init_address = 8'h57;
            29: adv7511_init_address = 8'h58;
            30: adv7511_init_address = 8'h59;
            31: adv7511_init_address = 8'h5A;
            32: adv7511_init_address = 8'h5B;
            33: adv7511_init_address = 8'h5C;
            34: adv7511_init_address = 8'h5D;
            35: adv7511_init_address = 8'h5E;
            36: adv7511_init_address = 8'h4A;
            37: adv7511_init_address = 8'hD0;
            38: adv7511_init_address = 8'hD1;
            39: adv7511_init_address = 8'hD2;
            40: adv7511_init_address = 8'h15;
            41: adv7511_init_address = 8'h48;
            42: adv7511_init_address = 8'h16;
            43: adv7511_init_address = 8'hAF;
            default: adv7511_init_address = 8'h00;
        endcase
    endfunction

    function automatic logic [7:0] adv7511_init_value(input int unsigned index);
        case (index)
            0:  adv7511_init_value = 8'h03;
            1:  adv7511_init_value = 8'hE0;
            2:  adv7511_init_value = 8'h30;
            3:  adv7511_init_value = 8'h61;
            4:  adv7511_init_value = 8'hA4;
            5:  adv7511_init_value = 8'hA4;
            6:  adv7511_init_value = 8'hC0;
            7:  adv7511_init_value = 8'hA8;
            8:  adv7511_init_value = 8'hC0;
            9:  adv7511_init_value = 8'h02;
            10: adv7511_init_value = 8'h10;
            11: adv7511_init_value = 8'hD0;
            12: adv7511_init_value = 8'h60;
            13: adv7511_init_value = 8'h9C;
            14: adv7511_init_value = 8'h01;
            15: adv7511_init_value = 8'hE0;
            16: adv7511_init_value = 8'h80;
            17: adv7511_init_value = 8'h10;
            18: adv7511_init_value = 8'h00;
            19: adv7511_init_value = 8'h10; // enable AVI packet
            20: adv7511_init_value = 8'h60;
            21: adv7511_init_value = 8'h00;
            22: adv7511_init_value = 8'h40; // begin AVI update
            23: adv7511_init_value = 8'h02;
            24: adv7511_init_value = 8'h0D;
            25: adv7511_init_value = 8'hAB;
            26: adv7511_init_value = 8'h29; // YCbCr422 format metadata
            27: adv7511_init_value = 8'h99;
            28: adv7511_init_value = 8'h01; // VIC 1: 640x480p60
            29: adv7511_init_value = 8'h01;
            30: adv7511_init_value = 8'h00;
            31: adv7511_init_value = 8'h00;
            32: adv7511_init_value = 8'h00;
            33: adv7511_init_value = 8'h00;
            34: adv7511_init_value = 8'h00;
            35: adv7511_init_value = 8'h00;
            36: adv7511_init_value = 8'h00; // finish AVI update
            37: adv7511_init_value = 8'h03;
            38: adv7511_init_value = 8'hFF;
            39: adv7511_init_value = 8'hFF;
            40: adv7511_init_value = ADV7511_VIDEO_INPUT_ID;
            41: adv7511_init_value = ADV7511_VIDEO_INPUT_CFG2;
            42: adv7511_init_value = ADV7511_VIDEO_INPUT_CFG1;
            43: adv7511_init_value = ADV7511_HDMI_MODE_CFG;
            default: adv7511_init_value = 8'h00;
        endcase
    endfunction

    function automatic logic [7:0] adv7511_readback_address(input int unsigned index);
        case (index)
            0: adv7511_readback_address = 8'h41;
            1: adv7511_readback_address = 8'h15;
            2: adv7511_readback_address = 8'h16;
            3: adv7511_readback_address = 8'h48;
            4: adv7511_readback_address = 8'hAF;
            5: adv7511_readback_address = 8'hDE;
            default: adv7511_readback_address = 8'h00;
        endcase
    endfunction

    function automatic logic [7:0] adv7511_readback_expected(input int unsigned index);
        case (index)
            0: adv7511_readback_expected = 8'h10;
            1: adv7511_readback_expected = 8'h01;
            2: adv7511_readback_expected = 8'h30; // depth/style fields only
            3: adv7511_readback_expected = 8'h08;
            4: adv7511_readback_expected = 8'h12;
            5: adv7511_readback_expected = 8'h10;
            default: adv7511_readback_expected = 8'h00;
        endcase
    endfunction

    function automatic logic [7:0] adv7511_readback_mask(input int unsigned index);
        case (index)
            0: adv7511_readback_mask = 8'h70;
            1: adv7511_readback_mask = 8'h0F;
            2: adv7511_readback_mask = 8'h30;
            3: adv7511_readback_mask = 8'h18;
            4: adv7511_readback_mask = 8'h12;
            5: adv7511_readback_mask = 8'h10;
            default: adv7511_readback_mask = 8'h00;
        endcase
    endfunction

endpackage
