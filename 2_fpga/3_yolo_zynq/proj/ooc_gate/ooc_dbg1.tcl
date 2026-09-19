# B0 debug pass 1: synthesis only + hierarchical utilization
# purpose: locate the 110 extra DSP48E1 and the LUTRAM/LUT2 inflation
set RTL E:/competition/2_fpga/3_yolo_zynq/rtl
set OUT E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate

read_verilog [list \
    $RTL/yolo_engine_top.v \
    $RTL/yolo_gemm_array.v \
    $RTL/yolo_csr.v \
    $RTL/yolo_ctrl.v \
    $RTL/yolo_dma.v \
    $RTL/yolo_dma_wr.v \
    $RTL/yolo_wbuf.v \
    $RTL/yolo_xbuf.v \
    $RTL/yolo_addrgen.v \
    $RTL/yolo_pe_pack.v \
    $RTL/yolo_acc.v \
    $RTL/yolo_requant.v \
    $RTL/yolo_silu_lut.v \
]

synth_design -top yolo_engine_top -part xc7z020clg484-1 -mode out_of_context
create_clock -period 6.667 -name clk_i [get_ports clk_i]

report_utilization -hierarchical -hierarchical_depth 4 -file $OUT/ooc_dbg1_hier_util.rpt
write_checkpoint -force $OUT/ooc_dbg1_synth.dcp
puts "OOC_DBG1_SYNTH_DONE"
