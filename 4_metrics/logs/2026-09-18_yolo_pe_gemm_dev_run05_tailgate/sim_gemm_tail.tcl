# =====================================================================
# sim_gemm_tail.tcl - manual step 3a shared tail gate sim (pure fabric:
# sum 33b -> prod 64b -> RNE -> sat INT8 -> SiLU LUT / bypass).
# Run by: cmd //c vivado.bat -mode batch -source sim_gemm_tail.tcl
# Working directory = run directory; all products stay here.
# =====================================================================

set xsimbin [file join $env(XILINX_VIVADO) bin unwrapped win64.o]
set dut  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv}
set tb   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_tail.sv}
set gold {E:/competition/4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run01/golden_tail.hex}

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
    -s tb_gemm_tail tb_yolo_gemm_tail

puts "EES_VIVADO_STAGE SIMULATE"
run_tool [file join $xsimbin xsim.exe] tb_gemm_tail -runall \
    -testplusarg GOLDEN=$gold
