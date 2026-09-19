# =====================================================================
# M12 B0 : yolo_engine_top OOC gate run02  (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# run01 失败链: DSP 238/220 (推断式打包乘法被拆解成双 8 位通道乘法器,
#   ooc_run01_vivado.log 保留为证). 修复 = pe_pack V1.1 DSP48E1 源语
#   直例 + xbuf V2.0 blk_mem_gen IP (13824 LUTRAM -> BRAM).
# 本跑: 与 run01 同约束同流程, 增加 BMG IP (read_ip; DCP 已由
#   ip/gen_xbuf_bmg.tcl synth_ip 产出, OOC per-IP 复用).
# batch : vivado -mode batch -source ooc_run02.tcl -nojournal
# gate  : GEMM16_OOC_TIMING_PASS  (WNS >= 0 @ create_clock 6.667ns)
# 预期  : DSP ~138 (128 PE + 1 row_addr + 5 addrgen + 4 requant),
#         BRAM ~20 RAMB36 (xbuf 双 bank), LUT ~24K (xbuf LUTRAM 出清)
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

report_utilization    -file $OUT/ooc_run02_utilization.rpt
report_timing_summary -file $OUT/ooc_run02_timing.rpt
report_drc            -file $OUT/ooc_run02_drc.rpt
report_route_status   -file $OUT/ooc_run02_route_status.rpt
write_checkpoint      -force $OUT/ooc_run02_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_RUN02_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
