# EES-331 Bluetooth AT-test constraints
# Source: EES-331 User Guide, PL clock/reset and PL Bluetooth pin tables.

# 100 MHz PL oscillator and active-low PL pushbutton reset.
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports SYS_CLK]
create_clock -name sys_clk_100m -period 10.000 [get_ports SYS_CLK]

set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports SYS_RST_N]

# MLT-BT05 power, reset, and UART signals.
# BT_RX is driven by the FPGA and received by the Bluetooth module.
# BT_TX is driven by the Bluetooth module and received by the FPGA.
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports FPGA_BT_3V3]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports BT_RESET_N]
set_property -dict {PACKAGE_PIN AA13 IOSTANDARD LVCMOS33} [get_ports BT_RX]
set_property -dict {PACKAGE_PIN Y13 IOSTANDARD LVCMOS33} [get_ports BT_TX]

set_property -dict {DRIVE 8 SLEW SLOW} \
    [get_ports {FPGA_BT_3V3 BT_RESET_N BT_RX}]

# Human-visible status outputs.
set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports TEST_PASS]
set_property -dict {PACKAGE_PIN U6 IOSTANDARD LVCMOS33} [get_ports TEST_FAIL]
set_property -dict {PACKAGE_PIN U5 IOSTANDARD LVCMOS33} [get_ports RESPONSE_SEEN]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33} [get_ports RX_FRAME_ERROR]
set_property -dict {PACKAGE_PIN W7 IOSTANDARD LVCMOS33} [get_ports {DEBUG_STATE[0]}]
set_property -dict {PACKAGE_PIN W6 IOSTANDARD LVCMOS33} [get_ports {DEBUG_STATE[1]}]
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports {DEBUG_STATE[2]}]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports {DEBUG_STATE[3]}]

set_property -dict {DRIVE 8 SLEW SLOW} \
    [get_ports {TEST_PASS TEST_FAIL RESPONSE_SEEN RX_FRAME_ERROR DEBUG_STATE[*]}]

# BT_TX and SYS_RST_N are asynchronous to SYS_CLK and are synchronized or used
# only as an asynchronous reset in the RTL. UART and status outputs have no
# external synchronous capture clock in this diagnostic design.
set_false_path -from [get_ports {BT_TX SYS_RST_N}]
set_false_path -to \
    [get_ports {BT_RX FPGA_BT_3V3 BT_RESET_N TEST_PASS TEST_FAIL \
                RESPONSE_SEEN RX_FRAME_ERROR DEBUG_STATE[*]}]
