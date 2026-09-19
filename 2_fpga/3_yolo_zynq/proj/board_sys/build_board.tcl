# ============================================================
# M13 board build -- yolo_sys block design (A2 loader V2)
# EES-331 XC7Z020clg484, Vivado 2025.2 batch
#   BD = ps7 (EES-331 preset) FCLK0=60MHz first-light + GP0 (CSR
#   @0x43C1_0000) + HP0 (W read + Y write) + HP1 (X read, A2);
#   DDR/FIXED_IO 显式接出; engine irq_o -> ps7/IRQ_F2P 直连
#   (用户 GUI 2026-09-18 补, v1 驱动仍轮询, 中断线留作后用)。
#   engine_top V1.1 PROD-16x16。No PL external pins (all traffic
#   via PS DDR)。
# gate : BOARD_BITSTREAM_PASS (timing WNS >= 0) + yolo_a2.xsa
# batch: vivado -mode batch -source build_board.tcl -nojournal
# ------------------------------------------------------------
# v2 (run9c 2026-09-18): BD 段改为 source yolo_sys_bd.tcl
#   （write_bd_tcl 从 GUI 权威 BD 导出的正典，见其尾部说明）。
#   手工拼装时代九跑剥洋葱坑的最终答案：
#   ① ps7 配置必须一次性 set_property -dict 灌入（大括号保护
#      MIO_TREE）——事后单独 set PCW_IRQ_F2P_INTR 得 41-721
#      disabled ignored，IRQ_F2P 引脚永不物化 → 41-701。
#   ② BD 若在 GUI 改动：重新 write_bd_tcl 覆盖 yolo_sys_bd.tcl。
# 旧 ps7_ees331.tcl 保留作历史参考，不再被本脚本引用。
# ============================================================
set ROOT E:/competition/2_fpga/3_yolo_zynq
set RTL $ROOT/rtl
set IPD $ROOT/ip
set OUT $ROOT/proj/board_sys

# run9+：可选 argv 后缀建独立工程（不与 GUI 打开中的主工程抢锁）
set SUFFIX ""
if {$argc >= 1} { set SUFFIX "_[lindex $argv 0]" }

create_project -force yolo_a2_board$SUFFIX $OUT/yolo_a2_board$SUFFIX -part xc7z020clg484-1

# RTL closure (engine PROD default = 16x16) + both BMG IPs
add_files -norecurse [list \
    $RTL/yolo_engine_top.v $RTL/yolo_gemm_array.v $RTL/yolo_csr.v \
    $RTL/yolo_ctrl.v $RTL/yolo_dma.v $RTL/yolo_dma_wr.v \
    $RTL/yolo_wbuf.v $RTL/yolo_xbuf.v $RTL/yolo_xrowgen.v \
    $RTL/yolo_pe_pack.v $RTL/yolo_acc.v $RTL/yolo_requant.v \
    $RTL/yolo_silu_lut.v \
    $IPD/yolo_wbuf_bmg/yolo_wbuf_bmg.xci \
    $IPD/yolo_xbuf_bmg/yolo_xbuf_bmg.xci]
add_files -fileset constrs_1 -norecurse $OUT/yolo_sys.xdc

# ---------------- block design ----------------
# 正典重建脚本（自带 validate_bd_design + save_bd_design）。
# 要求 RTL 已 add（module_ref yolo_engine_top 按 -reference 解析）。
source $OUT/yolo_sys_bd.tcl

# ---------------- top + bitstream ----------------
make_wrapper -files [get_files yolo_sys.bd] -top -import
set_property top yolo_sys_wrapper [current_fileset]

# （七跑实拦 [Vivado 12-1015]：-to_step write_bitstream 对 synth_1
#  非法（其唯一合法步是 synth_design）→ 两段式）
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# archive: XSA (contains .hwh for overlay tooling; runtime itself uses
# fixed 0x43C1_0000 via /dev/mem, no .hwh dependency)
write_hw_platform -fixed -include_bit -force $OUT/yolo_a2.xsa

open_run impl_1
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts "BOARD_TIMING wns_ns=$wns"
if {$wns >= 0} {
    puts "BOARD_BITSTREAM_PASS wns_ns=$wns xsa=$OUT/yolo_a2.xsa"
} else {
    puts "BOARD_BITSTREAM_FAIL wns_ns=$wns"
}
