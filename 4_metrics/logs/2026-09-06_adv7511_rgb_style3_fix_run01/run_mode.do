transcript file E:/competition/4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01/modelsim_transcript_mode.txt
if {![file exists rgb_style3_mode_lib]} { vlib rgb_style3_mode_lib }
vlog -work rgb_style3_mode_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table.sv
vlog -work rgb_style3_mode_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work rgb_style3_mode_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work rgb_style3_mode_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work rgb_style3_mode_lib E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work rgb_style3_mode_lib -sv E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/ila_0_stub.sv
vlog -work rgb_style3_mode_lib E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/vtc_480p_1ppc.v
vlog -work rgb_style3_mode_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/rgb2ycbcr422.sv
vlog -work rgb_style3_mode_lib E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_colorbar_vtc_top.v
vlog -work rgb_style3_mode_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_colorbar_vtc_top_mode_tb.sv
vsim -voptargs=+acc -wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01/mode_style3.wlf rgb_style3_mode_lib.hdmi_colorbar_vtc_top_mode_tb
log -r /*
run -all
