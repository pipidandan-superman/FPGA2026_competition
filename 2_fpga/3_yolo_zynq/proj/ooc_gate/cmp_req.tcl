foreach dcp {ooc_v17_routed.dcp ooc_v19_routed.dcp} {
    open_checkpoint $dcp
    puts "==== $dcp ===="
    set p [get_timing_paths -from [get_cells u_array/u_requant/sum_r_reg*] \
              -to   [get_cells u_array/u_requant/prod_r_reg*] -max_paths 1]
    if {[llength $p]} {
        puts "sum->prod slack=[get_property SLACK $p] levels=[get_property LOGIC_LEVELS $p] dpd=[get_property DATAPATH_DELAY $p]"
    } else { puts "sum->prod: no path" }
    set q [get_timing_paths -from [get_cells u_array/u_requant/sum_r_reg*] \
              -to   [get_cells u_array/u_requant/q_lsb_r_reg*] -max_paths 1]
    if {[llength $q]} {
        puts "sum->q_lsb slack=[get_property SLACK $q] levels=[get_property LOGIC_LEVELS $q] dpd=[get_property DATAPATH_DELAY $q]"
    } else { puts "sum->q_lsb: no path" }
    close_design
}
puts CMP_REQ_DONE
