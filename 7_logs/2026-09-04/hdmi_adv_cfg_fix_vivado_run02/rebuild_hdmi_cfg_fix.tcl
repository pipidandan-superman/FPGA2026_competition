open_project E:/competition/2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "SYNTH_FAIL progress=[get_property PROGRESS [get_runs synth_1]]"
    exit 1
}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "IMPL_FAIL progress=[get_property PROGRESS [get_runs impl_1]]"
    exit 1
}
write_hw_platform -fixed -include_bit -force E:/competition/2_fpga/0_diaplay_test/vitis/display_test_wrapper.xsa
puts "ADV_CFG_FIX_VIVADO_PASS"
