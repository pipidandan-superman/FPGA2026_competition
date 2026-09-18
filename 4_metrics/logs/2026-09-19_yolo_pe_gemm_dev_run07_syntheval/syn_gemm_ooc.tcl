# =====================================================================
# syn_gemm_ooc.tcl - run07 GEMM 上板准备：16x16 阵列 OOC 综合评估
#   A: 真配置 P_KMAX=2304 @ 100 MHz（板上目标频率，含 ③ 档功能缓冲代价）
#   B: 核视图 P_KMAX=64   @ 100 MHz（剥离缓冲伪影，看 MAC 网格+尾+FSM 本征时序）
#   C: 真配置 P_KMAX=2304 @ 150 MHz（余量探针）
# OOC 约束：create_clock + in->out false_path；内部 reg-reg 全计时。
# Run: cmd //c vivado.bat -mode batch -source syn_gemm_ooc.tcl -notrace -nojournal
# =====================================================================

set part   xc7z020clg484-1
set refdir {E:/competition/2_fpga/3_yolo_zynq/rtl}
set gdir   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM}
set outdir [file dirname [file normalize [info script]]]

proc bail {msg} { puts "EES_SYNTH_FAIL $msg"; exit 1 }

puts "EES_SYNTH_STAGE READ_SOURCES"
if {[catch {
    read_verilog [file join $refdir yolo_pe_pack.v]
    read_verilog -sv [file join $gdir yolo_pe_core.sv] \
                       [file join $gdir yolo_acc_dual.sv] \
                       [file join $gdir yolo_mac_cell.sv] \
                       [file join $gdir yolo_gemm_tail.sv] \
                       [file join $gdir yolo_gemm_array.sv]
} emsg]} { bail "read: $emsg" }

proc ooc_run {tag period kmax} {
    global part outdir
    puts "EES_SYNTH_STAGE BEGIN_$tag (KMAX=$kmax, period=${period}ns)"
    if {[catch {
        synth_design -top yolo_gemm_array -part $part -mode out_of_context \
            -generic [list P_TO=16 P_TN=16 P_KMAX=$kmax]
    } emsg]} { puts "EES_SYNTH_FAIL $tag synth: $emsg"; catch {close_design}; return }
    if {[catch {
        create_clock -period $period -name clk_i [get_ports clk_i]
        set_false_path -from [all_inputs] -to [all_outputs]

        report_utilization -file [file join $outdir util_$tag.rpt]
        report_timing_summary -max_paths 8 -file [file join $outdir timing_$tag.rpt]

        set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
        set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
        puts "EES_SYNTH_RESULT $tag WNS=$wns WHS=$whs KMAX=$kmax period=${period}ns"
        set ndsp [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == DSP && REF_NAME =~ DSP48E1*}]]
        puts "EES_SYNTH_RESULT $tag DSP48E1=$ndsp"
    } emsg]} { puts "EES_SYNTH_FAIL $tag report: $emsg" }
    catch {close_design}
    puts "EES_SYNTH_STAGE END_$tag"
}

ooc_run A 10.000 2304
ooc_run B 10.000 64
ooc_run C  6.667 2304

puts "EES_VIVADO_RESULT DONE"
