# gen_xbuf_bmg.tcl -- 生成 xbuf 用 BMG IP（M12 B0 源语/IP 修复批）
# 器件: xc7z020clg484-1 (EES-331)。非工程批处理模式。
# 配置（对齐 yolo_xbuf V1.0 契约）:
#   Simple Dual Port RAM: 端口A=只写(128b x 2304), 端口B=只读(128b)
#   字节写使能: 16 x 8bit (WEA[15:0] one-hot 列选, DINA=wdata 广播)
#   Write_Mode = Read_First (写端口A): 同地址同拍写读时端口B读旧值
#               == V1.0 RTL 参考的非阻塞语义
#   端口B不加输出寄存 -> 读延迟 1 拍 (与 V1.0 同)
#   无初始化文件; 端口A Always_Enabled (写由 WEA 门控); 端口B用 ENB
# 同时 synth_ip 产出 OOC DCP 供 ooc_run02 链接。
set part xc7z020clg484-1
set ipdir  [file normalize [file dirname [info script]]]
set_part $part

create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 \
    -module_name yolo_xbuf_bmg -dir $ipdir

set_property -dict [list \
    CONFIG.Memory_Type {Simple_Dual_Port_RAM} \
    CONFIG.Write_Width_A {128} \
    CONFIG.Write_Depth_A {2304} \
    CONFIG.Read_Width_B {128} \
    CONFIG.Use_Byte_Write_Enable {true} \
    CONFIG.Byte_Size {8} \
    CONFIG.Operating_Mode_A {READ_FIRST} \
    CONFIG.Enable_A {Always_Enabled} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Core {false} \
    CONFIG.Load_Init_File {false} \
    CONFIG.Fill_Remaining_Memory_Locations {false} \
] [get_ips yolo_xbuf_bmg]

generate_target all [get_ips yolo_xbuf_bmg]
synth_ip [get_ips yolo_xbuf_bmg]

# 资源确认
set dcp [file join $ipdir yolo_xbuf_bmg yolo_xbuf_bmg.dcp]
open_checkpoint $dcp
report_utilization -file [file join $ipdir yolo_xbuf_bmg_util.rpt]
close_design

puts "GEN_IP_XBUF_DONE"
