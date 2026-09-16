# =====================================================================
# B0 dbg8d 迭代 2 : yolo_engine_top OOC gate run05 (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = V1.5 批 (gemm_array V1.5 + ctrl V1.5, 其余同 v14):
#   (a) rq_addr 修复: d0 行解码改 fire 门控增量计数器 oc_loc_q/
#       n_loc_q (末拍 FIRE / 描述符接受沿复位), d1 捕获 oc_g/n_base
#       部分项, row_addr 乘法移到 d1->d2 沿寄存步 (v14 -6.507ns/17L)
#   (b) ctrl rq_limit 乘法移 S_TILE 拍 (寄存 x 寄存) (v14 -5.571ns/11L)
#   (c) acc 分组 en/clr 副本 + rq_en_d1_r 加 max_fanout (v14 -4.153ns
#       纯布线 x2, 综合合并跨组网线)
# 门链: M8 v15 TB_CTRL_PASS compared=706403 (黄金不变) +
#       M10 v15 TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447
#       gold_wr=3247 (逐拍等价承证).
# 对照 run04 (ooc_v14): WNS -6.507 whs +0.108 dsp48e1=140 ramb36=20.
#   v14 剩余 owner (dbg8d): rq_addr -6.507/17L, ctrl -5.571/11L,
#   acc CE -4.153/1L, requant CE -4.153/0L, PE -3.390/2L (BMG->DSP),
#   xbuf -2.929/11L (addrgen kw_r->DIADI), addrgen -2.774/9L,
#   dma_rd -2.172/11L, dma_wr -1.871/14L, wbuf -1.380/3L.
# 本跑验证: (a) top4 (requant-tail 族) 消除后 WNS 收敛到 PE/xbuf
#   tier (-3.4ns 附近) 或更好; (b) DSP/BRAM 计数不增.
# batch : vivado -mode batch -source ooc_v15.tcl -nojournal
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

report_utilization    -file $OUT/ooc_v15_utilization.rpt
report_timing_summary -file $OUT/ooc_v15_timing.rpt
report_drc            -file $OUT/ooc_v15_drc.rpt
report_route_status   -file $OUT/ooc_v15_route_status.rpt
write_checkpoint      -force $OUT/ooc_v15_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V15_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; per-module detail in
#      ooc_dbg8d.tcl patterns) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v15_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
