# =====================================================================
# synth_bit_ackfix.tcl - rebuild after RTL change (ACK race fix).
# Derived from synth_bit_v2.tcl / 6_skill/vivado-bd-bitstream template,
# with one deliberate difference: synth_1 is ALWAYS reset (source
# changed; reusing a completed-but-stale synth would rebuild impl from
# pre-fix RTL). All other hardening kept: verdict fields, bounded poll,
# disk artifact cross-check, ees_fail literal-split marker.
# =====================================================================
set projdir  {E:/competition/2_fpga/3_yolo_zynq/proj/axi_test}
set evidence {E:/competition/4_metrics/logs/2026-09-18_yolo_csr_bd_run02_ackfix}

proc ees_fail {msg} {
    set m "EES_VIVADO_RESULT FA"; append m "IL"
    puts "EES_INFO $msg"
    puts $m
    exit 2
}

puts "EES_VIVADO_STAGE BIT_OPEN"
open_project $projdir/axi_test.xpr

generate_target all [get_files display_test.bd]
set_property top display_test_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "EES_VIVADO_STAGE RESET_RUNS"
# source changed -> force both resets (no stale reuse)
reset_run synth_1
reset_run impl_1

puts "EES_VIVADO_STAGE LAUNCH"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set t0 [clock seconds]
while {1} {
    set st [get_property STATUS   [get_runs impl_1]]
    set pr [get_property PROGRESS [get_runs impl_1]]
    set done [expr {[string match -nocase "*complete*" $st] && $pr eq "100%"}]
    set bad  [expr {[string match -nocase "*error*" $st] || \
                    [string match -nocase "*abort*"   $st]}]
    if {$done || $bad} { break }
    if {[clock seconds] - $t0 > 2400} { ees_fail "impl_1 poll timeout STATUS=$st PROGRESS=$pr" }
    after 10000
}
puts "EES_INFO impl_1 STATUS=$st PROGRESS=$pr"
if {!$done} { ees_fail "impl_1 not complete: $st" }

set bit "$projdir/axi_test.runs/impl_1/display_test_wrapper.bit"
if {![file exists $bit] || [file size $bit] == 0} { ees_fail "bit missing: $bit" }
puts "EES_INFO bit [file size $bit] bytes  mtime [clock format [file mtime $bit]]"

# fresh hwh from hw_handoff, copied to evidence dir
set hwhsrc "$projdir/axi_test.gen/sources_1/bd/display_test/hw_handoff/display_test.hwh"
if {![file exists $hwhsrc]} { ees_fail "hwh missing: $hwhsrc" }
file copy -force $hwhsrc "$evidence/display_test_wrapper.hwh"
file copy -force $bit "$evidence/display_test_wrapper.bit"
puts "EES_INFO artifacts copied to $evidence"

puts "EES_VIVADO_STAGE REPORTS"
open_run impl_1
report_utilization    -file $evidence/utilization.rpt
report_timing_summary -file $evidence/timing_summary.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
puts "EES_INFO WNS=$wns  WHS=$whs"

close_project
puts "EES_VIVADO_STAGE BIT_DONE"
puts "EES_VIVADO_RESULT PASS"
