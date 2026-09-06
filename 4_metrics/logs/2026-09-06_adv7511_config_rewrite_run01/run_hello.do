if {![file exists cfg_rewrite_lib05]} { vlib cfg_rewrite_lib05 }
vlog -work cfg_rewrite_lib05 -sv E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/hello_tb.sv
vsim -wlf hello.wlf cfg_rewrite_lib05.hello_tb
run -all
