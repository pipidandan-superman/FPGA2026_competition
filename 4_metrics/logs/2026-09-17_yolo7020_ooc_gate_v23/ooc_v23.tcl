# =====================================================================
# B0 迭代 9 : yolo_engine_top OOC gate run (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = 迭代 9 批 (dma V1.3 + dma_wr V1.5, 位精确纯重定时, AXI 行为/
#   周期零变化 -> 黄金全复用):
#   dma V1.3 / dma_wr V1.5: AW/AR 突发参数预计算拆沿 —— v22 top10 全体
#     为 words_r->addr_r -0.581 / words_r->words_r -0.496 (发火沿串行
#     min(words,16) 24b 比较 -> min(bnd,*) -> 32b 减 -> 32b addr 加)。
#     want2_r=min(words_r,16) 与 addr_r 推进 (+blen_r<<3) 均改在上一
#     突发末拍装载/结算 (words_r/addr_r/blen_r 全突发稳定); 发火沿只剩
#     min(bnd_r,want2_r) 10b 比较 + 一次 32b 减法, addr_r 发火沿纯寄存
#     器搬运。
#   P&R 指令同 v21/v22 (place Explore + phys_opt AggressiveExplore +
#   route AggressiveExplore)。
# 门链: M9 v23 + M9b v23 (计数逐字节一致) + M12 csr v23 + M10 v23
#   + 本跑。
# 对照 run (ooc_v22): FAIL WNS -0.581 whs +0.096 fmax 137.97
#   dsp48e1=141 ramb36=20 (top10 全体 = dma_wr words_r 家族)

# batch : vivado -mode batch -source ooc_v23.tcl -nojournal
# gate  : GEMM16_OOC_TIMING_PASS  (WNS >= 0 @ create_clock 6.667ns)
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

# 会话内显式部件工程（须在 read_verilog 之前建，否则新工程为空 ->
# top not found，二跑实证）:
create_project -in_memory -part xc7z020clg484-1

read_verilog $filelist

# BMG IP (xbuf bank storage). V2.2 重生成后裸 read_ip 不再够: 无工程
# 上下文默认部件 xc7vx485t -> IP locked (IP_Flow 19-2162), 且 in-memory
# 改配后产品状态与 DCP 失配 -> Synth 8-439 module not found (首跑实证;
# v17 时代 .xci/DCP 一致才幸免). 会话内显式部件 + 重生成 + synth_ip
# -force（IP 已有 DCP 在位，不带 -force 写回报 Common 17-176，二跑
# 实证；IP 级综合仅 ~25s）:
read_ip $IPD/yolo_xbuf_bmg/yolo_xbuf_bmg.xci
generate_target all [get_ips yolo_xbuf_bmg]
synth_ip [get_ips yolo_xbuf_bmg] -force

# OOC island: all top-level I/O auto false-pathed; PROD-16x16 default params
synth_design -top yolo_engine_top -part xc7z020clg484-1 -mode out_of_context

# 150 MHz pure clock constraint (arch decision 2026-09-16; no IO delay)
create_clock -period 6.667 -name clk_i [get_ports clk_i]

opt_design
# 迭代 7: 更强 P&R 指令吸收 requant c3 布线压 (v20 route 占 58%)
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore

report_utilization    -file $OUT/ooc_v23_utilization.rpt
report_timing_summary -file $OUT/ooc_v23_timing.rpt
report_drc            -file $OUT/ooc_v23_drc.rpt
report_route_status   -file $OUT/ooc_v23_route_status.rpt
write_checkpoint      -force $OUT/ooc_v23_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V23_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; per-module detail in
#      ooc_dbg8d.tcl patterns) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v23_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
