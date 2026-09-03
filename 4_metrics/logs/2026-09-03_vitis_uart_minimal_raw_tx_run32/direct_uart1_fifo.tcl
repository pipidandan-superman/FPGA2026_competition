connect
targets
targets 2
catch {stop}
rst -processor
source E:/competition/2_fpga/0_diaplay_test/vitis/display_test_platform/hw/sdt/ps7_init.tcl
ps7_init
ps7_post_config
puts "UART_CTRL=[mrd 0xE0001000]"
puts "UART_MODE=[mrd 0xE0001004]"
puts "UART_STATUS=[mrd 0xE000102C]"
puts "MIO48_CTRL=[mrd 0xF8000830]"
puts "MIO49_CTRL=[mrd 0xF8000834]"
mwr 0xE0001030 0x58
mwr 0xE0001030 0x53
mwr 0xE0001030 0x43
mwr 0xE0001030 0x54
mwr 0xE0001030 0x54
mwr 0xE0001030 0x20
mwr 0xE0001030 0x4F
mwr 0xE0001030 0x4B
mwr 0xE0001030 0x0D
mwr 0xE0001030 0x0A
puts "DIRECT_UART1_WRITE_DONE"
after 3000
disconnect
exit
