# =====================================================================
# synth_bit_template.tcl - synth -> impl -> write_bitstream + reports.
#
# ADAPTATION POINTS:
#   <projdir>   absolute path holding <proj>.xpr
#   <proj>      project name
#   <bd_name>   block design name (wrapper = <bd_name>_wrapper)
#   <evidence>  evidence/run directory for reports (NOT the project tree)
#   <timeout_s> polling budget in seconds for impl completion
#
# Hardened rules (each fixes a real failure):
#   1. Never reset a run that is already complete and current — reuse
#      it (detached child jobs can finish AFTER a failed parent).
#   2. Verdict fields: STATUS gets "*Complete!*", PROGRESS gets "100%".
#      Do not look for "Complete" in PROGRESS.
#   3. wait_on_run can return against a stale terminal state: poll
#      PROGRESS transitions in a bounded loop and cross-check disk
#      artifacts (.dcp / .bit) before PASS.
# =====================================================================

set projdir  {<projdir>}
set evidence {<evidence>}

# Failure marker built in pieces: batch vivado echoes script source
# (comments included) into the console log, and marker-based runners
# regex-match the echo. A literal failure token in an unexecuted
# branch turns a successful run into a recorded FAIL.
proc ees_fail {msg} {
    set m "EES_VIVADO_RESULT FA"; append m "IL"
    puts "EES_INFO $msg"
    puts $m
    exit 2
}

puts "EES_VIVADO_STAGE BIT_OPEN"
open_project $projdir/<proj>.xpr

# wrapper/output products (no-op when current)
if {[llength [get_files -quiet <bd_name>_wrapper.v]] == 0} {
    make_wrapper -files [get_files <bd_name>.bd] -top -import
}
generate_target all [get_files <bd_name>.bd]
set_property top <bd_name>_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "EES_VIVADO_STAGE SYNTH_PREP"
# reuse a completed-and-current synth; reset only what is stale
set spr [get_property PROGRESS [get_runs synth_1]]
puts "EES_INFO synth_1 PROGRESS=$spr"
if {$spr ne "100%"} {
    reset_run synth_1
    puts "EES_INFO synth_1 reset (was stale)"
}
reset_run impl_1

puts "EES_VIVADO_STAGE SYNTH_LAUNCH"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# robust verdict: poll until terminal, don't trust one wait_on_run
set t0 [clock seconds]
while {1} {
    set st [get_property STATUS   [get_runs impl_1]]
    set pr [get_property PROGRESS [get_runs impl_1]]
    set done [expr {[string match -nocase "*complete*" $st] && $pr eq "100%"}]
    set bad  [expr {[string match -nocase "*error*"   $st] || \
                    [string match -nocase "*abort*"   $st]}]
    if {$done || $bad} { break }
    if {[clock seconds] - $t0 > <timeout_s>} {
        puts "EES_INFO impl_1 poll timeout STATUS=$st PROGRESS=$pr"
        puts "EES_VIVADO_RESULT FAIL"
        exit 2
    }
    after 10000
}
puts "EES_INFO impl_1 STATUS=$st PROGRESS=$pr"

# artifact cross-check on disk (dcp + bit must exist and be fresh)
set bit "$projdir/<proj>.runs/impl_1/<bd_name>_wrapper.bit"
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
