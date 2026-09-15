set run_dir E:/competition/4_metrics/logs/2026-09-13_axilt_reset_sim_run01
cd $run_dir
file copy E:/competition/2_fpga/2_axi_lite_test/sim/tb_reset_integration.sv $run_dir/tb_reset_integration.sv
foreach f [glob E:/competition/2_fpga/2_axi_lite_test/rtl/*.v] {file copy $f $run_dir}
file copy E:/competition/2_fpga/2_axi_lite_test/proj/AXI_LITE_test.gen/sources_1/bd/AXI_LITE_test/ip/AXI_LITE_test_control_reset_0/AXI_LITE_test_control_reset_0_sim_netlist.v $run_dir/reset_ip_netlist.v
create_project reset_sim $run_dir/project -part xc7z020clg484-1
add_files [glob $run_dir/*.v]
add_files -fileset sim_1 $run_dir/tb_reset_integration.sv
set_property top tb_reset_integration [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set_property xsim.simulate.wdb {} [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -mode behavioral
close_sim
close_project
exit
