# =====================================================================
# sim_acc_dual.tcl - dual-INT32 accumulator standalone gate sim
# (PE manual section 10 accumulator row; pure fabric RTL: no unisim,
# no glbl, no DSP primitive).
# Run by: cmd //c vivado.bat -mode batch -source sim_acc_dual.tcl
# =====================================================================

set xsimbin [file join $env(XILINX_VIVADO) bin unwrapped win64.o]
set dut {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv}
set tb  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_acc_dual.sv}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] -sv $dut $tb

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -s tb_acc_dual tb_yolo_acc_dual

puts "EES_VIVADO_STAGE SIMULATE"
run_tool [file join $xsimbin xsim.exe] tb_acc_dual -runall
