# =====================================================================
# B0 迭代 6 : yolo_engine_top OOC gate run (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = 迭代 6 批 (requant V1.2c 单点, 其余同 v19):
#   requant V1.2c: 删 V1.2b 的 c2 组合位选 tap (prod_c_w[s_r1]) -- 该
#   tap 迫使 33x32 乘法拆出 DSP 级联、部分积落 fabric CARRY4 纹波
#   (v19 实测: sum->prod_r -2.868/14L vs v17 +0.379/1L; sum->q_lsb_r
#   -4.853/18L = v19 WNS owner)。位选挪回 c3 沿从已寄存 prod_r[s_r2]
#   取, 与桶形/OR 树并联、根上 OR -- c3 ~13L 不变, 乘法恢复 v17 映射。
#   位值逐位相同/PIPE=5 不变: M5 v20 复用 v18 黄金 PASS (compared=21465
#   同数)。其余 RTL = xbuf V2.2 + gemm_array V1.6/V1.7 + ctrl V1.8 +
#   addrgen V1.2 + requant V1.2c。
# 门链: M5 v20 TB_REQUANT_PASS (V1.2c 复跑) + M10 v20 (V1.2c 链复跑,
#   本跑同时启动) + M4/M7/M8 v18 PASS (不涉 requant 数值路径)。
# 对照 run (ooc_v19): FAIL WNS -4.853 whs +0.086 dsp48e1=141 ramb36=20
#   fmax 86.8 -- requant 乘法重映射 + ctrl->acc_clr 布局被拖烂
#   (v17 同构 -1.221/0L vs v19 -4.046/0L)。v17 基线: WNS -1.463
#   (addrgen owner) fmax 123.0。
# 本跑验证: 乘法回 DSP 级联后 WNS 回 v17 档 (~-1.4) 且 requant/acc_clr
#   布局恢复; 下一批 (迭代 7) 处理 dma_rd/dma_wr 增量寻址 + acc_clr
#   预寄存。
# batch : vivado -mode batch -source ooc_v20.tcl -nojournal
# gate  : GEMM16_OOC_TIMING_PASS  (WNS >= 0 @ create_clock 6.667ns)
# 注    : M11 (ModelSim) 通过前本跑为预跑; M11 若翻案则丢弃重跑。
# =====================================================================================================================================
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

report_utilization    -file $OUT/ooc_v20_utilization.rpt
report_timing_summary -file $OUT/ooc_v20_timing.rpt
report_drc            -file $OUT/ooc_v20_drc.rpt
report_route_status   -file $OUT/ooc_v20_route_status.rpt
write_checkpoint      -force $OUT/ooc_v20_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V20_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; per-module detail in
#      ooc_dbg8d.tcl patterns) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v20_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
