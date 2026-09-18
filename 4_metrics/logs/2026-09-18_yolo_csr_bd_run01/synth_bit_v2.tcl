# synth_bit_v2.tcl - recovery run: reuse completed synth_1 (18:46 dcp),
# rerun impl + bit only. Fixes vs v1: verdict reads STATUS+PROGRESS
# correctly, bounded polling loop, disk artifact cross-check.

set projdir  {E:/competition/2_fpga/3_yolo_zynq/proj/axi_test}
set evidence {E:/competition/4_metrics/logs/2026-09-18_yolo_csr_bd_run01}

puts "EES_VIVADO_STAGE BIT_OPEN"
open_project $projdir/axi_test.xpr

set_property top display_test_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "EES_VIVADO_STAGE SYNTH_PREP"
set spr [get_property PROGRESS [get_runs synth_1]]
set sst [get_property STATUS   [get_runs synth_1]]
puts "EES_INFO synth_1 STATUS=$sst PROGRESS=$spr"
if {$spr ne "100%"} {
    reset_run synth_1
    puts "EES_INFO synth_1 reset (was stale)"
}
reset_run impl_1

puts "EES_VIVADO_STAGE SYNTH_LAUNCH"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set t0 [clock seconds]
while {1} {
    set st [get_property STATUS   [get_runs impl_1]]
    set pr [get_property PROGRESS [get_runs impl_1]]
    set done [expr {[string match -nocase "*complete*" $st] && $pr eq "100%"}]
    set bad  [expr {[string match -nocase "*error*" $st] || \
                    [string match -nocase "*abort*" $st]}]
    if {$done || $bad} { break }
    if {[clock seconds] - $t0 > 1500} {
        puts "EES_INFO impl_1 poll timeout STATUS=$st PROGRESS=$pr"
        puts "EES_VIVADO_RESULT FAIL"
        exit 2
    }
    after 10000
}
puts "EES_INFO impl_1 STATUS=$st PROGRESS=$pr"

set bit "$projdir/axi_test.runs/impl_1/display_test_wrapper.bit"
if {![file exists $bit] || [file size $bit] == 0} {
    puts "EES_INFO bitstream missing/empty: $bit"
    puts "EES_VIVADO_RESULT FAIL"
    exit 2
}
puts "EES_INFO bit [file size $bit] bytes  mtime [clock format [file mtime $bit]]"

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
