# Caller sets a new run_dir. Build only after action simulation and BD gates pass.
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file join $script_dir display_test_zynq7020_school]
set project_file [file join $project_dir display_test_zynq7020_school.xpr]
file mkdir $run_dir/release
open_project $project_file
set clock_xdc [file join $script_dir action_v1_clock_impl.xdc]
if {![llength [get_files -quiet $clock_xdc]]} {
    add_files -fileset constrs_1 $clock_xdc
}
set_property USED_IN_SYNTHESIS false [get_files $clock_xdc]
set_property USED_IN_IMPLEMENTATION true [get_files $clock_xdc]
set_property source_mgmt_mode All [current_project]
open_bd_design [get_files display_test.bd]
validate_bd_design
save_bd_design
generate_target all [get_files display_test.bd]
make_wrapper -files [get_files display_test.bd] -top

set wrapper_file [file join $project_dir \
    display_test_zynq7020_school.gen sources_1 bd display_test hdl \
    display_test_wrapper.v]
if {![file exists $wrapper_file]} {
    error "display_test_wrapper file was not generated"
}
if {[llength [get_files -quiet $wrapper_file]] == 0} {
    add_files -norecurse -fileset sources_1 $wrapper_file
}
foreach wrapper_candidate [get_files -all -quiet *display_test_wrapper.v] {
    if {[string match "*sources_1/imports/hdl/display_test_wrapper.v" \
            [string map {\\ /} $wrapper_candidate]]} {
        remove_files $wrapper_candidate
    }
}
if {[llength [get_files -quiet $wrapper_file]] != 1} {
    error "display_test_wrapper was not imported exactly once"
}
update_compile_order -fileset sources_1
set_property top display_test_wrapper [get_filesets sources_1]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
write_project_tcl -force [file join $run_dir recreate_project.tcl]

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_utilization -file [file join $run_dir utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $run_dir timing.rpt]
report_drc -file [file join $run_dir drc.rpt]
report_cdc -file [file join $run_dir cdc.rpt]
report_route_status -file [file join $run_dir route_status.rpt]
report_io -file [file join $run_dir io.rpt]
check_timing -verbose -file [file join $run_dir check_timing.rpt]

set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
set m19_net [get_nets -quiet -hierarchical -filter {NAME =~ *clk_wiz_0/inst/clk_in1_display_test_clk_wiz_0_0}]
if {[llength $m19_net] != 1} {
    error "M19 implementation net missing"
}
if {[string toupper [get_property CLOCK_DEDICATED_ROUTE $m19_net]] ni {FALSE 0}} {
    error "M19 implementation routing property missing"
}
set clock_pll [get_cells -hierarchical \
    -filter {REF_NAME == PLLE2_ADV && NAME =~ *clk_wiz_0*}]
set setup_path [get_timing_paths -delay_type max -max_paths 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1]
set drc_errors [get_drc_violations -filter {SEVERITY == Error}]
if {[llength $blackboxes] != 0} {
    error "Unresolved black boxes: $blackboxes"
}
if {[llength $clock_pll] != 1 ||
        [get_property COMPENSATION $clock_pll] ne "BUF_IN"} {
    error "M19 clock PLL compensation contract failed: $clock_pll"
}
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
    error "Timing paths missing"
}
set setup_slack [get_property SLACK $setup_path]
set hold_slack [get_property SLACK $hold_path]
if {$setup_slack < 0 || $hold_slack < 0} {
    error "Negative timing slack: setup=$setup_slack hold=$hold_slack"
}
if {[llength $drc_errors] != 0} {
    error "DRC errors: $drc_errors"
}

set bit_file [file join $project_dir \
    display_test_zynq7020_school.runs impl_1 display_test_wrapper.bit]
set hwh_file [file join $project_dir \
    display_test_zynq7020_school.gen sources_1 bd display_test hw_handoff \
    display_test.hwh]
if {![file exists $bit_file] || ![file exists $hwh_file]} {
    error "Paired BIT/HWH output missing"
}
set release_dir [file join $run_dir release]
write_hw_platform -fixed -include_bit -force \
    -file [file join $release_dir display_test_axi_action_uart.xsa]
file copy -force $bit_file \
    [file join $release_dir display_test_axi_action_uart.bit]
file copy -force $hwh_file \
    [file join $release_dir display_test_axi_action_uart.hwh]

set output [open [file join $run_dir build_metrics.txt] w]
puts $output "SETUP_SLACK $setup_slack"
puts $output "HOLD_SLACK $hold_slack"
puts $output "BLACKBOX_COUNT [llength $blackboxes]"
puts $output "DRC_ERROR_COUNT [llength $drc_errors]"
puts $output "M19_PLL_COMPENSATION [get_property COMPENSATION $clock_pll]"
puts $output "AXI_LITE_OFFSET 0x43C00000"
puts $output "AXI_LITE_RANGE 0x00001000"
puts $output "VDMA_OFFSET 0x43000000"
puts $output "CONTROL_CLOCK_HZ 50000000"
puts $output "ACTION_UART_BAUD 9600"
puts $output "ACTION_LED_COUNT 7"
puts $output "BLE_PRESENT false"
close $output

puts "ACTION_MAIN_BUILD_PASS setup=$setup_slack hold=$hold_slack"
puts "EES_VIVADO_RESULT PASS"
close_project
exit
