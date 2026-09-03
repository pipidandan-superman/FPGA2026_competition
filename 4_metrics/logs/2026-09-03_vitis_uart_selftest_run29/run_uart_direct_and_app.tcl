connect
targets 2
stop
rst -processor
source E:/competition/2_fpga/0_diaplay_test/vitis/app_component/_ide/psinit/ps7_init.tcl
ps7_init
ps7_post_config
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
dow E:/competition/2_fpga/0_diaplay_test/vitis/app_component/build/app_component.elf
con
after 3000
disconnect
exit
