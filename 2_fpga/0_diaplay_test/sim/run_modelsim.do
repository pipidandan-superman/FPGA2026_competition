set evidence_dir E:/competition/4_metrics/logs/2026-09-03_hdmi_sim_relocation_run20
set work_lib E:/competition/4_metrics/logs/2026-09-03_hdmi_sim_relocation_run20/hdmi_sim_relocation_run20_lib

file mkdir E:/competition/4_metrics/logs/2026-09-03_hdmi_sim_relocation_run20
transcript file E:/competition/4_metrics/logs/2026-09-03_hdmi_sim_relocation_run20/modelsim_transcript.txt

if {![file exists $work_lib]} {
    vlib $work_lib
}

vlog -work $work_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/oddr_sim_model.sv
vlog -work $work_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv
vlog -work $work_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/rgb2ycbcr422.sv
vlog -work $work_lib E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work $work_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work $work_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work $work_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work $work_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_out_adv7511.sv
vlog -work $work_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_out_adv7511_tb.sv

vsim $work_lib.hdmi_out_adv7511_tb
run -all
