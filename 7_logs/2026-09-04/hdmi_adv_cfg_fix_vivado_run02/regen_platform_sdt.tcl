package require sdtgen
::sdtgen::set_dt_param -xsa E:/competition/2_fpga/0_diaplay_test/vitis/display_test_plat/hw/display_test_wrapper.xsa -dir E:/competition/2_fpga/0_diaplay_test/vitis/display_test_plat/hw/sdt
::sdtgen::generate_sdt
puts SDT_REGEN_PASS
