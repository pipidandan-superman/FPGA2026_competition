set run_root E:/competition/4_metrics/logs/2026-09-12_pl_uart_bridge_build_run02
set rtl_root E:/competition/2_fpga/1_ble_test/rtl
set sim_root E:/competition/2_fpga/1_ble_test/sim
set project_root E:/competition/2_fpga/1_ble_test/proj/ble_uart_debug_vivado_2025_2
cd $run_root
if {[file exists $project_root]} {error "Refusing to overwrite existing project"}
if {[catch {
    create_project bridge_sim $run_root/sim_project -part xc7z020clg484-1
    add_files -fileset sim_1 -norecurse [list $rtl_root/ble_uart_debug_top.v \
        $rtl_root/uart_rx.v $sim_root/tb_ble_uart_debug_top.v]
    set_property top tb_ble_uart_debug_top [get_filesets sim_1]
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
    set_property xsim.simulate.wdb NUL [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation
    run all
    close_sim
    set fp [open $run_root/sim_project/bridge_sim.sim/sim_1/behav/xsim/simulate.log r]
    set content [read $fp]
    close $fp
    if {[string first "BLE_UART_BRIDGE_SIM_PASS host=18 module=13" $content] < 0} {
        error "Required simulation runtime result missing"
    }
    close_project
    puts "EES_VIVADO_STAGE SIMULATION_PASS"

    create_project ble_uart_debug_vivado_2025_2 $project_root -part xc7z020clg484-1
    set_property target_language Verilog [current_project]
    add_files -norecurse $rtl_root/ble_uart_debug_top.v
    add_files -fileset constrs_1 -norecurse $rtl_root/ees331_ble_uart_debug.xdc
    set_property top ble_uart_debug_top [get_filesets sources_1]
    update_compile_order -fileset sources_1
    set fp [open $run_root/project_sources.txt w]
    foreach f [get_files] {puts $fp $f}
    close $fp
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis incomplete"}
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation incomplete"}
    open_run impl_1
    report_timing_summary -delay_type min_max -report_unconstrained -file $run_root/timing_summary.rpt
    report_utilization -file $run_root/utilization.rpt
    report_drc -file $run_root/drc.rpt
    report_route_status -file $run_root/route_status.rpt
    report_cdc -file $run_root/cdc.rpt
    report_io -file $run_root/io.rpt
    set setup [get_timing_paths -delay_type max -max_paths 1]
    set hold [get_timing_paths -delay_type min -max_paths 1]
    if {[llength $setup] != 1 || [llength $hold] != 1} {error "Timing paths unavailable"}
    set wns [get_property SLACK $setup]
    set whs [get_property SLACK $hold]
    if {$wns < 0 || $whs < 0} {error "Timing failed WNS=$wns WHS=$whs"}
    if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]] > 0} {error "DRC errors"}
    set bit $project_root/ble_uart_debug_vivado_2025_2.runs/impl_1/ble_uart_debug_top.bit
    if {![file exists $bit]} {error "Bitstream missing"}
    set fp [open $run_root/build_summary.txt w]
    puts $fp "BLE_UART_DEBUG_BUILD_PASS\nWNS=$wns\nWHS=$whs\nBITSTREAM=$bit"
    close $fp
    close_project
} failure]} {
    puts "EES_VIVADO_RESULT FAIL: $failure"
    catch {close_sim}
    catch {close_project}
    exit 1
}
puts "EES_VIVADO_RESULT PASS"
exit 0
