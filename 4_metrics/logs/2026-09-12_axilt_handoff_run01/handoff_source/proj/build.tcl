cd $run_dir
create_project axilt_hw [file join $run_dir vivado] -part xc7z020clg484-1 -force
set_property target_language Verilog [current_project]
add_files [glob [file join $source_dir rtl *.v]]
create_bd_design axilt
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
source [file join $run_dir ps_config.tcl]
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
set sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 control_interconnect]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $sc
set csr [create_bd_cell -type module -reference axi_lite_test_top axi_lite_test_0]
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 control_reset]
set one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_one]
set_property CONFIG.CONST_VAL {1} $one
set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero]
set_property CONFIG.CONST_VAL {0} $zero
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins control_interconnect/aclk] [get_bd_pins control_reset/slowest_sync_clk] [get_bd_pins axi_lite_test_0/clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins control_reset/ext_reset_in]
connect_bd_net [get_bd_pins const_one/dout] [get_bd_pins control_reset/dcm_locked]
connect_bd_net [get_bd_pins const_zero/dout] [get_bd_pins control_reset/aux_reset_in] [get_bd_pins control_reset/mb_debug_sys_rst]
connect_bd_net [get_bd_pins control_reset/peripheral_aresetn] [get_bd_pins axi_lite_test_0/resetn] [get_bd_pins control_interconnect/aresetn]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins control_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins control_interconnect/M00_AXI] [get_bd_intf_pins axi_lite_test_0/S_AXI]
set segments [get_bd_addr_segs -of_objects [get_bd_intf_pins axi_lite_test_0/S_AXI]]
puts "CSR_SEGMENTS $segments"
if {[llength $segments] != 1} {error "Expected one CSR segment"}
assign_bd_address -offset 0x43C00000 -range 4K -target_address_space [get_bd_addr_spaces ps7/Data] $segments -force
validate_bd_design
if {[get_property CONFIG.C_EXT_RESET_HIGH $rst] != 0} {error "Reset polarity mismatch"}
save_bd_design
report_property $ps -file [file join $run_dir ps_properties.txt]
report_property [get_bd_addr_segs ps7/Data/*] -file [file join $run_dir address_properties.txt]
set bd [get_files axilt.bd]
generate_target all $bd
make_wrapper -files $bd -top
add_files [file join $run_dir vivado axilt_hw.gen sources_1 bd axilt hdl axilt_wrapper.v]
set_property top axilt_wrapper [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_utilization -file [file join $run_dir utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $run_dir timing.rpt]
report_drc -file [file join $run_dir drc.rpt]
report_cdc -file [file join $run_dir cdc.rpt]
report_route_status -file [file join $run_dir route.rpt]
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]] != 0} {error "Black boxes"}
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] == 0 || [llength $hold] == 0} {error "Missing timing paths"}
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {error "Negative timing slack"}
if {[llength [get_drc_violations -filter {SEVERITY == Error}]] != 0} {error "DRC errors"}
file mkdir [file join $run_dir release]
write_hw_platform -fixed -include_bit -force -file [file join $run_dir release axilt.xsa]
file copy -force [file join $run_dir vivado axilt_hw.runs impl_1 axilt_wrapper.bit] [file join $run_dir release axilt.bit]
file copy -force [file join $run_dir vivado axilt_hw.gen sources_1 bd axilt hw_handoff axilt.hwh] [file join $run_dir release axilt.hwh]
set out [open [file join $run_dir build_metrics.txt] w]
puts $out "SETUP_SLACK [get_property SLACK $setup]"
puts $out "HOLD_SLACK [get_property SLACK $hold]"
puts $out "BLACKBOX_COUNT 0"
puts $out "DRC_ERROR_COUNT 0"
close $out
puts "EES_VIVADO_RESULT PASS"
close_project
exit
