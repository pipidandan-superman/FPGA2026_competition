# =====================================================================
# sim_gemm_core_v21.tcl - run19: merged core gate, WNS A+B redo (run16
# decision A+B). Bank/feeder unchanged; tail V2.1 (magic-add RNE, D+5)
# + array V2.2 (mirror 5-deep) inside core V1.1. DUT = yolo_gemm_core V1.1 (the run16 OOC synthesis
# top and the board instantiation unit): paramless BMG bank + feeder +
# array(with BMG tail V2.0 D+4) in one wrapper. Single tier 8x16, G1-G9
# stimulus/golden verbatim from run08/run10a -> per-number realignment
# expected (4250 checks). Full IP set: 4x TDP bank BMG + 1x LUT BMG +
# DSP48E1 PEs -> blk_mem_gen + unisim libs + glbl.
# Run by: cmd //c vivado.bat -mode batch -source sim_gemm_core_bmg.tcl
# =====================================================================
set xil     {F:/vivado2025/2025.2/Vivado}
set xsimbin [file join $xil bin unwrapped win64.o]
set ipdir   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
set ref    {E:/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v}
set pecore {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv}
set acc    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv}
set mac    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_mac_cell.sv}
set tail   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv}
set arr    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_array.sv}
set bank   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_bank.sv}
set fed    {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_feeder.sv}
set core   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_core.sv}
set tb     {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_core_bmg.sv}

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
    [file join $ipdir gemm_bm_w_g0 sim gemm_bm_w_g0.v] \
    [file join $ipdir gemm_bm_w_g1 sim gemm_bm_w_g1.v] \
    [file join $ipdir gemm_bm_x_g0 sim gemm_bm_x_g0.v] \
    [file join $ipdir gemm_bm_x_g1 sim gemm_bm_x_g1.v] \
    [file join $ipdir gemm_bm_lut   sim gemm_bm_lut.v]
run_tool [file join $xsimbin xvlog.exe] -sv \
    $pecore $acc $mac $tail $arr $bank $fed $core $tb
run_tool [file join $xsimbin xvlog.exe] \
    {F:/vivado2025/2025.2/data/verilog/src/glbl.v}

puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} \
    -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim \
    -s tb_core_bmg tb_gemm_core_8x16_bmg glbl

puts "EES_VIVADO_STAGE SIMULATE_8X16"
run_tool [file join $xsimbin xsim.exe] tb_core_bmg -runall
