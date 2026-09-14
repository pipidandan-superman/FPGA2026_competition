# ADV7511KSTZ hardware users guide archive

This directory collects the official manuals and source-code register evidence used to configure the EES-331 ADV7511 board.

## Main manuals

- `ADV7511_Hardware_Users_Guide.pdf` - ADV7511 Hardware User's Guide, Rev. D, 58 pages. Input mappings are in Section 6.1.2.1; Style 3/right-justified mapping is Table 7, page 24.
- `ADV7511_Datasheet_analog.com.pdf` - official short-form datasheet currently exposed by Analog Devices.
- `UG-556_ADV7511_API_Library.pdf` - official ADI API software user guide.
- `UG-235_ADV7511_Evaluation_Board.pdf` - official ADV7511 evaluation-board user guide.
- `manuals/UG-206.pdf`, `UG-214.pdf`, `UG-216.pdf` - related ADI evaluation/reference-design manuals.
- `manuals/UG961-ZC706-GSG.pdf` - Xilinx ZC706 board guide with ADV7511-based hardware context.

## Register evidence sources

- `sources/adi_api/` - source headers and drivers extracted from the official ADV7511 API Library package.
- `sources/adi_api/TX/HAL/WIRED/ADV7511/MACROS/ADV7511_main_map_fct.h` - complete machine-readable main-map bit-field macros.
- `sources/adi_api/TX/HAL/COMMON/tx_hal.c` - ADI input-format enum-to-register translation code.
- `sources/linux_driver/adv7511_drv.c` - Linux driver recommended register writes and YCbCr 4:2:2 input setup.
- `sources/linux_driver/adv7511.h` - Linux register-address definitions.
- `sources/ADV7511_API_Library_official.exe` - the official downloaded ADI package installer.

Read `REGISTER_NOTES.md` first for the project's exact 34-register table, Style 3 mapping, and internal-test-pattern conclusion.
