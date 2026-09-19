# =====================================================================
# sim_gemm_array_v2.tcl - run08: P1.1/V1 wide-word pure-consumer array
# gate sim, three tiers (4x4 unit-debug / 8x16 baseline / 16x16
# parameterized) from ONE TB. TB drives the w_word/x_word stream
# directly (valid/ready + first/last sideband + producer jitter).
# MAC grid carries real DSP48E1 PEs -> unisim libs + glbl required.
# Run by: cmd //c vivado.bat -mode batch -source sim_gemm_array_v2.tcl
# =====================================================================

set xil   {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set ref  {E:/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v}
set core {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv}
set acc  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv}
set mac  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_mac_cell.sv}
set tail {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv}
set arr  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_array.sv}
set tb   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_array.sv}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] $ref
run_tool [file join $xsimbin xvlog.exe] -sv $core $acc $mac $tail $arr $tb
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}
puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L unisims_ver -L unisim -s tb_arr4 tb_gemm_array_4x4 glbl
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L unisims_ver -L unisim -s tb_arr8 tb_gemm_array_8x16 glbl
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L unisims_ver -L unisim -s tb_arr16 tb_gemm_array_16x16 glbl

puts "EES_VIVADO_STAGE SIMULATE_4X4"
run_tool [file join $xsimbin xsim.exe] tb_arr4 -runall
puts "EES_VIVADO_STAGE SIMULATE_8X16"
run_tool [file join $xsimbin xsim.exe] tb_arr8 -runall
puts "EES_VIVADO_STAGE SIMULATE_16X16"
run_tool [file join $xsimbin xsim.exe] tb_arr16 -runall
