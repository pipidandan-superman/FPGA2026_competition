# =====================================================================
# gen_ycap_ip.tcl - run21/B1: GEMM 顶层 Y 捕获 RAM BMG IP 生成。
# 用户硬指标（2026-09-19 裁定，run11 先例）：存储一律真 Vivado IP，
# 不内部参数化表达。Y 捕获 = 结果回读通道，同为存储 → 同样用 IP。
#   gemm_bm_ycap : SDP 8b x 128, A 写/B 读, 读延迟 1
#     （地址 = y_row*16 + y_col，0..127，单 tile 坐标索引唯一）
# 配置逐项照抄 run11 gemm_bm_lut 的 lkeys（SDP 8b、关 Primitive 输出
# 寄存器 → 读延迟 1），仅深度 256→128。
# Run: cmd //c vivado.bat -mode batch -source gen_ycap_ip.tcl -notrace -nojournal
# =====================================================================

set ipdir {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
file mkdir $ipdir

proc bail {msg} { puts "EES_IP_FAIL $msg"; exit 1 }

if {[catch {create_project -in_memory -part xc7z020clg484-1} emsg]} {
    bail "create_project: $emsg"
}

# ---- 版本：2025.2 随发行版 blk_mem_gen 8.4（固定，与 run11 五件一致）----
set bmgver 8.4

set name gemm_bm_ycap
puts "EES_IP_STAGE CREATE $name (SDP 8 x 128)"
if {[catch {
    create_ip -vlnv xilinx.com:ip:blk_mem_gen:$bmgver \
              -module_name $name -dir $ipdir
} emsg]} { bail "create_ip $name: $emsg" }
set ip [get_ips $name]
set keys [list \
    CONFIG.Memory_Type                  {Simple_Dual_Port_RAM} \
    CONFIG.Write_Width_A                {8} \
    CONFIG.Write_Depth_A                {128} \
    CONFIG.Read_Width_B                 {8} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File               {false} \
]
if {[catch { set_property -dict $keys $ip } emsg]} { bail "config $name: $emsg" }
if {[catch {
    generate_target all $ip
    catch { export_ip_user_files $ip -no_script -sync -force -quiet }
} emsg]} { bail "generate $name: $emsg" }

foreach k {Memory_Type Write_Width_A Write_Depth_A Read_Width_B \
           Register_PortA_Output_of_Memory_Primitives \
           Register_PortB_Output_of_Memory_Primitives} {
    set v [get_property CONFIG.$k $ip]
    if {$v ne ""} { puts "EES_IP_CFG $name $k=$v" }
}
puts "EES_IP_STAGE DONE $name"
puts "EES_IP_RESULT DONE"
