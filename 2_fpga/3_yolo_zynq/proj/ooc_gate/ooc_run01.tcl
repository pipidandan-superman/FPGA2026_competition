# =====================================================================
# M12 B0 : yolo_engine_top OOC gate run01  (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# batch : vivado -mode batch -source ooc_run01.tcl -nojournal
# gate  : GEMM16_OOC_TIMING_PASS  (WNS >= 0 @ create_clock 6.667ns)
# RTL source of truth = E:/competition/2_fpga/3_yolo_zynq/rtl (by reference)
# Engine RTL only; golden cores (conv_core/conv0) are sim-only, excluded.
# =====================================================================

set RTL E:/competition/2_fpga/3_yolo_zynq/rtl
set OUT E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate

set filelist [list \
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

read_verilog $filelist

# OOC island: all top-level I/O auto false-pathed; PROD-16x16 default params
synth_design -top yolo_engine_top -part xc7z020clg484-1 -mode out_of_context

# 150 MHz pure clock constraint (arch decision 2026-09-16; no IO delay)
create_clock -period 6.667 -name clk_i [get_ports clk_i]

opt_design
place_design
phys_opt_design
route_design

report_utilization    -file $OUT/ooc_run01_utilization.rpt
report_timing_summary -file $OUT/ooc_run01_timing.rpt
report_drc            -file $OUT/ooc_run01_drc.rpt
report_route_status   -file $OUT/ooc_run01_route_status.rpt
write_checkpoint      -force $OUT/ooc_run01_routed.dcp

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
