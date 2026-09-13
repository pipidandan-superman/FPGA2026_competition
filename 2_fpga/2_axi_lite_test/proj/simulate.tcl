# Called from a run-local wrapper; no generated project files in the source tree.
cd $run_dir
create_project axilt_sim [file join $run_dir vivado] -part xc7z020clg484-1 -force
set_property target_language Verilog [current_project]
if {$run_mode eq "smoke"} {
    add_files -fileset sim_1 [file join $source_dir sim tb_smoke.sv]
    set_property top tb_smoke [get_filesets sim_1]
} else {
    add_files [glob [file join $source_dir rtl *.v]]
    add_files -fileset sim_1 [file join $source_dir sim tb_axi_lite.sv]
    add_files -fileset sim_1 [file join $source_dir sim tb_slave_delay.sv]
    set_property top tb_axi_lite [get_filesets sim_1]
}
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set_property xsim.simulate.wdb {} [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
exit
