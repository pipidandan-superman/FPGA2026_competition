# =====================================================================
# gen_gemm_ip.tcl - run11: GEMM 存储层 BMG IP 生成（用户硬指标裁定
# 2026-09-19：存储一律真 Vivado IP，LUTRAM 亦然，不内部参数化表达）。
# 生成 5 个 blk_mem_gen 到 rtl/GEMM/ip/（落点已裁定）：
#   gemm_bm_w_g0/g1 : TDP 64b x 1024, A 写(字节WE=8)/B 读, 读延迟 1
#   gemm_bm_x_g0/g1 : TDP 128b x 1024, A 写(字节WE=16)/B 读, 读延迟 1
#   gemm_bm_lut     : SDP 8b x 256, A 写/B 读, 读延迟 1
# 读延迟=1（关 Primitive 输出寄存器）= 现 bank RTL dout 一级寄存逐拍匹配。
# Run: cmd //c vivado.bat -mode batch -source gen_gemm_ip.tcl -notrace -nojournal
# =====================================================================

set ipdir {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
file mkdir $ipdir

# create_ip 需要工程上下文（2025.2 批处理）：in-memory 工程，不落盘
if {[catch {create_project -in_memory -part xc7z020clg484-1} emsg]} {
    bail "create_project: $emsg"
}

proc bail {msg} { puts "EES_IP_FAIL $msg"; exit 1 }

# ---- 版本：2025.2 随发行版 blk_mem_gen 8.4（固定，不再探测）----
set bmgver 8.4

proc mk_bmg {name memtype keys} {
    global ipdir bmgver
    puts "EES_IP_STAGE CREATE $name ($memtype)"
    if {[catch {
        create_ip -vlnv xilinx.com:ip:blk_mem_gen:$bmgver \
                  -module_name $name -dir $ipdir
    } emsg]} { bail "create_ip $name: $emsg" }
    set ip [get_ips $name]
    if {[catch {
        set_property -dict $keys $ip
    } emsg]} { bail "config $name: $emsg" }
    if {[catch {
        generate_target all $ip
        catch { export_ip_user_files $ip -no_script -sync -force -quiet }
    } emsg]} { bail "generate $name: $emsg" }
    # 回显关键配置作证据
    foreach k {Memory_Type Write_Width_A Write_Depth_A Write_Width_B \
               Read_Width_B Use_Byte_Write_Enable Byte_Size \
               Register_PortA_Output_of_Memory_Primitives \
               Register_PortB_Output_of_Memory_Primitives} {
        set v [get_property CONFIG.$k $ip]
        if {$v ne ""} { puts "EES_IP_CFG $name $k=$v" }
    }
    puts "EES_IP_STAGE DONE $name"
}

# ---- W 双组：TDP 64 x 1024，双口 64b，字节 WE ----
set wkeys [list \
    CONFIG.Memory_Type                  {True_Dual_Port_RAM} \
    CONFIG.Write_Width_A                {64} \
    CONFIG.Write_Depth_A                {1024} \
    CONFIG.Write_Width_B                {64} \
    CONFIG.Use_Byte_Write_Enable        {true} \
    CONFIG.Byte_Size                    {8} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File               {false} \
]
# ---- X 双组：TDP 128 x 1024（lo/hi 合并在阵列外，对称双口即可）----
set xkeys [list \
    CONFIG.Memory_Type                  {True_Dual_Port_RAM} \
    CONFIG.Write_Width_A                {128} \
    CONFIG.Write_Depth_A                {1024} \
    CONFIG.Write_Width_B                {128} \
    CONFIG.Use_Byte_Write_Enable        {true} \
    CONFIG.Byte_Size                    {8} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File               {false} \
]
# ---- SiLU LUT：SDP 8 x 256（A 写 / B 读）----
set lkeys [list \
    CONFIG.Memory_Type                  {Simple_Dual_Port_RAM} \
    CONFIG.Write_Width_A                {8} \
    CONFIG.Write_Depth_A                {256} \
    CONFIG.Read_Width_B                 {8} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File               {false} \
]

mk_bmg gemm_bm_w_g0 True_Dual_Port_RAM $wkeys
mk_bmg gemm_bm_w_g1 True_Dual_Port_RAM $wkeys
mk_bmg gemm_bm_x_g0 True_Dual_Port_RAM $xkeys
mk_bmg gemm_bm_x_g1 True_Dual_Port_RAM $xkeys
mk_bmg gemm_bm_lut   Simple_Dual_Port_RAM $lkeys

# ---- 生成物清单（证据）----
puts "EES_IP_STAGE LISTING"
foreach f [glob -nocomplain -directory $ipdir -type f *] {
    puts "EES_IP_FILE $f"
}

puts "EES_IP_RESULT DONE"
