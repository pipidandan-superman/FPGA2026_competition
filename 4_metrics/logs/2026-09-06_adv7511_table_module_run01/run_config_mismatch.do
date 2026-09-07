transcript file E:/competition/4_metrics/logs/2026-09-06_adv7511_table_module_run01/modelsim_transcript_mismatch.txt
if {![file exists table_module_lib_mismatch]} { vlib table_module_lib_mismatch }
vlog -work table_module_lib_mismatch -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table.sv
vlog -work table_module_lib_mismatch -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work table_module_lib_mismatch -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work table_module_lib_mismatch -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work table_module_lib_mismatch E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work table_module_lib_mismatch -sv E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/ila_0_stub.sv
vlog -work table_module_lib_mismatch -sv E:/competition/2_fpga/0_diaplay_test/sim/adv7511_cfg_top_tb.sv
vsim -voptargs=+acc -wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_table_module_run01/config_mismatch.wlf table_module_lib_mismatch.adv7511_cfg_top_mismatch_tb
log -r /*
run -all
