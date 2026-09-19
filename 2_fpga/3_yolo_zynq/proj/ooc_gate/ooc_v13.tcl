# =====================================================================
# UG479 合规批 B0 : yolo_engine_top OOC gate run03 (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = pe_pack V1.2 (DSP48E1 3-stage pipeline AREG/BREG/MREG/PREG=1,
#   C/D tie-off Table 2-2 note 1, explicit flow-through control regs)
# + gemm_array V1.3 (acc_en 3-cycle retime) + ctrl V1.3 (S_DRAIN).
# 对照 run02 (V1.1 0-stage pipeline): WNS -31ns, DSP=128.
# 本跑验证: (a) DSP 计数保持 128 (1/PE, 不因 MREG/PREG 拆乘法);
#   (b) WNS 从 -31ns 收敛改善 (UG479 p.14 三级流水时序收益).
# batch : vivado -mode batch -source ooc_v13.tcl -nojournal
# gate  : GEMM16_OOC_TIMING_PASS  (WNS >= 0 @ create_clock 6.667ns)
# 注    : M11 (ModelSim) 通过前本跑为预跑; M11 若翻案则丢弃重跑.
# =====================================================================

set RTL E:/competition/2_fpga/3_yolo_zynq/rtl
set IPD E:/competition/2_fpga/3_yolo_zynq/ip
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

# BMG IP (xbuf bank storage) -- pre-synthesized OOC DCP reused
read_ip $IPD/yolo_xbuf_bmg/yolo_xbuf_bmg.xci

# OOC island: all top-level I/O auto false-pathed; PROD-16x16 default params
synth_design -top yolo_engine_top -part xc7z020clg484-1 -mode out_of_context

# 150 MHz pure clock constraint (arch decision 2026-09-16; no IO delay)
create_clock -period 6.667 -name clk_i [get_ports clk_i]

opt_design
place_design
phys_opt_design
route_design

report_utilization    -file $OUT/ooc_v13_utilization.rpt
report_timing_summary -file $OUT/ooc_v13_timing.rpt
report_drc            -file $OUT/ooc_v13_drc.rpt
report_route_status   -file $OUT/ooc_v13_route_status.rpt
write_checkpoint      -force $OUT/ooc_v13_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V13_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
