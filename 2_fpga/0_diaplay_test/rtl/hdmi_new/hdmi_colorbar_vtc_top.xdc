set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports sys_clk_100m]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports reset_n]
set_property -dict {PACKAGE_PIN AB6 IOSTANDARD LVCMOS33} [get_ports SW0]

set_property -dict {PACKAGE_PIN R7 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[0]}]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[1]}]
set_property -dict {PACKAGE_PIN V9 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[2]}]
set_property -dict {PACKAGE_PIN V8 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[3]}]
set_property -dict {PACKAGE_PIN W8 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[4]}]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[5]}]
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[6]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[7]}]
set_property -dict {PACKAGE_PIN W12 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[8]}]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[9]}]
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[10]}]
set_property -dict {PACKAGE_PIN U10 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[11]}]
set_property -dict {PACKAGE_PIN U9 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[12]}]
set_property -dict {PACKAGE_PIN AA12 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[13]}]
set_property -dict {PACKAGE_PIN AB12 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[14]}]
set_property -dict {PACKAGE_PIN AA11 IOSTANDARD LVCMOS33} [get_ports {HDMI_DATA[15]}]
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS33} [get_ports HDMI_INT]
set_property -dict {PACKAGE_PIN AB10 IOSTANDARD LVCMOS33} [get_ports HDMI_SCL]
set_property -dict {PACKAGE_PIN AB9 IOSTANDARD LVCMOS33} [get_ports HDMI_SDA]

# SDA remains an open-drain bidirectional I2C line. Keep the board's external
# pull-up as the primary source and add a weak FPGA pull-up as a fallback.
set_property PULLTYPE PULLUP [get_ports HDMI_SDA]
set_property -dict {PACKAGE_PIN Y11 IOSTANDARD LVCMOS33} [get_ports HDMI_VSYNC]
set_property -dict {PACKAGE_PIN Y10 IOSTANDARD LVCMOS33} [get_ports HDMI_HSYNC]
set_property -dict {PACKAGE_PIN AA9 IOSTANDARD LVCMOS33} [get_ports HDMI_DE]
set_property -dict {PACKAGE_PIN Y8 IOSTANDARD LVCMOS33} [get_ports HDMI_CLK]

set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN U6 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN U5 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN W7 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN W6 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]

# ADV7511 samples D/DE/HS/VS on the rising edge of HDMI_CLK. The RTL launches
# these signals on the falling edge, providing a nominal half-cycle margin.
create_generated_clock -name adv7511_pixel_clk -source [get_pins u_hdmi_clk_oddr/C] -divide_by 1 [get_ports HDMI_CLK]

set_output_delay -clock adv7511_pixel_clk -max 1.000 [get_ports {{HDMI_DATA[*]} HDMI_DE HDMI_HSYNC HDMI_VSYNC}]
set_output_delay -clock adv7511_pixel_clk -min -0.700 [get_ports {{HDMI_DATA[*]} HDMI_DE HDMI_HSYNC HDMI_VSYNC}]

# LEDs are human-visible status outputs and I2C SCL timing is defined by the
# protocol divider, not by an external synchronous capture clock. SW0 is a
# mechanical asynchronous input and is synchronized in the RTL.
set_false_path -from [get_ports SW0]
set_false_path -to [get_ports {{LED[*]} HDMI_SCL}]

# Keep the source-synchronous data/control registers in the output I/O cells.
set_property IOB TRUE [get_cells -hier -filter {
NAME =~ *HDMI_DATA_reg* ||
NAME =~ *HDMI_DE_reg ||
NAME =~ *HDMI_HSYNC_reg ||
NAME =~ *HDMI_VSYNC_reg
}]
