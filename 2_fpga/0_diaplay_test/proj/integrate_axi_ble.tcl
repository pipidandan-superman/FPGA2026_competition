# Reproducible integration of the validated AXI-Lite register block and the
# validated EES-331 transparent Bluetooth UART bridge into the video BD.
# The caller must set run_dir to an absolute evidence directory.

if {![info exists run_dir]} {
    error "run_dir must be set by the caller"
}

set repo_root E:/competition
set project_dir $repo_root/2_fpga/0_diaplay_test/proj/display_test_zynq7020_school
set project_file $project_dir/display_test_zynq7020_school.xpr
set bd_file $project_dir/display_test_zynq7020_school.srcs/sources_1/bd/display_test/display_test.bd
set axilt_rtl $repo_root/2_fpga/2_axi_lite_test/rtl
set video_rtl $repo_root/2_fpga/0_diaplay_test/rtl/control
set ble_rtl $repo_root/2_fpga/1_ble_test/rtl

proc connect_intf_checked {left right} {
    set left_net [get_bd_intf_nets -quiet -of_objects $left]
    set right_net [get_bd_intf_nets -quiet -of_objects $right]
    if {[llength $left_net] && [llength $right_net]} {
        if {$left_net ne $right_net} {
            error "Interfaces are already connected to different nets: $left $right"
        }
        return
    }
    if {[llength $left_net] || [llength $right_net]} {
        error "Only one interface endpoint is already connected: $left $right"
    }
    connect_bd_intf_net $left $right
}

proc connect_pin_checked {left right} {
    set left_net [get_bd_nets -quiet -of_objects $left]
    set right_net [get_bd_nets -quiet -of_objects $right]
    if {[llength $left_net] && [llength $right_net]} {
        if {$left_net ne $right_net} {
            error "Pins are already connected to different nets: $left $right"
        }
        return
    }
    if {[llength $left_net] || [llength $right_net]} {
        error "Only one pin endpoint is already connected: $left $right"
    }
    connect_bd_net $left $right
}

file mkdir $run_dir
open_project $project_file

set required_sources [list \
    $axilt_rtl/axi_lite_slave.v \
    $axilt_rtl/axi_lite_reg_bank.v \
    $axilt_rtl/reg_test_executor.v \
    $axilt_rtl/axi_lite_test_top.v \
    $video_rtl/video_axi_lite_control_top.v \
    $ble_rtl/ble_uart_debug_top.v]
foreach source_file $required_sources {
    if {![file exists $source_file]} {
        error "Required source missing: $source_file"
    }
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -norecurse -fileset sources_1 $source_file
    }
}
update_compile_order -fileset sources_1

open_bd_design $bd_file
file copy -force $bd_file $run_dir/before.bd

set ps [get_bd_cells processing_system7_0]
set smc [get_bd_cells axi_smc]
set reset_ip [get_bd_cells rst_ps7_0_50M]
set clock_ip [get_bd_cells clk_wiz_0]
foreach required [list $ps $smc $reset_ip $clock_ip] {
    if {[llength $required] != 1} {
        error "Required baseline BD cell missing or ambiguous"
    }
}

# Keep the wizard's supported configuration stable; the implementation-level
# BUF_IN compensation required by non-CCIO M19 is applied in the project XDC.
set_property CONFIG.PLL_COMPENSATION {SYSTEM_SYNCHRONOUS} $clock_ip

# One PS GP0 master fans out to the existing VDMA control port and the new
# 4 KiB register slave. Existing M00_AXI/VDMA mapping is preserved.
set_property CONFIG.NUM_MI {2} $smc
if {[llength [get_bd_cells -quiet axi_lite_test_0]] == 0} {
    create_bd_cell -type module -reference video_axi_lite_control_top axi_lite_test_0
}
connect_intf_checked [get_bd_intf_pins axi_smc/M01_AXI] \
                     [get_bd_intf_pins axi_lite_test_0/S_AXI]
connect_pin_checked [get_bd_pins processing_system7_0/FCLK_CLK0] \
                    [get_bd_pins axi_lite_test_0/clk]
connect_pin_checked [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] \
                    [get_bd_pins axi_lite_test_0/resetn]

set axilt_segments [get_bd_addr_segs -of_objects \
    [get_bd_intf_pins axi_lite_test_0/S_AXI]]
if {[llength $axilt_segments] != 1} {
    error "Expected one AXI-Lite slave address segment, got: $axilt_segments"
}
assign_bd_address -offset 0x43C00000 -range 4K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    $axilt_segments -force

# Make the low-active proc_sys_reset inputs explicit. aux_reset_in is inactive
# high; mb_debug_sys_rst is inactive low; dcm_locked must be high for release.
if {[llength [get_bd_cells -quiet control_const_one]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 control_const_one
}
if {[llength [get_bd_cells -quiet control_const_zero]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 control_const_zero
}
set_property CONFIG.CONST_VAL {1} [get_bd_cells control_const_one]
set_property CONFIG.CONST_VAL {0} [get_bd_cells control_const_zero]
foreach pin_name {aux_reset_in dcm_locked} {
    set pin [get_bd_pins rst_ps7_0_50M/$pin_name]
    set old_net [get_bd_nets -quiet -of_objects $pin]
    if {[llength $old_net]} {
        disconnect_bd_net $old_net $pin
    }
    connect_bd_net [get_bd_pins control_const_one/dout] $pin
}
set debug_pin [get_bd_pins rst_ps7_0_50M/mb_debug_sys_rst]
set debug_net [get_bd_nets -quiet -of_objects $debug_pin]
if {[llength $debug_net]} {
    disconnect_bd_net $debug_net $debug_pin
}
connect_bd_net [get_bd_pins control_const_zero/dout] $debug_pin

# Transparent BLE bridge reuses the external 100 MHz camera reference clock
# and board reset. BRIDGE_READY stays internal because V4 belongs to cfg_done.
if {[llength [get_bd_cells -quiet ble_uart_bridge_0]] == 0} {
    create_bd_cell -type module -reference ble_uart_debug_top ble_uart_bridge_0
}
connect_pin_checked [get_bd_ports clk_in1_0] [get_bd_pins ble_uart_bridge_0/SYS_CLK]
connect_pin_checked [get_bd_ports resetn_0] [get_bd_pins ble_uart_bridge_0/SYS_RST_N]
foreach pin_name {PL_RS232_RX PL_RS232_TX BT_TX BT_RX FPGA_BT_3V3 BT_RESET_N} {
    set module_pin [get_bd_pins ble_uart_bridge_0/$pin_name]
    set external_port [get_bd_ports -quiet $pin_name]
    if {[llength $external_port] == 0} {
        make_bd_pins_external $module_pin
        set module_net [get_bd_nets -of_objects $module_pin]
        set external_port [get_bd_ports -of_objects $module_net]
        if {[llength $external_port] != 1} {
            error "Failed to create one external port for $pin_name"
        }
        set_property name $pin_name $external_port
    } else {
        connect_pin_checked $external_port $module_pin
    }
}

validate_bd_design

if {[get_property CONFIG.C_AUX_RESET_HIGH $reset_ip] != 0} {
    error "Unexpected aux reset polarity"
}
if {[get_bd_nets -of_objects [get_bd_pins rst_ps7_0_50M/aux_reset_in]] ne \
    [get_bd_nets -of_objects [get_bd_pins control_const_one/dout]]} {
    error "aux_reset_in is not tied inactive high"
}

set axilt_map [get_bd_addr_segs -quiet -of_objects \
    [get_bd_addr_spaces processing_system7_0/Data] \
    -filter {NAME =~ "*axi_lite_test_0*"}]
if {[llength $axilt_map] != 1 || \
    [expr {[get_property OFFSET $axilt_map] != 0x43C00000}] || \
    [expr {[get_property RANGE $axilt_map] != 4096}]} {
    error "AXI-Lite address mapping contract failed"
}

save_bd_design
write_bd_tcl -force $run_dir/recreate_display_test.tcl
file copy -force $bd_file $run_dir/after.bd

set contract [open $run_dir/bd_contract.txt w]
puts $contract "BD display_test"
puts $contract "AXI_LITE_CELL axi_lite_test_0"
puts $contract "AXI_LITE_OFFSET [get_property OFFSET $axilt_map]"
puts $contract "AXI_LITE_RANGE [get_property RANGE $axilt_map]"
puts $contract "CONTROL_CLOCK_HZ 50000000"
puts $contract "M19_PLL_COMPENSATION XDC_BUF_IN"
puts $contract "BLE_CELL ble_uart_bridge_0"
puts $contract "BLE_READY_EXTERNAL false"
puts $contract "RESET_AUX_ACTIVE_LOW_TIED_HIGH true"
close $contract

generate_target all [get_files display_test.bd]
puts "MAIN_BD_INTEGRATION_PASS"
puts "EES_VIVADO_RESULT PASS"
close_project
exit
