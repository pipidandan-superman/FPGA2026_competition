# =====================================================================
# B0 迭代 5 收尾 : yolo_engine_top OOC gate run (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = 迭代 5 批 (xbuf V2.2 BMG 输出寄存合同, 2026-09-17 用户授权):
#   (a) xbuf V2.2: BMG Register_PortB_Output_of_Memory_Primitives=true,
#       读延迟 1->2 (dbg8f/g PE -0.87/-0.69ns 2L 布线 owner 消除)
#   (b) gemm_array V1.6: W 广播寄存 wrow_d1_r (两操作数同在 D+2 入墙,
#       乘积 D+5); acc 使能链 3->4 级; wbuf 写束一级寄存 + tile_load_done
#       !wpipe_we_q 排空判据
#   (c) ctrl V1.8: S_DRAIN 3->4 拍 (末 K 拍 tk -> acc 落地 tk+5 ->
#       requant 采样 tk+6)
#   (d) gemm_array V1.7: 末拍后补一拍 flush 读 (xren_flush_q) -- BMG 两
#       级均 ENB 门控, 末拍 word[K-1] 滞留 stage1 永不到 stage2 (M10 v18
#       根因, lane(0,0) acc +198 实证)
# 门链: M4 v18 TB_XBUF_PASS compared=97464 (黄金再生成, 延迟平移) +
#       M5 v18 TB_REQUANT_PASS compared=21465 pipe=5 + M7 v18
#       TB_ADDRGEN_PASS compared=67918 + M8 v18 TB_CTRL_PASS
#       compared=708674 (drain 3->4 镜像) + M10 v19
#       TB_GEMM_ARRAY_PASS (V1.7 修复后).
# 对照 run (ooc_v17): WNS -1.463 whs +0.039 dsp48e1=141 ramb36=20
#   fmax 123.0. v17 剩余 owner: PE -1.463/2L (BMG 源语输出->DSP A/B,
#   本批合同消除), dma_rd -1.297/9L, acc -1.242/12L, wbuf -1.107/9L,
#   xbuf -1.083/2L, requant -1.024/11L, dma_wr -0.968/10L.
# 本跑验证: BMG 输出寄存吸掉 PE tier 后 WNS 收敛到 dma/acc tier
#   (~-1.3) 或更好; DSP/BRAM 计数不增.
# batch : vivado -mode batch -source ooc_v19.tcl -nojournal
# gate  : GEMM16_OOC_TIMING_PASS  (WNS >= 0 @ create_clock 6.667ns)
# 注    : M11 (ModelSim) 通过前本跑为预跑; M11 若翻案则丢弃重跑.
# =====================================================================
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
place_design
phys_opt_design
route_design

report_utilization    -file $OUT/ooc_v19_utilization.rpt
report_timing_summary -file $OUT/ooc_v19_timing.rpt
report_drc            -file $OUT/ooc_v19_drc.rpt
report_route_status   -file $OUT/ooc_v19_route_status.rpt
write_checkpoint      -force $OUT/ooc_v19_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V19_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; per-module detail in
#      ooc_dbg8d.tcl patterns) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v19_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
