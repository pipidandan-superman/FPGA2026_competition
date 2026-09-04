transcript file E:/competition/7_logs/2026-09-04/hdmi_adv_input_style_sim_run03/modelsim_transcript.txt
if {![file exists adv_input_style_sim_lib]} { vlib adv_input_style_sim_lib }
vlog -work adv_input_style_sim_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv
vlog -work adv_input_style_sim_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work adv_input_style_sim_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work adv_input_style_sim_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work adv_input_style_sim_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work adv_input_style_sim_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/adv7511_cfg_top_tb.sv
vsim -voptargs=+acc adv_input_style_sim_lib.adv7511_cfg_top_tb
log -r /*
run -all
