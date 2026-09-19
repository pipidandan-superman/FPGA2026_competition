# =====================================================================
# sim_mac_cell.tcl - level-2 joint MAC gate sim (real DSP48E1 PE
# feeding the dual INT32 accumulator; xsim + unisim DSP48E1).
# Run by: cmd //c vivado.bat -mode batch -source sim_mac_cell.tcl
# Working directory = run directory; all products stay here.
# =====================================================================

set xsimbin [file join $env(XILINX_VIVADO) bin unwrapped win64.o]
set ref  {E:/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v}
set core {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv}
set acc  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv}
set mac  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_mac_cell.sv}
set tb   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_mac_cell.sv}
set gold {E:/competition/4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run01/golden_pe.hex}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] $ref
run_tool [file join $xsimbin xvlog.exe] -sv $core $acc $mac $tb
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L unisims_ver -L unisim -s tb_mac_cell tb_yolo_mac_cell glbl

puts "EES_VIVADO_STAGE SIMULATE"
run_tool [file join $xsimbin xsim.exe] tb_mac_cell -runall \
    -testplusarg GOLDEN=$gold
