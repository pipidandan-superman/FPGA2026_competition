transcript file E:/competition/4_metrics/logs/2026-09-06_adv7511_csc601_rebuild_run01/modelsim_table_dump_transcript.txt
if {![file exists csc601_table_lib]} { vlib csc601_table_lib }
vlog -work csc601_table_lib -sv E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table.sv
vlog -work csc601_table_lib -sv E:/competition/4_metrics/logs/2026-09-06_adv7511_csc601_rebuild_run01/adv7511_init_table_dump_tb.sv
vsim -voptargs=+acc -wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_csc601_rebuild_run01/table_dump_fresh.wlf csc601_table_lib.adv7511_init_table_dump_tb
log -r /*
run -all
