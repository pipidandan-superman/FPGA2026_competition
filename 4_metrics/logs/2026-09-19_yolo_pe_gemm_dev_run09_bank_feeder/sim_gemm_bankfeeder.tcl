# =====================================================================
# sim_gemm_bankfeeder.tcl - run09: P1.2/V2 bank+feeder one-body gate,
# three tiers (4x4/KC8 unit / 8x16/KC64 baseline / 8x16/KC576 depth)
# from ONE TB. No DSP primitives -> plain xvlog/xelab/xsim chain.
# Run by: cmd //c vivado.bat -mode batch -source sim_gemm_bankfeeder.tcl
# =====================================================================
set xil     {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set bank    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_bank.sv}
set feeder  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_feeder.sv}
set tb      {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_bankfeeder.sv}
set tiers   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_gemm_bank_tiers.sv}

proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] -sv $bank $feeder $tb $tiers

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -s tb_bk1 tb_gemm_bank_4x4_kc8
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -s tb_bk2 tb_gemm_bank_8x16_kc64
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -s tb_bk3 tb_gemm_bank_8x16_kc576

puts "EES_VIVADO_STAGE SIMULATE_4X4_KC8"
run_tool [file join $xsimbin xsim.exe] tb_bk1 -runall
puts "EES_VIVADO_STAGE SIMULATE_8X16_KC64"
run_tool [file join $xsimbin xsim.exe] tb_bk2 -runall
puts "EES_VIVADO_STAGE SIMULATE_8X16_KC576"
run_tool [file join $xsimbin xsim.exe] tb_bk3 -runall
