# =====================================================================
# sim_bankfeeder_bmg.tcl - run12: bank+feeder one-body gate, BMG IP
# redo (user order sequence 2). DUT = yolo_gemm_bank V2.0.1 (4×BMG IP)
# + yolo_gemm_feeder. Three tiers from ONE TB, all 8x16 with logical
# KC {8, 64, 576}. BMG behavioral model from the xsim precompiled
# library blk_mem_gen_v8_4_12; RAM primitives via unisims_ver + glbl.
# Run by: cmd //c vivado.bat -mode batch -source sim_bankfeeder_bmg.tcl
# =====================================================================
set xil     {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set ipdir   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
set bank    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_bank.sv}
set feeder  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_feeder.sv}
set tb      {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_bankfeeder_bmg.sv}
set tiers   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_gemm_bank_tiers_bmg.sv}

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
run_tool [file join $xsimbin xvlog.exe] -sv $bank $feeder $tb $tiers
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_bmg1 tb_gemm_bank_8x16_kc8
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_bmg2 tb_gemm_bank_8x16_kc64
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_bmg3 tb_gemm_bank_8x16_kc576

puts "EES_VIVADO_STAGE SIMULATE_8X16_KC8"
run_tool [file join $xsimbin xsim.exe] tb_bmg1 -runall
puts "EES_VIVADO_STAGE SIMULATE_8X16_KC64"
run_tool [file join $xsimbin xsim.exe] tb_bmg2 -runall
puts "EES_VIVADO_STAGE SIMULATE_8X16_KC576"
run_tool [file join $xsimbin xsim.exe] tb_bmg3 -runall
