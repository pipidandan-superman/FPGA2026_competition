# =====================================================================
# B0 dbg8e 迭代 3 : yolo_engine_top OOC gate run06 (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = 迭代 3 批 (addrgen V1.2 + ctrl V1.6 + requant V1.2, 其余同 v15):
#   (a) xbuf 修复: addrgen 输出寄存级 (vld/x_addr/pad/pad_val/k/n +1 拍
#       呈现, start->beat0 19->20 拍; done_o 保持末呈现拍后一拍) -- pad/
#       窗口解码不再直通 BMG DIADI (v15 -1.982ns/11L)
#   (b) addrgen last_k: oy 环绕 row_off 更新折叠 m_iw_r 单加 (v15
#       -1.537ns/8L 串行减加 -> 并行双加法器+选择)
#   (c) ctrl V1.6: 末 tile 尾宽接受拍预存, S_RQ 前进=比较+2:1 (v15
#       -1.856ns/12L tail_calc 链删除)
#   (d) requant V1.2: 64 位 lo_sh 寄存器降为 1 位 sticky (c3 沿折叠,
#       v15 -1.746ns/22L c4 拍 OR 归约链消除)
# 门链: M7 v16 TB_ADDRGEN_PASS compared=67918 (流值不变 +1 拍平移) +
#       M5 v16 TB_REQUANT_PASS compared=21465 pipe=5 + M8 v16
#       TB_CTRL_PASS compared=706403 (黄金不变) + M10 v16
#       TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447
#       gold_wr=3247 (逐拍等价承证).
# 对照 run05 (ooc_v15): WNS -1.982 whs +0.091 dsp48e1=141 ramb36=20.
#   v15 剩余 owner (dbg8e): xbuf -1.982/11L, ctrl -1.856/12L, requant
#   -1.746/22L, addrgen -1.537/8L, dma_wr -1.248/13L, dma_rd -1.163/14L,
#   PE -1.151/2L (BMG->DSP 布线, 需 BMG 输出寄存合同变更--缓), wbuf
#   -1.036/1L, acc -0.823/12L, rq_addr -0.787/1L (已修).
# 本跑验证: top4 修复后 WNS 收敛到 dma/PE tier (~-1.2) 或更好; DSP/BRAM
#   计数不增.
# batch : vivado -mode batch -source ooc_v17.tcl -nojournal
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

report_utilization    -file $OUT/ooc_v17_utilization.rpt
report_timing_summary -file $OUT/ooc_v17_timing.rpt
report_drc            -file $OUT/ooc_v17_drc.rpt
report_route_status   -file $OUT/ooc_v17_route_status.rpt
write_checkpoint      -force $OUT/ooc_v17_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V17_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; per-module detail in
#      ooc_dbg8d.tcl patterns) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v17_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
