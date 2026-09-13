# EES-331 action UART + LEDs; LED0/V4 is reserved for camera cfg_done.
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports PL_RS232_TX]
set_property -dict {PACKAGE_PIN U6 IOSTANDARD LVCMOS33} [get_ports {ACTION_LED[0]}]
set_property -dict {PACKAGE_PIN U5 IOSTANDARD LVCMOS33} [get_ports {ACTION_LED[1]}]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33} [get_ports {ACTION_LED[2]}]
set_property -dict {PACKAGE_PIN W7 IOSTANDARD LVCMOS33} [get_ports {ACTION_LED[3]}]
set_property -dict {PACKAGE_PIN W6 IOSTANDARD LVCMOS33} [get_ports {ACTION_LED[4]}]
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports {ACTION_LED[5]}]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports {ACTION_LED[6]}]
# UART and visible LEDs are asynchronous observer outputs (no receiving clock).
set_false_path -to [get_ports {PL_RS232_TX ACTION_LED[*]}]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
