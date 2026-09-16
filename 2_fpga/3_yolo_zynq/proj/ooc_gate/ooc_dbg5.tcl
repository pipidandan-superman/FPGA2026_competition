# ooc_dbg5.tcl -- run02 routed DCP 各子系统 WNS 分布（时序诊断，只读）
open_checkpoint E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_run02_routed.dcp
foreach {tag filt} [list \
    PE_acc     {NAME =~ */u_acc/*} \
    addrgen    {NAME =~ */u_addrgen/*} \
    ctrl       {NAME =~ */u_ctrl/*} \
    dma        {NAME =~ */u_dma/*} \
    dma_wr     {NAME =~ */u_dma_wr/*} \
    wbuf       {NAME =~ */u_wbuf/*} \
    xbuf       {NAME =~ */u_xbuf/*} \
    requant    {NAME =~ */u_requant/*} \
] {
    set paths [get_timing_paths -max_paths 1 -to [get_cells -hier -filter $filt] -quiet]
    if {[llength $paths] > 0} {
        set s [get_property SLACK [lindex $paths 0]]
        puts "SUBSYS_WNS $tag $s"
    } else {
        puts "SUBSYS_WNS $tag (no endpoint)"
    }
}
close_design
puts "OOC_DBG5_DONE"
