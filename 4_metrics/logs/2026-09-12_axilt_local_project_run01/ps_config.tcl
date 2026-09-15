# Board configuration extracted from the run-local baseline BD.
set board_cfg [list]
lappend board_cfg CONFIG.PCW_CAN0_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_CAN1_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333}
lappend board_cfg CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF}
lappend board_cfg CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27}
lappend board_cfg CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1}
lappend board_cfg CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53}
lappend board_cfg CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {IO PLL}
lappend board_cfg CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1}
lappend board_cfg CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {1000 Mbps}
lappend board_cfg CONFIG.PCW_ENET0_RESET_ENABLE {1}
lappend board_cfg CONFIG.PCW_ENET0_RESET_IO {MIO 47}
lappend board_cfg CONFIG.PCW_ENET1_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_ENET_RESET_ENABLE {1}
lappend board_cfg CONFIG.PCW_ENET_RESET_SELECT {Share reset pin}
lappend board_cfg CONFIG.PCW_FCLK_CLK0_BUF {TRUE}
lappend board_cfg CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50}
lappend board_cfg CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {50}
lappend board_cfg CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {50}
lappend board_cfg CONFIG.PCW_FPGA3_PERIPHERAL_FREQMHZ {50}
lappend board_cfg CONFIG.PCW_FPGA_FCLK0_ENABLE {1}
lappend board_cfg CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1}
lappend board_cfg CONFIG.PCW_GPIO_EMIO_GPIO_IO {2}
lappend board_cfg CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {2}
lappend board_cfg CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1}
lappend board_cfg CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO}
lappend board_cfg CONFIG.PCW_GPIO_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_I2C1_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_I2C_RESET_ENABLE {1}
lappend board_cfg CONFIG.PCW_MIO_0_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_0_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_0_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_10_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_10_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_10_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_11_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_11_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_11_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_12_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_12_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_13_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_13_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_13_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_14_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_14_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_15_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_15_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_16_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_16_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_16_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_17_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_17_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_17_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_18_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_18_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_18_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_19_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_19_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_19_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_1_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_1_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_20_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_20_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_20_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_21_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_21_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_21_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_22_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_22_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_22_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_23_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_23_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_23_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_24_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_24_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_24_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_25_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_25_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_25_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_26_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_26_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_26_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_27_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_27_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_27_SLEW {fast}
lappend board_cfg CONFIG.PCW_MIO_28_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_28_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_28_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_29_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_29_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_29_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_2_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_30_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_30_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_30_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_31_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_31_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_31_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_32_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_32_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_32_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_33_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_33_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_33_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_34_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_34_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_34_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_35_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_35_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_35_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_36_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_36_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_36_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_37_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_37_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_37_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_38_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_38_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_38_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_39_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_39_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_39_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_3_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_40_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_40_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_40_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_41_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_41_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_41_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_42_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_42_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_42_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_43_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_43_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_43_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_44_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_44_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_44_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_45_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_45_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_45_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_46_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_46_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_46_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_47_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_47_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_47_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_48_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_48_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_48_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_49_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_49_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_49_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_4_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_50_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_50_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_50_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_51_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_51_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_51_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_52_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_52_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_52_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_53_IOTYPE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_MIO_53_PULLUP {disabled}
lappend board_cfg CONFIG.PCW_MIO_53_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_5_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_6_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_7_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_7_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_8_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_8_SLEW {slow}
lappend board_cfg CONFIG.PCW_MIO_9_IOTYPE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_MIO_9_PULLUP {enabled}
lappend board_cfg CONFIG.PCW_MIO_9_SLEW {slow}
lappend board_cfg CONFIG.PCW_PJTAG_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V}
lappend board_cfg CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V}
lappend board_cfg CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_SD0_GRP_CD_ENABLE {1}
lappend board_cfg CONFIG.PCW_SD0_GRP_CD_IO {MIO 0}
lappend board_cfg CONFIG.PCW_SD0_GRP_POW_ENABLE {0}
lappend board_cfg CONFIG.PCW_SD0_GRP_WP_ENABLE {0}
lappend board_cfg CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1}
lappend board_cfg CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45}
lappend board_cfg CONFIG.PCW_SD1_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {100}
lappend board_cfg CONFIG.PCW_SDIO_PERIPHERAL_VALID {1}
lappend board_cfg CONFIG.PCW_SPI0_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_SPI1_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_TTC1_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_UART0_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_UART1_BAUD_RATE {115200}
lappend board_cfg CONFIG.PCW_UART1_GRP_FULL_ENABLE {0}
lappend board_cfg CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1}
lappend board_cfg CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49}
lappend board_cfg CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100}
lappend board_cfg CONFIG.PCW_UART_PERIPHERAL_VALID {1}
lappend board_cfg CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374}
lappend board_cfg CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-15E}
lappend board_cfg CONFIG.PCW_USB0_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_USB1_PERIPHERAL_ENABLE {0}
lappend board_cfg CONFIG.PCW_USB_RESET_ENABLE {1}
lappend board_cfg CONFIG.PCW_USE_DMA0 {0}
lappend board_cfg CONFIG.PCW_USE_DMA1 {0}
lappend board_cfg CONFIG.PCW_USE_M_AXI_GP0 {1}
lappend board_cfg CONFIG.PCW_USE_M_AXI_GP1 {0}
lappend board_cfg CONFIG.PCW_USE_S_AXI_ACP {0}
lappend board_cfg CONFIG.PCW_USE_S_AXI_GP0 {0}
lappend board_cfg CONFIG.PCW_USE_S_AXI_GP1 {0}
lappend board_cfg CONFIG.PCW_USE_S_AXI_HP0 {1}
lappend board_cfg CONFIG.PCW_USE_S_AXI_HP1 {1}
lappend board_cfg CONFIG.PCW_USE_S_AXI_HP2 {0}
lappend board_cfg CONFIG.PCW_USE_S_AXI_HP3 {0}
lappend board_cfg CONFIG.PCW_WDT_PERIPHERAL_ENABLE {0}
set_property -dict $board_cfg $ps
set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {0} CONFIG.PCW_USE_S_AXI_HP1 {0} CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {0} CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] $ps
