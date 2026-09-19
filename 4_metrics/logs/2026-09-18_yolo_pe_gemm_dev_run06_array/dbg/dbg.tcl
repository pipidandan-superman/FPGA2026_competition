set xsimbin [file join $env(XILINX_VIVADO) bin unwrapped win64.o]
set ref  {E:/competition/2_fpga/3_yolo_zynq/rtl/yolo_pe_pack.v}
set core {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv}
set acc  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv}
set mac  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_mac_cell.sv}
set tail {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv}
set arr  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_array.sv}
set tb   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_dbg_arr.sv}
proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}
run_tool [file join $xsimbin xvlog.exe] $ref
run_tool [file join $xsimbin xvlog.exe] -sv $core $acc $mac $tail $arr $tb
run_tool [file join $xsimbin xvlog.exe] {F:/vivado2025/2025.2/data/verilog/src/glbl.v}
run_tool [file join $xsimbin xelab.exe] -debug off -timescale {1ns/1ps} -L unisims_ver -L unisim -s tb_dbg tb_dbg_arr glbl
run_tool [file join $xsimbin xsim.exe] tb_dbg -runall
