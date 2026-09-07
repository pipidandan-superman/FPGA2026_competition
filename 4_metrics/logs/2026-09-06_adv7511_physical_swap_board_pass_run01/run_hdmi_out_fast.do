transcript file E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/modelsim_hdmi_out_transcript.txt
if {![file exists E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib]} { vlib E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib }
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/oddr_sim_model.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib -sv E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/ila_0_stub.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/rgb2ycbcr422.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_out_adv7511.v
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_out_adv7511_tb.sv
vsim -voptargs=+acc -wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_physical_swap.wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/hdmi_out_swap_lib.hdmi_out_adv7511_fast_tb
log -r /*
run -all
