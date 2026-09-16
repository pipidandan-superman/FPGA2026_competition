# gen_xbuf_bmg_v22.tcl -- xbuf BMG 输出寄存合同变更（V2.2, 2026-09-17
# 用户授权）：Register_PortB_Output_of_Memory_Primitives false -> true，
# 读延迟 1 -> 2 拍。其余配置不动（128b x 2304 SDP、字节写使能 16x8、
# READ_FIRST、A 常使能、B=ENB）。非工程批处理，就地改 xci 并重生成
# (generate_target + synth_ip 产出新 OOC DCP 供 ooc_v18 链接)。
# 外部合同影响: yolo_xbuf V2.2 (dout_vld 2 级), gemm_array W 操作数
# 对齐 +1 (PE 墙前寄存), acc_en 3->4 拍, ctrl S_DRAIN 3->4 (V1.8);
# M4/M8 黄金再生成（仅延迟平移，数值字节不变——授权原文）。
set part  xc7z020clg484-1
set ipdir [file normalize [file dirname [info script]]]
set ipsub [file join $ipdir yolo_xbuf_bmg]
set ipxci [file join $ipsub yolo_xbuf_bmg.xci]

create_project -in_memory -part $part
read_ip $ipxci
set_property -dict [list \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {true} \
] [get_ips yolo_xbuf_bmg]
generate_target all [get_ips yolo_xbuf_bmg]
synth_ip [get_ips yolo_xbuf_bmg]
close_project

# 资源/延迟确认: 重开 DCP 报 util
open_checkpoint [file join $ipsub yolo_xbuf_bmg.dcp]
report_utilization -file [file join $ipsub yolo_xbuf_bmg_util_v22.rpt]
close_design

puts "GEN_IP_XBUF_V22_DONE"
