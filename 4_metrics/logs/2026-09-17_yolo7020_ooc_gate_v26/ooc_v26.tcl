# ============================================================
# OOC gate v26 -- B0 iteration 12 (2026-09-17 04:1x)
#   requant V1.2g: multiply operand re-registration sum_x_r/m_x_r
#     (PIPE 6->7) -- v25 top10 sole family sum_r_reg/C ->
#     prod_c_w__2/PCIN -0.079: the 33x32 multiply is a 2-DSP
#     cascade, DSP1 traversed combinationally (A -> mult -> adder ->
#     PCOUT 4.04ns; sum_r is the c1 adder output, no input regs to
#     absorb). The pass-through stage gives AREG/BREG candidates --
#     the cascade hop launches from a DSP-internal register.
#   gemm_array V1.9: tail chain d8 -> d9 (LUT en rq_en_d8_r,
#   sideband d9, segmenter reads d9) -- pure latency shift.
#   addrgen/ctrl unchanged. Bit-exact (M5 v26 gate before this run).
#   Previous: v25 FAIL wns -0.079 (fmax 148.24). Target: wns >= 0.
#   对照 run (ooc_v25) 结果见 ooc_v25_drv.log。
# ============================================================
# =====================================================================
# B0 迭代 10 : yolo_engine_top OOC gate run (PROD-16x16, 150MHz)
# ---------------------------------------------------------------------
# RTL = 迭代 10 批 (requant V1.2e, 位精确纯重定时, PIPE=5/吞吐/AXI 行为
#   零变化 -> 黄金全复用):
#   requant V1.2e: v23 top10 全体为 prod_c_w__2/CLK->q_r -0.457..-0.340
#     (c3 拍 64 输出桶形 prod>>>s, DSP P 寄存 CLK->P + 6 级 mux + 64
#     负载路由)。q_r 消费者只需 q[7:0] (9b 舍入加, 8x 64:1 窗口 mux) +
#     q[63] (= prod[63], asr 保号, 0L) + 在域判定 (-2^(s+7)<=prod<=
#     2^(s+7)-1, magn<himask 用 c2 沿从 s_r1 预寄存的 himask_r 同
#     mask_r 模式) —— 64 位桶形整体消失 (64 FF -> 10 FF)。
#     首版 himask 取反位序错 (~(1<<t)=低位掩码), M5 v24 门拦下 2739
#     错后修复 (m5_v24a_xsim_fail.log 留档)。
#   P&R 指令同 v21-v23 (place Explore + phys_opt AggressiveExplore +
#   route AggressiveExplore)。
# 门链: M5 v24 (PASS compared=21465) + M10 v24 + M12 csr v24 + 本跑。
# 对照 run (ooc_v23): FAIL WNS -0.457 whs +0.076 fmax 140.37
#   dsp48e1=141 ramb36=20 (top10 全体 = requant c3 桶形家族)

# batch : vivado -mode batch -source ooc_v26.tcl -nojournal
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

report_utilization    -file $OUT/ooc_v26_utilization.rpt
report_timing_summary -file $OUT/ooc_v26_timing.rpt
report_drc            -file $OUT/ooc_v26_drc.rpt
report_route_status   -file $OUT/ooc_v26_route_status.rpt
write_checkpoint      -force $OUT/ooc_v26_routed.dcp

# ---- resource echo (greppable) ----
set ndsp   [llength [get_cells -hier -filter {REF_NAME =~ DSP48E1}]]
set nbram36 [llength [get_cells -hier -filter {REF_NAME =~ RAMB36E1}]]
set nbram18 [llength [get_cells -hier -filter {REF_NAME =~ RAMB18E1}]]
puts "OOC_V26_RES dsp48e1=$ndsp ramb36=$nbram36 ramb18=$nbram18"

# ---- worst-N owners (dbg iteration loop; per-module detail in
#      ooc_dbg8d.tcl patterns) ----
report_timing -max_paths 10 -path_type summary \
    -file $OUT/ooc_v26_top10.rpt

# ---- machine verdict (greppable) ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / (6.667 - $wns)}]
if {$wns >= 0} {
    puts "GEMM16_OOC_TIMING_PASS wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
} else {
    puts "GEMM16_OOC_TIMING_FAIL wns_ns=$wns whs_ns=$whs fmax_mhz=$fmax target_mhz=150.0"
}
