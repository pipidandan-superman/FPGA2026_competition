transcript file E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/modelsim_transcript_mismatch_yuv422.txt
catch {quit -sim}
vmap cfg_yuv422_lib E:/competition/cfg_yuv422_lib
vsim -voptargs=+acc -wlf E:/competition/4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01/mismatch_yuv422.wlf cfg_yuv422_lib.adv7511_cfg_top_mismatch_tb
log -r /*
run -all
