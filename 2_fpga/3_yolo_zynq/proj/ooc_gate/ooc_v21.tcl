# =====================================================================
# B0 迭代 7 : yolo_engine_top OOC gate run (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = 迭代 7 批 (dma V1.1 + dma_wr V1.3 + csr V1.1, 用户授权
#   "dma_wr/dma_rd 增量寻址" + 迭代 6 遗留布线 owner 处理):
#   dma V1.1     : 4KB 边界拍数改增量寄存器 bnd_r (接受沿 512-addr[11:3]
#                  装载, AR 发火沿 -beats) -- 删每拍 (4096-addr_r[11:0])>>3
#                  重算; v20 owner addr_r->last_burst_r -0.862 /
#                  addr_r->addr_r[31] -0.783。addr_r 变纯累加器。
#   dma_wr V1.3  : 同款镜像 (AW 侧, awaddr 本就下对齐 8B)。
#   csr V1.1     : LUT 写口寄存化 + max_fanout=32 -- v20 owner
#                  u_csr/bpend_r->u_lut/lut_reg[*][*]/CE -0.773 纯布线
#                  (组合写脉冲扇出到全部 silu_lut RAM CE, xbuf V2.1 先例)。
#                  写脉冲晚一拍, 仅配置期。
#   requant V1.2c 保持不变 (v20 已回 DSP 级联)。v20 残余 owner
#   requant prod_r[0]->sticky_r -1.187 (logic 3.27 route 4.58 = 58%,
#   拥塞布线) -- 本批以更强 P&R 指令吸收 (place Explore +
#   phys_opt AggressiveExplore + route AggressiveExplore); 若仍不达
#   0, 迭代 8 预备 requant PIPE 5->6 切分 (c3 桶形/OR 树输出寄存,
#   c4 位选+根 OR+舍入饱和; 需 M5 黄金重生成 pipe=6)。
# 门链: M9 (dma V1.1) + M9b (dma_wr V1.3) + M12 csr (V1.1) + M10 v21
#   + 本跑; M4/M5/M7/M8 不涉数值路径 (csr 写口仅配置期) 不重跑。
# 对照 run (ooc_v20): FAIL WNS -1.187 whs +0.080 dsp48e1=141 ramb36=20
#   fmax 127.3 (requant c3 route owner; 优于 v17 基线 -1.463/123.0)。
# batch : vivado -mode batch -source ooc_v21.tcl -nojournal
# gate  : GEMM16_OOC_TIMING_PASS  (WNS >= 0 @ create_clock 6.667ns)
# 注    : M11 (ModelSim) 通过前本跑为预跑; M11 若翻案则丢弃重跑。
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

report_utilization    -file $OUT/ooc_v21_utilization.rpt
report_timing_summary -file $OUT/ooc_v21_timing.rpt
report_drc            -file $OUT/ooc_v21_drc.rpt
report_route_status   -file $OUT/ooc_v21_route_status.rpt
write_checkpoint      -force $OUT/ooc_v21_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V21_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; per-module detail in
#      ooc_dbg8d.tcl patterns) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v21_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
