set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ../../proj/hdmi_colorbar_vtc]]

create_project hdmi_colorbar_vtc $project_dir -part xc7z020clg484-1 -force

set source_files [list \
    [file join $script_dir hdmi_colorbar_vtc_top.v] \
    [file join $script_dir vtc_480p_1ppc.v] \
    [file join $script_dir hdmi_out_adv7511.v] \
    [file join $script_dir rgb2ycbcr422.sv] \
    [file join $script_dir adv7511_cfg_top.sv] \
    [file join $script_dir adv7511_controller.sv] \
    [file join $script_dir adv7511_iic_data_xfer.sv] \
    [file join $script_dir adv7511_init_table_pkg.sv] \
]
add_files -norecurse $source_files

set constraint_file [file join $script_dir hdmi_colorbar_vtc_top.xdc]
add_files -fileset constrs_1 -norecurse $constraint_file

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

generate_target all [get_files $project_dir/hdmi_colorbar_vtc.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
catch { export_ip_user_files -of_objects [get_files $project_dir/hdmi_colorbar_vtc.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci] -no_script -sync -force -quiet }

puts "HDMI_COLORBAR_PROJECT_CREATED $project_dir"
puts "TOP=hdmi_colorbar_vtc_top"
puts "Use Run Synthesis / Run Implementation / Generate Bitstream in Vivado GUI."
