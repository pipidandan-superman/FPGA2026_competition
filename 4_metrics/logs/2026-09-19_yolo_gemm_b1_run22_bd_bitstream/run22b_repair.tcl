# =====================================================================
# run22b_repair.tcl - B1 修复：GUI 并发会话把 .xpr 回写成旧态（GEMM 源
# 引用全丢、BD 打不开、impl_1 被清）。.bd/synth dcp/xsa 均完好。
# 修复：重加源引用 → 重开 BD（module_ref 解析）→ validate →
# impl→bit（synth 视新旧自动复用或重跑）→ close_project 确定性落盘。
# 前提：用户 GUI 已关闭（2026-09-19 16:2x 确认 vivado.exe 退出）。
# Run: cmd //c vivado.bat -mode batch -source run22b_repair.tcl
# =====================================================================
set proj  {E:/competition/2_fpga/3_yolo_zynq/proj/axi_gemm_test/axi_gemm_test.xpr}
set bdf   {E:/competition/2_fpga/3_yolo_zynq/proj/axi_gemm_test/axi_gemm_test.srcs/sources_1/bd/display_test/display_test.bd}
set rtl   {E:/competition/2_fpga/3_yolo_zynq/rtl}
set run22 {E:/competition/4_metrics/logs/2026-09-19_yolo_gemm_b1_run22_bd_bitstream}

proc bail {msg} { puts "EES_FIX_FAIL $msg"; exit 1 }

puts "EES_FIX_STAGE A_RESTORE_SOURCES"
if {[catch {open_project $proj} emsg]} { bail "open_project: $emsg" }

set srcs [list \
    $rtl/yolo_pe_pack.v \
    $rtl/GEMM/yolo_pe_core.sv \
    $rtl/GEMM/yolo_acc_dual.sv \
    $rtl/GEMM/yolo_mac_cell.sv \
    $rtl/GEMM/yolo_gemm_tail.sv \
    $rtl/GEMM/yolo_gemm_array.sv \
    $rtl/GEMM/yolo_gemm_bank.sv \
    $rtl/GEMM/yolo_gemm_feeder.sv \
    $rtl/GEMM/yolo_gemm_core.sv \
    $rtl/GEMM/yolo_gemm_top.v]
set ips [list \
    $rtl/GEMM/ip/gemm_bm_w_g0/gemm_bm_w_g0.xci \
    $rtl/GEMM/ip/gemm_bm_w_g1/gemm_bm_w_g1.xci \
    $rtl/GEMM/ip/gemm_bm_x_g0/gemm_bm_x_g0.xci \
    $rtl/GEMM/ip/gemm_bm_x_g1/gemm_bm_x_g1.xci \
    $rtl/GEMM/ip/gemm_bm_lut/gemm_bm_lut.xci \
    $rtl/GEMM/ip/gemm_bm_ycap/gemm_bm_ycap.xci]
if {[catch {add_files -fileset sources_1 [concat $srcs $ips]} emsg]} {
    bail "add_files: $emsg"
}
if {[catch {update_compile_order -fileset sources_1} emsg]} { bail "ucc: $emsg" }
foreach f [concat $srcs $ips] {
    set fo [get_files -quiet -of [get_filesets sources_1] [file tail $f]]
    if {[llength $fo] == 0} { bail "source not in fileset: $f" }
    puts "EES_FIX_SRC [file tail $f] -> $fo"
}

puts "EES_FIX_STAGE B_BD_REOPEN"
if {[catch {open_bd_design $bdf} emsg]} { bail "open_bd_design: $emsg" }
if {[llength [get_bd_cells -quiet u_yolo_gemm]] == 0} { bail "u_yolo_gemm cell missing in BD" }
if {[llength [get_bd_intf_pins -quiet u_yolo_gemm/s_axi]] == 0} { bail "s_axi interface not resolved" }
puts "EES_FIX_CELL u_yolo_gemm resolved, iface s_axi present"
if {[catch {validate_bd_design} emsg]} { bail "validate: $emsg" }
if {[catch {save_bd_design} emsg]} { bail "save_bd_design: $emsg" }
set bfd [open $bdf r]; set bdtxt [read $bfd]; close $bfd
if {![regexp {0x43C00000} $bdtxt]} { bail "0x43C00000 lost from .bd" }
if {![regexp {0x43C10000} $bdtxt]} { bail "0x43C10000 lost from .bd" }
puts "EES_FIX_ADDR both addresses verified in saved .bd"

puts "EES_FIX_STAGE C_IMPL_BIT"
catch {set_property incremental_checkpoint {} [get_runs synth_1]}
# GUI 失败尝试后 impl_1 处于半复位态（opt_design 需先 reset）；synth 被标
# 脏（NEEDS_REFRESH=1）→ 全链显式复位后重跑
set snr [get_property NEEDS_REFRESH [get_runs synth_1]]
puts "EES_FIX_SYNTH_NEEDS_REFRESH $snr"
if {[catch {reset_run impl_1} emsg]} { bail "reset impl: $emsg" }
if {$snr} {
    if {[catch {reset_run synth_1} emsg]} { bail "reset synth: $emsg" }
}
if {[catch {launch_runs impl_1 -to_step write_bitstream -jobs 4} emsg]} {
    bail "launch_runs: $emsg"
}
if {[catch {wait_on_run impl_1} emsg]} { bail "wait_on_run: $emsg" }
set st [get_property STATUS [get_runs impl_1]]
puts "EES_FIX_IMPL_STATUS $st"
if {![string match "*Complete*" $st]} { bail "impl not complete: $st" }
set bit [file join [get_property DIRECTORY [get_runs impl_1]] display_test_wrapper.bit]
if {![file exists $bit]} { bail "bitstream missing: $bit" }
puts "EES_FIX_BIT $bit [file size $bit] bytes"

puts "EES_FIX_STAGE D_REPORTS"
if {[catch {open_run impl_1} emsg]} { bail "open_run: $emsg" }
report_timing_summary -file $run22/impl_timing_summary.rpt
report_utilization   -file $run22/impl_utilization.rpt
report_drc           -file $run22/impl_drc.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
puts "EES_FIX_WNS $wns"
puts "EES_FIX_WHS $whs"
if {[catch {write_hw_platform -fixed -include_bit -force \
        $run22/axi_gemm_test_wrapper.xsa} emsg]} { puts "EES_FIX_WARN xsa: $emsg" }
# 确定性落盘：显式关工程再退出，杜绝依赖 exit 隐式保存
close_project
puts "EES_FIX_RESULT DONE"
