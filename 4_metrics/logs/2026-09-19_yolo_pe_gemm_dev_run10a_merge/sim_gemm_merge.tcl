# =====================================================================
# sim_gemm_merge.tcl - run10a: P1.3/V4 three-body merged gate
# (yolo_gemm_bank + yolo_gemm_feeder + yolo_gemm_array), two tiers
# (4x4 unit / 8x16 G2 baseline) from ONE TB. TB does block-granular
# scheduling only: load block into bank via 64b stream port (groups
# alternate b%2), hand job to feeder; word stream is real wiring.
# 16x16 not run: W word 128b has no 64b write-port path (run08
# coverage frozen). MAC grid carries real DSP48E1 -> unisim + glbl.
# Run by: cmd //c vivado.bat -mode batch -source sim_gemm_merge.tcl
# =====================================================================

set xil   {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set ref  {E:/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v}
set core {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv}
set acc  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv}
set mac  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_mac_cell.sv}
set tail {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv}
set arr  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_array.sv}
set bank {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_bank.sv}
set fed  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_feeder.sv}
set tb   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_merge.sv}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] $ref
run_tool [file join $xsimbin xvlog.exe] -sv $bank $fed $core $acc $mac $tail $arr $tb
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}
puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L unisims_ver -L unisim -s tb_mrg4 tb_gemm_merge_4x4 glbl
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L unisims_ver -L unisim -s tb_mrg8 tb_gemm_merge_8x16 glbl

puts "EES_VIVADO_STAGE SIMULATE_4X4"
run_tool [file join $xsimbin xsim.exe] tb_mrg4 -runall
puts "EES_VIVADO_STAGE SIMULATE_8X16"
run_tool [file join $xsimbin xsim.exe] tb_mrg8 -runall
