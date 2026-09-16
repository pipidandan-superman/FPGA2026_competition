foreach dcp {ooc_v17_routed.dcp ooc_v19_routed.dcp} {
    open_checkpoint $dcp
    puts "==== $dcp ===="
    set p [get_timing_paths -from [get_cells u_array/u_ctrl/FSM_onehot_state_r_reg*] \
              -to   [get_cells -hier -regexp {.*g_acc\[.\]\.acc_clr_d1_g_r.*}] -max_paths 1]
    puts "FSM->acc_clr_d1 slack=[get_property SLACK $p] levels=[get_property LOGIC_LEVELS $p] dpd=[get_property DATAPATH_DELAY $p]"
    close_design
}
puts CMP_CTL_DONE
