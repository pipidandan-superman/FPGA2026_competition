if {![file exists cfg_rewrite_lib04]} { vlib cfg_rewrite_lib04 }
vlog -work cfg_rewrite_lib04 -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv
vlog -work cfg_rewrite_lib04 -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work cfg_rewrite_lib04 -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work cfg_rewrite_lib04 -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work cfg_rewrite_lib04 E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work cfg_rewrite_lib04 -sv E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/ila_0_stub.sv
vlog -work cfg_rewrite_lib04 -sv E:/competition/2_fpga/0_diaplay_test/sim/adv7511_cfg_top_tb.sv
vsim -wlf success_lib04.wlf cfg_rewrite_lib04.adv7511_cfg_top_success_tb
log -r /*
run -all
