# =====================================================================
# sim_gemm_b3_bridge.tcl - run26/B3: yolo_gemm_top V1.1（B3 DMA 桥）
# 块级门。TB=PS 角色（AXI-Lite）+ DMA MM2S BFM（s_axis_ld 三拍节律）
# + y 接收 BFM（m_axis_y 逐字节对拍 + 每 tile 128B tlast 检查）。
# 场景 S1-S7：槽路径回归 / 流单块 / 双组重叠零反压(STALLCNT) /
# 同组重载反压+读清 / 双源冲突(D4) / tlast 错位恢复 / y FIFO 溢出恢复。
# 全 IP 集：4x TDP bank BMG + LUT BMG + ycap BMG + DSP48E1 PEs
# -> blk_mem_gen + unisim libs + glbl。top 为 .v（纯 V2001）与其余
# .sv 混编——与 BD Add Module 同构路径，一并实证。
# Run by: cmd //c vivado.bat -mode batch -source sim_gemm_b3_bridge.tcl
# =====================================================================
set xil     {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set ipdir   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
set ref    {E:/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v}
set pecore {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv}
set acc    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv}
set mac    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_mac_cell.sv}
set tail   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv}
set arr    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_array.sv}
set bank   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_bank.sv}
set fed    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_feeder.sv}
set core   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_core.sv}
set top    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_top.v}
set tb     {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_b3_bridge.sv}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] $ref
run_tool [file join $xsimbin xvlog.exe] \
    [file join $ipdir gemm_bm_w_g0 sim gemm_bm_w_g0.v] \
    [file join $ipdir gemm_bm_w_g1 sim gemm_bm_w_g1.v] \
    [file join $ipdir gemm_bm_x_g0 sim gemm_bm_x_g0.v] \
    [file join $ipdir gemm_bm_x_g1 sim gemm_bm_x_g1.v] \
    [file join $ipdir gemm_bm_lut   sim gemm_bm_lut.v] \
    [file join $ipdir gemm_bm_ycap  sim gemm_bm_ycap.v]
run_tool [file join $xsimbin xvlog.exe] -sv \
    $pecore $acc $mac $tail $arr $bank $fed $core $tb
run_tool [file join $xsimbin xvlog.exe] $top
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_b3_bridge tb_yolo_gemm_b3_bridge glbl

puts "EES_VIVADO_STAGE SIMULATE"
run_tool [file join $xsimbin xsim.exe] tb_b3_bridge -runall

puts "EES_VIVADO_RESULT DONE"
