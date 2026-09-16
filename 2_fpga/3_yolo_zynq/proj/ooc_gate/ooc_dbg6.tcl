# ooc_dbg6.tcl -- PE_acc / requant / xbuf 最差路径明细（时序诊断，只读）
open_checkpoint E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_run02_routed.dcp
foreach {tag filt} [list \
    PE_acc  {NAME =~ */u_acc/*} \
    requant {NAME =~ */u_requant/*} \
    xbuf    {NAME =~ */u_xbuf/*} \
] {
    set p [lindex [get_timing_paths -max_paths 1 -to [get_cells -hier -filter $filt]] 0]
    puts "==== $tag ===="
    puts "  slack : [get_property SLACK $p]"
    puts "  from  : [get_property STARTPOINT_PIN $p]"
    puts "  to    : [get_property ENDPOINT_PIN $p]"
    puts "  levels: [get_property LOGIC_LEVELS $p]"
}
close_design
puts "OOC_DBG6_DONE"
