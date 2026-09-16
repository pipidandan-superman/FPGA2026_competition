# ooc_dbg4.tcl -- run02 routed DCP 的 DSP 分类（142 vs 预测 138 差异定位）
open_checkpoint E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_run02_routed.dcp
set cells [get_cells -hier -filter {REF_NAME =~ DSP48E1}]
set counts [dict create]
foreach c $cells {
    set n [get_property NAME $c]
    # 归类: u_array/u_pe[*] -> PE; u_array/u_addrgen -> addrgen; u_array/u_requant -> requant
    if {[regexp {u_array/g_pe\[} $n]}       { set k "PE(g_pe)" } \
    elseif {[regexp {/u_addrgen/} $n]}      { set k "addrgen" } \
    elseif {[regexp {/u_requant/} $n]}      { set k "requant" } \
    elseif {[regexp {row_addr} $n]}         { set k "row_addr_d0_w" } \
    else                                    { set k "OTHER:$n" }
    dict incr counts $k
}
dict for {k v} $counts { puts "DSP_CLS $k = $v" }
# 非阵列 DSP 的具体名字
foreach c $cells {
    set n [get_property NAME $c]
    if {![regexp {u_array/g_pe\[} $n]} { puts "DSP_NAME $n" }
}
close_design
puts "OOC_DBG4_DONE"
