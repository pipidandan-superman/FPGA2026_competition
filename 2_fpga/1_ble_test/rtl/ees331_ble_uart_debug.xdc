# EES-331 User Guide sections 5, 7, 14, 20 and 24.
# Separate bridge project; original AT/ILA project constraints remain unchanged.
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports SYS_CLK]
create_clock -name sys_clk_100m -period 10.000 [get_ports SYS_CLK]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports SYS_RST_N]

# J8 upper USB socket -> CP2103 -> PL UART (FPGA directions).
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports PL_RS232_RX]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports PL_RS232_TX]

# Bluetooth module pin names are from the module's point of view.
set_property -dict {PACKAGE_PIN Y13 IOSTANDARD LVCMOS33} [get_ports BT_TX]
set_property -dict {PACKAGE_PIN AA13 IOSTANDARD LVCMOS33} [get_ports BT_RX]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports FPGA_BT_3V3]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports BT_RESET_N]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports BRIDGE_READY]
set_property -dict {DRIVE 8 SLEW SLOW} \
    [get_ports {PL_RS232_TX BT_RX FPGA_BT_3V3 BT_RESET_N BRIDGE_READY}]

# UART inputs are asynchronous and enter explicit two-flop synchronizers.
set_false_path -from [get_ports {SYS_RST_N PL_RS232_RX BT_TX}]
set_false_path -to [get_ports {PL_RS232_TX BT_RX FPGA_BT_3V3 BT_RESET_N BRIDGE_READY}]
