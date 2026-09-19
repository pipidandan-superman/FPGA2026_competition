# =====================================================================
# B0 dbg7c 时序修复批 : yolo_engine_top OOC gate run04 (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = ①②③ 合并批 (授权 2026-09-16):
#   ① addrgen V1.1  (S_DIV 16 拍迭代除法 + S_RUN 纯加法地址增量,
#                    修 ooc_v13 -31.0ns 95 级 capture-beat 除法链)
#   ② requant V1.1  (5 级流水 c0..c4, 修 -24.6ns 47 级单拍算术链)
# + gemm_array V1.4 (requant 尾重定时 d0..d7 / seg_infl 4 位 / acc
#   8-lane 分组 en/clr 副本 / 接 ctrl V1.4 rq_last_o)
# + ctrl V1.4       (rq_limit_r 登记式末拍比较, 修 -11.6ns 14 级)
# + xbuf V2.1       (rd_bank_q/rd_active_q max_fanout=8, 修 -10.8ns
#   128 位输出 mux bank 选择广播)
# 对照 run03 (ooc_v13): WNS -31.017 whs +0.117 dsp48e1=142 ramb36=20.
# 本跑验证: (a) WNS 自 -31ns 收敛 (150MHz 或接近, 剩余 owner 迭代);
#   (b) DSP/BRAM 计数不增 (acc 分组/流水复制不应新增乘法器或 BRAM).
# batch : vivado -mode batch -source ooc_v14.tcl -nojournal
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

report_utilization    -file $OUT/ooc_v14_utilization.rpt
report_timing_summary -file $OUT/ooc_v14_timing.rpt
report_drc            -file $OUT/ooc_v14_drc.rpt
report_route_status   -file $OUT/ooc_v14_route_status.rpt
write_checkpoint      -force $OUT/ooc_v14_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V14_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; ooc_dbg7c per-module detail
#      stays in ooc_dbg7c.tcl) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v14_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
