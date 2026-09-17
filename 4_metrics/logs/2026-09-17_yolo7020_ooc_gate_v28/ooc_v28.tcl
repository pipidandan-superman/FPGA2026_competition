# ============================================================
# OOC gate v28 -- A2 loader V2 first P&R (2026-09-17)
#   RTL = A2 batch (M10 run13 / M11 run05): gemm_array V2.0c
#     (loader V2 三件套: W 跨 n_tile 持久 wbuf V3.0 + X 行段流式
#     dma V1.4/xrowgen V1.3/xbuf V3.0 + requant 尾 2-slot 重叠,
#     Fix #9-#12) + engine_top V1.1 (组合 X 口退役 -> 第二条 AXI4
#     读主 x_m_axi_* 引到顶层; dsc_walk CSR DESC1[19] 接线) +
#     csr V1.2 (DESC1[19] walk 影子位)。addrgen 自此退役, 不入
#     编译/综合集 (xrowgen 接管 X 地址生成)。
#   IP  = 两个 BMG: yolo_wbuf_bmg (新, 双 bank W 阵) + yolo_xbuf_bmg
#     (V2.2 重生成版)。wbuf BMG 换掉行为阵列 -> 预期 RAMB36 +32
#     (v27=20 -> ~52, XC7Z020=140, 裕量足; 资源回声行核对)。
#   时序风险: Fix #11 把 acc en 链 4 级缩到 3 级 (wv+3 开门) --
#     PE 墙后段路径 +1 级组合压, wbuf BMG 读路径 (D+2 dout_vld)
#     与 xrowgen/xbuf 新数据路径首次过 P&R。目标 WNS >= 0 @150MHz。
#   Previous: v27 PASS (B0 V1.10 iteration 13, row-addr DSP split,
#     wns +0.061 fmax 151.39) -- 对照 run (ooc_v27_drv.log)。
#
# batch : vivado -mode batch -source ooc_v28.tcl -nojournal
# gate  : GEMM16_OOC_TIMING_PASS  (WNS >= 0 @ create_clock 6.667ns)
# ============================================================

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
    $RTL/yolo_xrowgen.v \
    $RTL/yolo_pe_pack.v \
    $RTL/yolo_acc.v \
    $RTL/yolo_requant.v \
    $RTL/yolo_silu_lut.v \
]

# 会话内显式部件工程（须在 read_verilog 之前建，否则新工程为空 ->
# top not found，二跑实证）:
create_project -in_memory -part xc7z020clg484-1

read_verilog $filelist

# BMG IP ×2 (wbuf V3.0 + xbuf V3.0 bank storage). V2.2 重生成后裸
# read_ip 不再够: 无工程上下文默认部件 xc7vx485t -> IP locked
# (IP_Flow 19-2162), 且 in-memory 改配后产品状态与 DCP 失配 ->
# Synth 8-439 module not found (首跑实证). 会话内显式部件 + 重生成
# + synth_ip -force（IP 已有 DCP 在位，不带 -force 写回报
# Common 17-176，二跑实证）:
read_ip $IPD/yolo_wbuf_bmg/yolo_wbuf_bmg.xci
generate_target all [get_ips yolo_wbuf_bmg]
synth_ip [get_ips yolo_wbuf_bmg] -force

read_ip $IPD/yolo_xbuf_bmg/yolo_xbuf_bmg.xci
generate_target all [get_ips yolo_xbuf_bmg]
synth_ip [get_ips yolo_xbuf_bmg] -force

# OOC island: all top-level I/O auto false-pathed; PROD-16x16 default params
synth_design -top yolo_engine_top -part xc7z020clg484-1 -mode out_of_context

# 150 MHz pure clock constraint (arch decision 2026-09-16; no IO delay)
create_clock -period 6.667 -name clk_i [get_ports clk_i]

opt_design
# 迭代 7+: 强 P&R 指令 (place Explore + phys_opt AggressiveExplore +
# route AggressiveExplore) -- 沿用 v21-v27 定妆组合
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore

report_utilization    -file $OUT/ooc_v28_utilization.rpt
report_timing_summary -file $OUT/ooc_v28_timing.rpt
report_drc            -file $OUT/ooc_v28_drc.rpt
report_route_status   -file $OUT/ooc_v28_route_status.rpt
write_checkpoint      -force $OUT/ooc_v28_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V28_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v28_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
