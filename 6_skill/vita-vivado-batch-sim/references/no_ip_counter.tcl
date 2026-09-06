set run_dir [file normalize [pwd]]
set skill_dir [file normalize [file join [file dirname [info script]] ..]]
set src "D:/VitA/6_proj/vitis_test/vitis_bd_test/vitis_bd_test.srcs/sources_1/new/simple_counter.v"
set tb [file join $skill_dir references no_ip_counter_tb.sv]
create_project -force vita_batch_no_ip [file join $run_dir project] -part xc7z020clg400-1
add_files $src
add_files -fileset sim_1 $tb
set_property top no_ip_counter_tb [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -mode behavioral -simset sim_1
close_sim
close_project
