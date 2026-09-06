transcript file E:/competition/4_metrics/logs/2026-09-06_hdmi_style1_mode_tb_run01/modelsim_transcript.txt
if {![file exists mode_style1_lib]} { vlib mode_style1_lib }
vlog -work mode_style1_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv
vlog -work mode_style1_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work mode_style1_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work mode_style1_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work mode_style1_lib E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work mode_style1_lib -sv E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/ila_0_stub.sv
vlog -work mode_style1_lib E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/vtc_480p_1ppc.v
vlog -work mode_style1_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/rgb2ycbcr422.sv
vlog -work mode_style1_lib E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_colorbar_vtc_top.v
vlog -work mode_style1_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_colorbar_vtc_top_mode_tb.sv
vsim -voptargs=+acc -wlf E:/competition/4_metrics/logs/2026-09-06_hdmi_style1_mode_tb_run01/mode_style1.wlf mode_style1_lib.hdmi_colorbar_vtc_top_mode_tb
log -r /*
run -all
