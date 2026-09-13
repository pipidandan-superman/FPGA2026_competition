# Replace the previous control/transparent bridge with AXI action output.
# Caller sets run_dir; current project and prior artifacts are snapshotted first.
set repo E:/competition
set project_dir $repo/2_fpga/0_diaplay_test/proj/display_test_zynq7020_school
open_project $project_dir/display_test_zynq7020_school.xpr
set rtl $repo/2_fpga/2_axi_lite_test/rtl
foreach name {axi_lite_slave axi_action_reg_bank action_uart_tx action_command_executor axi_action_control_top} {
    if {![llength [get_files -quiet $rtl/$name.v]]} {add_files -norecurse $rtl/$name.v}
}
# Resolve old module refs while opening a pre-v1 BD. They are removed below.
foreach legacy [list $rtl/axi_lite_reg_bank.v $rtl/reg_test_executor.v $rtl/axi_lite_test_top.v $repo/2_fpga/0_diaplay_test/rtl/control/video_axi_lite_control_top.v $repo/2_fpga/1_ble_test/rtl/ble_uart_debug_top.v] {
    if {![llength [get_files -quiet $legacy]]} {add_files -norecurse $legacy}
}
set wrapper $repo/2_fpga/0_diaplay_test/rtl/control/video_axi_action_uart_top.v
if {![llength [get_files -quiet $wrapper]]} {add_files -norecurse $wrapper}
set xdc $repo/2_fpga/2_axi_lite_test/proj/action_v1_pins.xdc
if {![llength [get_files -quiet $xdc]]} {add_files -fileset constrs_1 $xdc}
set clock_xdc $repo/2_fpga/0_diaplay_test/proj/action_v1_clock_impl.xdc
if {![llength [get_files -quiet $clock_xdc]]} {add_files -fileset constrs_1 $clock_xdc}
set_property USED_IN_SYNTHESIS false [get_files $clock_xdc]
set_property USED_IN_IMPLEMENTATION true [get_files $clock_xdc]
update_compile_order -fileset sources_1
open_bd_design [get_files display_test.bd]
write_bd_tcl -force $run_dir/before.tcl
foreach cell {ble_uart_bridge_0 axi_lite_test_0} {
    if {[llength [get_bd_cells -quiet $cell]]} {delete_bd_objs [get_bd_cells $cell]}
}
foreach port {PL_RS232_RX PL_RS232_TX BT_TX BT_RX FPGA_BT_3V3 BT_RESET_N} {
    if {[llength [get_bd_ports -quiet $port]]} {delete_bd_objs [get_bd_ports $port]}
}
foreach name {ble_uart_debug_top.v video_axi_lite_control_top.v axi_lite_test_top.v axi_lite_reg_bank.v reg_test_executor.v} {
    set files [get_files -quiet */$name]
    if {[llength $files]} {remove_files $files}
}
if {![llength [get_bd_cells -quiet axi_action_0]]} {
    create_bd_cell -type module -reference video_axi_action_uart_top axi_action_0
}
set_property CONFIG.NUM_MI 2 [get_bd_cells axi_smc]
set old [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins axi_smc/M01_AXI]]
set current [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins axi_action_0/S_AXI]]
if {[llength $current]} {
    if {$current ne $old} {error "Action slave is connected to an unexpected master"}
} elseif {[llength $old]} {
    # The old slave was removed above. Delete only its dangling interface net.
    set endpoints [get_bd_intf_pins -of_objects $old]
    if {[llength $endpoints] != 1 ||
        $endpoints ne "/axi_smc/M01_AXI"} {error "Unexpected control net endpoints: $endpoints"}
    delete_bd_objs $old
}
if {![llength $current]} {
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M01_AXI] [get_bd_intf_pins axi_action_0/S_AXI]
}
foreach {source target} {processing_system7_0/FCLK_CLK0 axi_action_0/clk rst_ps7_0_50M/peripheral_aresetn axi_action_0/resetn} {
    set net [get_bd_nets -quiet -of_objects [get_bd_pins $target]]
    if {![llength $net]} {
        connect_bd_net [get_bd_pins $source] [get_bd_pins $target]
    } elseif {$net ne [get_bd_nets -of_objects [get_bd_pins $source]]} {
        error "Wrong clock/reset for $target"
    }
}
foreach name {PL_RS232_TX ACTION_LED} {
    set pin [get_bd_pins axi_action_0/$name]
    if {![llength [get_bd_ports -quiet $name]]} {
        make_bd_pins_external $pin
        set_property name $name [get_bd_ports -of_objects [get_bd_nets -of_objects $pin]]
    } elseif {[get_bd_nets -of_objects [get_bd_ports $name]] ne
              [get_bd_nets -of_objects $pin]} {error "Wrong external action port $name"}
}
set segments [get_bd_addr_segs -of_objects [get_bd_intf_pins axi_action_0/S_AXI]]
assign_bd_address -offset 0x43C00000 -range 4K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] $segments -force
# Prove both the declared polarity and the actual inactive constant.
set rst [get_bd_cells rst_ps7_0_50M]
if {[get_property CONFIG.C_AUX_RESET_HIGH $rst] != 0 ||
    [get_property CONFIG.C_EXT_RESET_HIGH $rst] != 0} {error "Reset polarity changed"}
foreach {pin constant value} {aux_reset_in control_const_one 1 dcm_locked control_const_one 1 mb_debug_sys_rst control_const_zero 0} {
    if {[get_property CONFIG.CONST_VAL [get_bd_cells $constant]] != $value ||
        [get_bd_nets -of_objects [get_bd_pins rst_ps7_0_50M/$pin]] ne
        [get_bd_nets -of_objects [get_bd_pins $constant/dout]]} {error "Unsafe reset $pin"}
}
validate_bd_design
save_bd_design
write_bd_tcl -force $run_dir/recreate_bd.tcl
generate_target all [get_files display_test.bd]
puts "ACTION_MAIN_BD_PASS"
puts "EES_VIVADO_RESULT PASS"
close_project
exit
