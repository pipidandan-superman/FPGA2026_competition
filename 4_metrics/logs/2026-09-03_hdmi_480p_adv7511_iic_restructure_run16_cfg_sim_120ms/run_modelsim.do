transcript file E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/modelsim_transcript.txt

if {![file exists E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib]} {
    vlib E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib
}

vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_new/adv7511_cfg_top_tb.sv

vsim -gFAST_SIM=0 -gPOWER_UP_DELAY_MS=120 -gIIC_CLOCK_DIVIDER=252 E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_iic_restructure_run16_cfg_sim_120ms/hdmi_iic_restructure_run16_cfg_lib.adv7511_cfg_top_tb
run -all



