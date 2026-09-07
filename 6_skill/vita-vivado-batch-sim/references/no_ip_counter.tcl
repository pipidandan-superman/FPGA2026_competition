if {![info exists ::env(EES_VIVADO_RUN_DIR)]} {
  error "EES_VIVADO_RUN_DIR is required; set it to E:/competition/4_metrics/logs/YYYY-MM-DD_<task>_runNN"
}
set run_dir [file normalize $::env(EES_VIVADO_RUN_DIR)]
file mkdir $run_dir
set skill_dir [file normalize [file join [file dirname [info script]] ..]]
set src "E:/competition/4_metrics/references/simple_counter.v"
set tb [file join $skill_dir references no_ip_counter_tb.sv]
create_project -force ees_batch_no_ip [file join $run_dir project] -part xc7z020clg484-1
add_files $src
add_files -fileset sim_1 $tb
set_property top no_ip_counter_tb [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -mode behavioral -simset sim_1
close_sim
close_project
