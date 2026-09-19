# =====================================================================
# sim_pe_core_full.tcl - single-PE FULL mode: 256^3 exhaustive stream
# (16,777,216 continuous transactions vs independent signed multiply)
# Run by: cmd //c vivado.bat -mode batch -source sim_pe_core_full.tcl
# =====================================================================

set xsimbin [file join $env(XILINX_VIVADO) bin unwrapped win64.o]
set ref  {E:/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v}
set core {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv}
set tb   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_pe_core.sv}
set gold {E:/competition/4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run01/golden_pe.hex}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] $ref
run_tool [file join $xsimbin xvlog.exe] -sv $core $tb
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L unisims_ver -L unisim -s tb_pe_full tb_yolo_pe_core glbl

puts "EES_VIVADO_STAGE SIMULATE"
run_tool [file join $xsimbin xsim.exe] tb_pe_full -runall \
    -testplusarg GOLDEN=$gold -testplusarg FULL_EXH=1
