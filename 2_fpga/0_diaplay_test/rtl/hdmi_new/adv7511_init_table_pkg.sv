/************************************************************************
 * File Name       : adv7511_init_table_pkg.sv
 * Developer       : LSL
 * Date            : 2026-09-03
 * Project Name    : EES-331 HDMI display adaptation
 * Module Name     : adv7511_init_table_pkg
 * Description     : First-pass ADV7511 register initialization table for
 *                   480p60 YCbCr 4:2:2 16-bit input operation.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-03) by LSL : Initial release
 ************************************************************************/

package adv7511_init_table_pkg;

    localparam int ADV7511_INIT_ENTRY_COUNT = 18;

    typedef struct packed {
        logic [7:0] register_address;
        logic [7:0] register_value;
    } adv7511_init_entry_t;

    localparam adv7511_init_entry_t ADV7511_INIT_TABLE [0:ADV7511_INIT_ENTRY_COUNT-1] = '{
        '{8'h98, 8'h03},
        '{8'h9A, 8'hE0},
        '{8'h9C, 8'h30},
        '{8'h9D, 8'h61},
        '{8'hA2, 8'hA4},
        '{8'hA3, 8'hA4},
        '{8'hAF, 8'h10},
        '{8'hD0, 8'h03},
        '{8'hD1, 8'hFF},
        '{8'hD2, 8'hFF},
        '{8'hDE, 8'h55},
        '{8'hE0, 8'hD0},
        '{8'h15, 8'h01},
        '{8'h16, 8'h30},
        '{8'h18, 8'h46},
        '{8'h55, 8'h0A},
        '{8'h56, 8'h4A},
        '{8'h57, 8'h02}
    };

endpackage
