transcript file E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/modelsim_transcript.txt

if {![file exists E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib]} {
    vlib E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib
}

vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_new/oddr_sim_model.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/rgb2ycbcr422.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_out_adv7511.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_new/hdmi_out_adv7511_tb.sv

vsim E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_overall_sim_run19_final/hdmi_overall_run19_final_lib.hdmi_out_adv7511_tb
run -all


