# =====================================================================
# sim_gemm_array_v22.tcl - run18: array gate, WNS A+B redo (run16
# decision A+B). DUT = yolo_gemm_array V2.2 (coordinate mirror deepened
# 4->5 to match the tail V2.1, D+5) + yolo_gemm_tail V2.1 (RNE
# magic-add narrowing, same gemm_bm_lut IP). Three elaboration tiers
# 4x4/8x16/16x16 from ONE TB, identical stimulus/golden to
# run06/run08/run14 -> per-number realignment expected (846/4250/6881).
# MAC grid carries real DSP48E1 PEs and the tail carries a real BMG ->
# unisim libs + blk_mem_gen precompiled lib + glbl required.
# Run by: cmd //c vivado.bat -mode batch -source sim_gemm_array_v22.tcl
# =====================================================================
set xil     {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set ipdir   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
set ref  {E:/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v}
set core {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv}
set acc  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv}
set mac  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_mac_cell.sv}
set tail {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv}
set arr  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_array.sv}
set tb   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_array_bmg.sv}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] $ref
# IP sim wrapper（.veo 注：须编 wrapper 并引仿真库）
run_tool [file join $xsimbin xvlog.exe] \
    [file join $ipdir gemm_bm_lut sim gemm_bm_lut.v]
run_tool [file join $xsimbin xvlog.exe] -sv $core $acc $mac $tail $arr $tb
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_arr4_bmg tb_gemm_array_4x4_bmg glbl
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_arr8_bmg tb_gemm_array_8x16_bmg glbl
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_arr16_bmg tb_gemm_array_16x16_bmg glbl

puts "EES_VIVADO_STAGE SIMULATE_4X4"
run_tool [file join $xsimbin xsim.exe] tb_arr4_bmg -runall
puts "EES_VIVADO_STAGE SIMULATE_8X16"
run_tool [file join $xsimbin xsim.exe] tb_arr8_bmg -runall
puts "EES_VIVADO_STAGE SIMULATE_16X16"
run_tool [file join $xsimbin xsim.exe] tb_arr16_bmg -runall
