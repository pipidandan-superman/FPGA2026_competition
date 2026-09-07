transcript file E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/modelsim_transcript.txt
if {![file exists E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib]} { vlib E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib }
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_controller.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_cfg_top.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib E:/competition/2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib -sv E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/ila_0_stub.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/vtc_480p_1ppc.v
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/rgb2ycbcr422.sv
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_colorbar_vtc_top.v
vlog -work E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib -sv E:/competition/2_fpga/0_diaplay_test/sim/hdmi_colorbar_vtc_top_mode_tb.sv
vsim -voptargs=+acc -wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/mode_physical_swap.wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/physical_swap_pass_lib.hdmi_colorbar_vtc_top_mode_tb
log -r /*
run -all
