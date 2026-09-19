# B0 debug pass 2: open ooc_dbg1_synth.dcp, attribute every DSP48E1
set OUT E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate
open_checkpoint $OUT/ooc_dbg1_synth.dcp

set dsps [get_cells -hier -filter {REF_NAME == DSP48E1}]
puts "TOTAL_DSP48E1 [llength $dsps]"

# classify by parent instance path
set n_pe 0
set n_other 0
foreach c $dsps {
    set nm [get_property NAME $c]
    if {[string match "*u_pe*" $nm]} {
        incr n_pe
    } else {
        incr n_other
        puts "NONPE_DSP $nm"
    }
}
puts "PE_DSP_COUNT $n_pe"
puts "NONPE_DSP_COUNT $n_other"

# dump the two DSPs inside one sample PE (g_pe_row[0].g_pe_pair[0]) with
# the source nets on A/B/C/P so we can see what each one multiplies
set sample [get_cells -hier -filter {REF_NAME == DSP48E1 && NAME =~ "*g_pe_row\[0\].g_pe_pair\[0\]*"}]
puts "SAMPLE_PE_DSP_COUNT [llength $sample]"
foreach c $sample {
    puts "SAMPLE_DSP [get_property NAME $c]"
    foreach pin {A B C P PCIN PCOUT} {
        set p [get_pins -of_objects $c -filter "REF_PIN_NAME == $pin"]
        if {[llength $p] == 0} { continue }
        set net [get_nets -of_objects $p -quiet]
        puts "  PIN_$pin -> [get_property NAME $p] NET {[llength $net]?}"
        if {[llength $net]} { puts "    NETNAME [get_property NAME $net]" }
    }
}

# also dump every distinct DSP under the 16 pair[7] PEs (they had 1 cell)
set p7 [get_cells -hier -filter {REF_NAME == DSP48E1 && NAME =~ "*g_pe_pair\[7\]*"}]
puts "PAIR7_DSP_COUNT [llength $p7]"

close_design
puts "OOC_DBG2_DONE"
