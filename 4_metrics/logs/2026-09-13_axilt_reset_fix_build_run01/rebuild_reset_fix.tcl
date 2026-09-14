# Run with run_dir set to a fresh, absolute evidence directory.
cd $run_dir
set sim_log E:/competition/4_metrics/logs/2026-09-13_axilt_reset_sim_run01/vivado_console.log
set f [open $sim_log r]
set passed [read $f]
close $f
if {![regexp {\nAXILT_OFFICIAL_RESET_PASS } $passed]} {error "Official reset simulation required"}
set project_dir E:/competition/2_fpga/2_axi_lite_test/proj
set project_name AXI_LITE_test
set design_name AXI_LITE_test
set artifact_stem AXI_LITE_test
open_project $project_dir/AXI_LITE_test.xpr
open_bd_design [get_files AXI_LITE_test.bd]
set aux [get_bd_pins control_reset/aux_reset_in]
set rst [get_bd_cells control_reset]
set old_net [get_bd_nets -of_objects $aux]
set one_net [get_bd_nets -of_objects [get_bd_pins const_one/dout]]
if {$old_net ne $one_net} {
    if {$old_net ne [get_bd_nets -of_objects [get_bd_pins const_zero/dout]]} {error "Unexpected aux connection"}
    disconnect_bd_net $old_net $aux
    connect_bd_net [get_bd_pins const_one/dout] $aux
}
validate_bd_design
if {[get_property CONFIG.C_EXT_RESET_HIGH $rst] != 0 || [get_property CONFIG.C_AUX_RESET_HIGH $rst] != 0} {error "Reset polarity changed"}
if {[get_bd_nets -of_objects $aux] ne $one_net} {error "Aux reset not tied high"}
puts "AXILT_BD_RESET_CONTRACT_PASS aux_active_low_tied_high"
save_bd_design
write_bd_tcl -force $run_dir/recreate_bd.tcl
file copy -force [get_property NAME [get_files AXI_LITE_test.bd]] $run_dir/after.bd
generate_target all [get_files AXI_LITE_test.bd]
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_utilization -file $run_dir/utilization.rpt
report_timing_summary -report_unconstrained -file $run_dir/timing.rpt
report_drc -file $run_dir/drc.rpt
report_cdc -file $run_dir/cdc.rpt
report_route_status -file $run_dir/route.rpt
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]]} {error "Black boxes"}
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] == 0 || [llength $hold] == 0} {error "Missing timing paths"}
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {error "Negative timing slack"}
if {[llength [get_drc_violations -filter {SEVERITY == Error}]]} {error "DRC errors"}
file mkdir $run_dir/release
write_hw_platform -fixed -include_bit -force -file $run_dir/release/AXI_LITE_test.xsa
file copy $project_dir/AXI_LITE_test.runs/impl_1/AXI_LITE_test_wrapper.bit $run_dir/release/AXI_LITE_test.bit
file copy $project_dir/AXI_LITE_test.gen/sources_1/bd/AXI_LITE_test/hw_handoff/AXI_LITE_test.hwh $run_dir/release/AXI_LITE_test.hwh
set out [open $run_dir/build_metrics.txt w]
puts $out "SETUP_SLACK [get_property SLACK $setup]"
puts $out "HOLD_SLACK [get_property SLACK $hold]"
puts $out "BLACKBOX_COUNT 0"
puts $out "DRC_ERROR_COUNT 0"
close $out
puts "EES_VIVADO_RESULT PASS"
close_project
exit
