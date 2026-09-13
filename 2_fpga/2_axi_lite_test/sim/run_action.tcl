# Run-local wrapper sets run_dir and source_dir; no source-tree products.
cd $run_dir
create_project action_sim $run_dir/project -part xc7z020clg484-1 -force
foreach name {axi_lite_slave axi_action_reg_bank action_uart_tx action_command_executor axi_action_control_top} {
    add_files $source_dir/rtl/$name.v
}
add_files -fileset sim_1 $source_dir/sim/tb_axi_action.sv
set_property top tb_axi_action [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set_property xsim.simulate.wdb {} [get_filesets sim_1]
launch_simulation
close_sim
close_project
exit
