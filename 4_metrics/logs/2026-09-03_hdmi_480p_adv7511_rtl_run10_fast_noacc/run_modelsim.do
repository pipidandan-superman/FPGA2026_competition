transcript file E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/modelsim_transcript.txt

if {![file exists E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib]} {
    vlib E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib
}

vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_new/oddr_sim_model.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/rgb2ycbcr422.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_i2c_init.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_out_adv7511.sv
vlog -work E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_new/hdmi_out_adv7511_tb.sv

vsim -gFAST_SIM=1 E:/competition/4_metrics/logs/2026-09-03_hdmi_480p_adv7511_rtl_run10_fast_noacc/hdmi_rtl_run10_fast_noacc_lib.hdmi_out_adv7511_tb
run -all









