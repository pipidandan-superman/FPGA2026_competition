create_project -force check_hdmi_module_ref [file normalize {C:/Users/Administrator/AppData/Local/Temp/check_hdmi_module_ref}] -part xc7z020clg484-1
add_files -fileset sources_1 [list \
  E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv \
  E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/rgb2ycbcr422.sv \
  E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv \
  E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv \
  E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv \
  E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_out_adv7511.sv \
  E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v]
update_compile_order -fileset sources_1
create_bd_design check_bd
if {[catch {create_bd_cell -type module -reference hdmi_out_adv7511 u_hdmi_out_adv7511} result]} {
    puts "MODULE_REF_FAILED: $result"
} else {
    puts "MODULE_REF_OK"
}
validate_bd_design
close_project
