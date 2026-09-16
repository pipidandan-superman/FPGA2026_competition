# B0 debug pass 3 (fixed): inferred DSP48E1 tie-offs as primitive template
set OUT E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate
open_checkpoint $OUT/ooc_dbg1_synth.dcp

set pats [list "*g_pe_row\\[1\\]*" "*g_pe_row\\[2\\]*"]
foreach pat $pats {
    set c [get_cells -hier -filter "REF_NAME == DSP48E1 && NAME =~ $pat"]
    foreach one $c {
        puts "=== [get_property NAME $one]"
        foreach p {OPMODE ALUMODE INMODE USE_MULT USE_SIMD USE_PATTERN_DETECT \
                   ACASCREG_BCASCREG AREG BREG CREG DREG ADREG MREG PREG \
                   SEL_MASK SEL_PATTERN} {
            set v [get_property $p $one -quiet]
            if {[llength $v]} { puts "  $p = $v" }
        }
    }
}
set rq [lindex [get_cells -hier -filter {REF_NAME == DSP48E1 && NAME =~ "*u_requant*"}] 0]
if {[llength $rq]} {
    puts "=== REQUANT [get_property NAME $rq]"
    foreach p {OPMODE ALUMODE INMODE USE_MULT USE_SIMD MREG PREG} {
        set v [get_property $p $rq -quiet]
        if {[llength $v]} { puts "  $p = $v" }
    }
}
close_design
puts "OOC_DBG3_DONE"
