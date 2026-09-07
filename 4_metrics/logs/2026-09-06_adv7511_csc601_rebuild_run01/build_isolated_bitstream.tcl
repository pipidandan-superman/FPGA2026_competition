set run_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $run_dir vivado_build hdmi_csc601]]
set rtl_dir [file normalize E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new]

create_project hdmi_csc601 $project_dir -part xc7z020clg484-1 -force

set source_files [list \
    [file join $rtl_dir hdmi_colorbar_vtc_top.v] \
    [file join $rtl_dir vtc_480p_1ppc.v] \
    [file join $rtl_dir rgb2ycbcr422.sv] \
    [file join $rtl_dir adv7511_cfg_top.sv] \
    [file join $rtl_dir adv7511_controller.sv] \
    [file join $rtl_dir adv7511_iic_data_xfer.sv] \
    [file join $rtl_dir adv7511_init_table.sv] \
    [file join $rtl_dir ../iic/iic_protocal.v] \
]
add_files -norecurse $source_files
add_files -fileset constrs_1 -norecurse [file join $rtl_dir hdmi_colorbar_vtc_top.xdc]

create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0
set clk_wiz [get_ips clk_wiz_0]
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.NUM_OUT_CLKS {1} \
    CONFIG.CLK_OUT1_PORT {clk_out1} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_PORT {reset} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
] $clk_wiz

set_property top hdmi_colorbar_vtc_top [current_fileset]
update_compile_order -fileset sources_1
generate_target all [get_files $project_dir/hdmi_csc601.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
catch {
    export_ip_user_files -of_objects [get_files $project_dir/hdmi_csc601.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci] -no_script -sync -force -quiet
}

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "SYNTHESIS_FAILED"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "IMPLEMENTATION_OR_BITSTREAM_FAILED"
}

set bit_file [file join $project_dir hdmi_csc601.runs impl_1 hdmi_colorbar_vtc_top.bit]
if {![file exists $bit_file]} {
    error "BITSTREAM_NOT_FOUND $bit_file"
}
puts "ISOLATED_BITSTREAM_READY $bit_file"
