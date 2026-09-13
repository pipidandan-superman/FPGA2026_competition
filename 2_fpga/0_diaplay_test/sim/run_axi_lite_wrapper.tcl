# Reproduce the bounded RTL simulation of the main-project AXI wrapper.
# Usage: vivado -mode batch -source run_axi_lite_wrapper.tcl -tclargs <new-run-dir>

if {$argc != 1} {
    error "Usage: run_axi_lite_wrapper.tcl <new-run-dir>"
}
set run_dir [file normalize [lindex $argv 0]]
if {[file exists $run_dir]} {
    error "Evidence directory already exists: $run_dir"
}
file mkdir $run_dir
set script_dir [file dirname [file normalize [info script]]]
set main_root [file dirname $script_dir]
set repo_root [file dirname [file dirname $main_root]]
set axilt_rtl [file join $repo_root 2_fpga 2_axi_lite_test rtl]

cd $run_dir
create_project -force main_axi_wrapper_sim [file join $run_dir work] \
    -part xc7z020clg484-1
add_files [list \
    [file join $axilt_rtl axi_lite_slave.v] \
    [file join $axilt_rtl axi_lite_reg_bank.v] \
    [file join $axilt_rtl reg_test_executor.v] \
    [file join $axilt_rtl axi_lite_test_top.v] \
    [file join $main_root rtl control video_axi_lite_control_top.v]]
add_files -fileset sim_1 [file join $script_dir tb_video_axi_lite_control.sv]
set_property top tb_video_axi_lite_control [get_filesets sim_1]
launch_simulation
run 101 us
close_sim
puts "EES_VIVADO_RESULT PASS"
close_project
exit
