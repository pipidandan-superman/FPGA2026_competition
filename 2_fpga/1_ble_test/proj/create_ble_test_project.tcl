set project_name "ble_test_vivado_2025_2"
set project_root "E:/competition/2_fpga/1_ble_test/proj/${project_name}"
set rtl_root "E:/competition/2_fpga/1_ble_test/rtl"
set evidence_base "E:/competition/4_metrics/logs"
set run_date [clock format [clock seconds] -format "%Y-%m-%d"]
set run_index 1
while {1} {
    set run_name [format "%s_ble_vivado_build_run%02d" $run_date $run_index]
    set evidence_root "${evidence_base}/${run_name}"
    if {![file exists $evidence_root]} {
        break
    }
    incr run_index
}

file mkdir $evidence_root

create_project $project_name $project_root -part xc7z020clg484-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property source_mgmt_mode All [current_project]

add_files -fileset sources_1 -norecurse [list \
    "${rtl_root}/uart_tx.v" \
    "${rtl_root}/uart_rx.v" \
    "${rtl_root}/ble_at_test_ctrl.v" \
    "${rtl_root}/ble_test_top.v" \
]
set_property top ble_test_top [get_filesets sources_1]

add_files -fileset constrs_1 -norecurse \
    "${rtl_root}/ees331_ble_test.xdc"
set_property target_constrs_file \
    "${rtl_root}/ees331_ble_test.xdc" [get_filesets constrs_1]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
    -module_name ila_0
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {14} \
    CONFIG.C_DATA_DEPTH {65536} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_INPUT_PIPE_STAGES {0} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {8} \
    CONFIG.C_PROBE3_WIDTH {8} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {4} \
    CONFIG.C_PROBE10_WIDTH {1} \
    CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} \
    CONFIG.C_PROBE13_WIDTH {1} \
] [get_ips ila_0]
generate_target all [get_ips ila_0]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set source_report [open "${evidence_root}/project_sources.txt" w]
puts $source_report "PROJECT=[current_project]"
puts $source_report "PART=[get_property PART [current_project]]"
puts $source_report "TOP=[get_property TOP [get_filesets sources_1]]"
puts $source_report "DESIGN_SOURCES"
foreach source_file [get_files -of_objects [get_filesets sources_1]] {
    puts $source_report [file normalize $source_file]
}
puts $source_report "CONSTRAINT_SOURCES"
foreach constraint_file [get_files -of_objects [get_filesets constrs_1]] {
    puts $source_report [file normalize $constraint_file]
}
close $source_report

launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status] || ($synth_progress ne "100%")} {
    error "SYNTHESIS_FAILED: status=$synth_status progress=$synth_progress"
}

open_run synth_1
report_utilization -hierarchical -file \
    "${evidence_root}/post_synth_utilization.rpt"
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 10 -file \
    "${evidence_root}/post_synth_timing_summary.rpt"
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status] || ($impl_progress ne "100%")} {
    error "IMPLEMENTATION_FAILED: status=$impl_status progress=$impl_progress"
}

open_run impl_1
report_utilization -hierarchical -file \
    "${evidence_root}/post_route_utilization.rpt"
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 10 -file \
    "${evidence_root}/post_route_timing_summary.rpt"
report_drc -file "${evidence_root}/post_route_drc.rpt"
report_methodology -file "${evidence_root}/post_route_methodology.rpt"

set setup_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
set build_summary [open "${evidence_root}/build_summary.txt" w]
puts $build_summary "SYNTH_STATUS=$synth_status"
puts $build_summary "SYNTH_PROGRESS=$synth_progress"
puts $build_summary "IMPL_STATUS=$impl_status"
puts $build_summary "IMPL_PROGRESS=$impl_progress"
if {[llength $setup_paths] > 0} {
    puts $build_summary "WNS=[get_property SLACK $setup_paths]"
}
if {[llength $hold_paths] > 0} {
    puts $build_summary "WHS=[get_property SLACK $hold_paths]"
}
puts $build_summary "BITSTREAM=[file normalize \
    "${project_root}/${project_name}.runs/impl_1/ble_test_top.bit"]"
close $build_summary

puts "BLE_VIVADO_BUILD_PASS"
close_project
