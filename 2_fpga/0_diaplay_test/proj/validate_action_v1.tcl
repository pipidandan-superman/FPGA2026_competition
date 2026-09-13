open_project E:/competition/2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr
open_bd_design [get_files display_test.bd]
# Removed bridge ports leave empty nets in Vivado; discard only nets with no endpoints.
foreach net [get_bd_nets -quiet *ble_uart_bridge*] {
    if {![llength [get_bd_pins -quiet -of_objects $net]] &&
        ![llength [get_bd_ports -quiet -of_objects $net]]} {delete_bd_objs $net}
}
foreach pin {processing_system7_0/FCLK_CLK0 axi_smc/aclk axi_action_0/clk} {
    report_property [get_bd_pins $pin]
}
report_property [get_bd_intf_pins axi_action_0/S_AXI]
validate_bd_design
if {[get_property CONFIG.FREQ_HZ [get_bd_pins axi_action_0/clk]] != 50000000} {
    error "Action clock frequency contract"
}
if {[get_bd_nets -of_objects [get_bd_pins axi_action_0/clk]] ne
    [get_bd_nets -of_objects [get_bd_pins processing_system7_0/FCLK_CLK0]]} {
    error "Action clock connectivity contract"
}
set segment [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data] -filter {NAME =~ "*axi_action_0*"}]
if {[llength $segment] != 1 || [get_property OFFSET $segment] != 0x43C00000 ||
    [get_property RANGE $segment] != 4096} {error "CSR mapping"}
save_bd_design
generate_target all [get_files display_test.bd]
write_bd_tcl -force $run_dir/recreate_bd.tcl
puts "ACTION_MAIN_BD_PASS"
puts "EES_VIVADO_RESULT PASS"
close_project
exit
