# =====================================================================
# sim_tail_v21.tcl - run17: shared tail gate, WNS A+B redo (run16
# decision A+B, user authorized 2026-09-19). DUT = yolo_gemm_tail V2.1:
# RNE narrowed to the exact magic-add identity (65-bit add + barrel
# shifts, semantics bit-identical), sat/addr split into their own
# cycle; pipeline D+4 -> D+5, latency hard check updated 4 -> 5 in the
# TB. Golden cross vs run01 software oracle via -testplusarg GOLDEN=...
# Run by: cmd //c vivado.bat -mode batch -source sim_tail_v21.tcl
# =====================================================================
set xil     {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set ipdir   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
set dut     {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv}
set tb      {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_tail_bmg.sv}
set gold    {E:/competition/4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run01/golden_tail.hex}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
# IP sim wrapper（.veo 注：须编 wrapper 并引仿真库）
run_tool [file join $xsimbin xvlog.exe] \
    [file join $ipdir gemm_bm_lut sim gemm_bm_lut.v]
run_tool [file join $xsimbin xvlog.exe] -sv $dut $tb
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_tail_bmg tb_yolo_gemm_tail_bmg

puts "EES_VIVADO_STAGE SIMULATE"
run_tool [file join $xsimbin xsim.exe] tb_tail_bmg -runall \
    -testplusarg GOLDEN=$gold
