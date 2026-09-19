# =====================================================================
# sim_bank_bmg.tcl - run11: bank 单元控制仿真（②pp ram 先行，IP 化重做
# 第一门）。DUT = yolo_gemm_bank V2.0（4×BMG IP）。BMG 行为模型来自
# xsim 预编译库 blk_mem_gen_v8_4_12（wrapper 引用 blk_mem_gen_v8_4_12
# 模块）；RAM 原语经 unisims_ver + glbl 解析。
# Run by: cmd //c vivado.bat -mode batch -source sim_bank_bmg.tcl
# =====================================================================

set xil    {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set ipdir  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
set gdir   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM}
set bank   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_bank.sv}
set tb     {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_bank_bmg.sv}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
# IP sim wrapper（.veo 注：须编 wrapper 并引仿真库）
run_tool [file join $xsimbin xvlog.exe] \
    [file join $ipdir gemm_bm_w_g0 sim gemm_bm_w_g0.v] \
    [file join $ipdir gemm_bm_w_g1 sim gemm_bm_w_g1.v] \
    [file join $ipdir gemm_bm_x_g0 sim gemm_bm_x_g0.v] \
    [file join $ipdir gemm_bm_x_g1 sim gemm_bm_x_g1.v] \
    [file join $ipdir gemm_bm_lut   sim gemm_bm_lut.v]
run_tool [file join $xsimbin xvlog.exe] -sv $bank $tb
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_bank_bmg tb_yolo_gemm_bank_bmg glbl

puts "EES_VIVADO_STAGE SIMULATE"
run_tool [file join $xsimbin xsim.exe] tb_bank_bmg -runall
