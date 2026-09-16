# =====================================================================
# B0 迭代 8 : yolo_engine_top OOC gate run (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = 迭代 8 批 (requant V1.2d + dma V1.2 + dma_wr V1.4, 全部位精确,
#   PIPE/吞吐/AXI 行为零变化 -> 黄金全复用):
#   requant V1.2d: ① c3 owner prod_r->sticky_r -0.713 —— V1.2c 的
#                  |(prod<<(65-s)) 是 64b 桶形串 64b OR 树 (~12L);
#                  位 j 存活 <=> j<=s-2, 故 == |prod[s-2:0] —— 改为
#                  c2 沿预寄存 mask_r (= ~(全1<<(s-1)), 仅依赖 s_r1,
#                  与乘法并联; c2 DSP 路径 v17 实测 +0.379 余量) 的
#                  AND+OR 树 (~8L)。② c4 档 sticky_r->y_pre_o -0.563
#                  —— 64 位加+比较饱和改范围归约 (q[63:7] 全 0/全 1
#                  <=> 在域) + 9 位加 (唯一溢出 +128)。
#   dma V1.2 / dma_wr V1.4: bnd 结算沿从 AR/AW 发火挪到突发末拍
#                  (发火装 blen_r 5b, 末拍读 blen_r/bnd_r 10 位等值/
#                  减法) —— words_r 退出 bnd 更新链 (v21 owner
#                  words_r->bnd_r -0.634)。
#   P&R 指令同 v21 (place Explore + phys_opt AggressiveExplore +
#   route AggressiveExplore)。
# 门链: M5 v22 (V1.2d 复跑 v18 黄金) + M9 v22 + M9b v22 + M12 csr v22
#   + M10 v22 + 本跑。
# 对照 run (ooc_v22): FAIL WNS -0.713 whs +0.053 dsp48e1=141 ramb36=20
#   fmax 135.5 (requant c3 / dma_wr bnd / requant c4 三档 owner)。
# batch : vivado -mode batch -source ooc_v22.tcl -nojournal
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

report_utilization    -file $OUT/ooc_v22_utilization.rpt
report_timing_summary -file $OUT/ooc_v22_timing.rpt
report_drc            -file $OUT/ooc_v22_drc.rpt
report_route_status   -file $OUT/ooc_v22_route_status.rpt
write_checkpoint      -force $OUT/ooc_v22_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V22_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; per-module detail in
#      ooc_dbg8d.tcl patterns) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v22_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
