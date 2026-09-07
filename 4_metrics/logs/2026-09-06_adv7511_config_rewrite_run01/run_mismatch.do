transcript file E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/modelsim_transcript_mismatch.txt
catch {quit -sim}
vmap cfg_rewrite_lib02 E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/cfg_rewrite_lib02
vsim -voptargs=+acc -wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/mismatch_corrected.wlf cfg_rewrite_lib02.adv7511_cfg_top_mismatch_tb
log -r /*
run -all
