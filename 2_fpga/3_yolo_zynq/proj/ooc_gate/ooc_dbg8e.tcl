# ooc_dbg8e.tcl -- v15 批分层时序剖析（只读；dbg8d 同式，DCP/打点名适配 V1.5）
open_checkpoint E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_v15_routed.dcp

foreach {tag filt} [list \
    rq_addr {NAME =~ *u_array/row_addr*} \
    addrgen {NAME =~ */u_addrgen/*} \
    PE      {NAME =~ *u_pe*} \
    acc     {NAME =~ *u_acc*} \
    requant {NAME =~ */u_requant/*} \
    xbuf    {NAME =~ */u_xbuf/*} \
    wbuf    {NAME =~ */u_wbuf/*} \
    dma_rd  {NAME =~ */u_dma/*} \
    dma_wr  {NAME =~ */u_dma_wr/*} \
    ctrl    {NAME =~ */u_ctrl/*} \
] {
    set p [lindex [get_timing_paths -max_paths 1 -to [get_cells -hier -filter $filt]] 0]
    if {$p ne ""} {
        puts [format "==== %s worst_slack=%s levels=%s" $tag \
            [get_property SLACK $p] [get_property LOGIC_LEVELS $p]]
        puts "        from [get_property STARTPOINT_PIN $p]"
        puts "        to   [get_property ENDPOINT_PIN $p]"
    } else {
        puts "==== $tag (no paths)"
    }
}

close_design
puts "OOC_DBG8E_DONE"
