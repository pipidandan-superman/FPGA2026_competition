# ooc_dbg7.tcl -- V1.3 批 (ooc_v13_routed.dcp) 分层时序剖析（只读）
# 问题: V4 三级流水后 WNS 仍 -31.017 (run02 -31.140)。
# 输出: 各模块组最差 slack + 失败端点数 + addrgen 最差路径明细
open_checkpoint E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_v13_routed.dcp

foreach {tag filt} [list \
    addrgen {NAME =~ */u_addrgen/*} \
    PE      {NAME =~ */u_pe/*} \
    acc     {NAME =~ */u_acc/*} \
    requant {NAME =~ */u_requant/*} \
    xbuf    {NAME =~ */u_xbuf/*} \
    wbuf    {NAME =~ */u_wbuf/*} \
    dma     {NAME =~ */u_dma*/*} \
    ctrl    {NAME =~ */u_ctrl/*} \
] {
    set eps [get_pins -of_objects [get_cells -hier -filter $filt] \
             -filter {DIRECTION == IN && IS_ENABLE != 1} -quiet]
    set n 0
    set p [lindex [get_timing_paths -max_paths 1 -to $eps] 0]
    if {$p ne ""} {
        set s [get_property SLACK $p]
        puts [format "==== %s worst_slack=%s from=%s to=%s levels=%s" $tag $s \
            [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p] \
            [get_property LOGIC_LEVELS $p]]
    } else {
        puts "==== $tag (no paths)"
    }
}

# addrgen 最差路径逐级明细（找 95 级组合链的算术来源）
set p [lindex [get_timing_paths -max_paths 1 \
        -to [get_pins -of_objects [get_cells -hier -filter {NAME =~ */u_addrgen/*}] -filter {DIRECTION == IN}]] 0]
puts "==== addrgen path detail ===="
foreach c [get_property SLOWEST_CELLS $p] { puts "  cell: $c" }
report_timing -from [get_property STARTPOINT_PIN $p] \
              -to [get_property ENDPOINT_PIN $p] -max_paths 1 \
              -file E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_dbg7_addrgen.rpt

close_design
puts "OOC_DBG7_DONE"
