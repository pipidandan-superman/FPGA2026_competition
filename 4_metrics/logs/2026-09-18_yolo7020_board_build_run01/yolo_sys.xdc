# yolo_sys fabric clock -- all PL logic on ps7 FCLK0 (60 MHz).
# PS7 interface clocks (DDR/MIO) are auto-constrained by the PS7 IP;
# this constraint documents the single fabric clock domain.
create_clock -period 16.667 -name FCLK0 [get_pins -hier -filter {NAME =~ *ps7/FCLK_CLK0} -quiet]
