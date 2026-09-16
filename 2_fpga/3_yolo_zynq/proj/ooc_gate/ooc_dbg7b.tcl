# ooc_dbg7b.tcl -- V1.3 批分层时序剖析（只读，修正版：cell 端点）
open_checkpoint E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_v13_routed.dcp

foreach {tag filt} [list \
    addrgen {NAME =~ */u_addrgen} \
    PE      {NAME =~ *u_pe} \
    acc     {NAME =~ */u_acc} \
    requant {NAME =~ */u_requant} \
    xbuf    {NAME =~ */u_xbuf} \
    wbuf    {NAME =~ */u_wbuf} \
    dma_rd  {NAME =~ */u_dma} \
    dma_wr  {NAME =~ */u_dma_wr} \
    ctrl    {NAME =~ */u_ctrl} \
] {
    set p [lindex [get_timing_paths -max_paths 1 -to [get_cells -hier -filter $filt]] 0]
    if {$p ne ""} {
        puts [format "==== %s worst_slack=%s levels=%s from=%s to=%s" $tag \
            [get_property SLACK $p] [get_property LOGIC_LEVELS $p] \
            [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
    } else {
        puts "==== $tag (no paths)"
    }
}

# addrgen 95 级链逐级明细
report_timing -to [get_cells -hier -filter {NAME =~ */u_addrgen/ox_r_reg*}] \
              -max_paths 1 \
              -file E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_dbg7b_addrgen.rpt

close_design
puts "OOC_DBG7B_DONE"
