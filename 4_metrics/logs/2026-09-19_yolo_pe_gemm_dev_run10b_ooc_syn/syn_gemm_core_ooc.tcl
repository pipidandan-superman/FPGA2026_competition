# =====================================================================
# syn_gemm_core_ooc.tcl - run10b: P1.4 G2 计算核心（bank+feeder+array
# 三体，top=yolo_gemm_core）OOC 综合定档：8x16 两配置
#   KC576 : P_KC=576 @ 100 MHz（板上目标频率）
#   KC1024: P_KC=1024 @ 100 MHz
# 判据（执行计划 P1.4）：BRAM36≈12、无 FF 爆炸、WNS>=0 绝对值、
# 无新关键告警 → Kc 定档（决策点）。
# OOC 约束：create_clock + in->out false_path；内部 reg-reg 全计时。
# Run: cmd //c vivado.bat -mode batch -source syn_gemm_core_ooc.tcl -notrace -nojournal
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
                       [file join $gdir yolo_gemm_array.sv] \
                       [file join $gdir yolo_gemm_bank.sv] \
                       [file join $gdir yolo_gemm_feeder.sv] \
                       [file join $gdir yolo_gemm_core.sv]
} emsg]} { bail "read: $emsg" }

proc ooc_run {tag period kc} {
    global part outdir
    puts "EES_SYNTH_STAGE BEGIN_$tag (KC=$kc, period=${period}ns)"
    if {[catch {
        synth_design -top yolo_gemm_core -part $part -mode out_of_context \
            -generic [list P_TO=8 P_TN=16 P_KC=$kc]
    } emsg]} { puts "EES_SYNTH_FAIL $tag synth: $emsg"; catch {close_design}; return }
    if {[catch {
        create_clock -period $period -name clk_i [get_ports clk_i]
        set_false_path -from [all_inputs] -to [all_outputs]

        report_utilization -file [file join $outdir util_$tag.rpt]
        report_timing_summary -max_paths 8 -file [file join $outdir timing_$tag.rpt]

        set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
        set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
        puts "EES_SYNTH_RESULT $tag WNS=$wns WHS=$whs KC=$kc period=${period}ns"
        set ndsp [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == DSP && REF_NAME =~ DSP48E1*}]]
        puts "EES_SYNTH_RESULT $tag DSP48E1=$ndsp"
        set nb36 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB36*}]]
        set nb18 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB18*}]]
        puts "EES_SYNTH_RESULT $tag BRAM36=$nb36 BRAM18=$nb18 (判据≈12)"
        set nff [llength [get_cells -hierarchical -filter {IS_SEQUENTIAL && PRIMITIVE_GROUP == REGISTER}]]
        puts "EES_SYNTH_RESULT $tag FF_cells=$nff"
    } emsg]} { puts "EES_SYNTH_FAIL $tag report: $emsg" }
    catch {close_design}
    puts "EES_SYNTH_STAGE END_$tag"
}

ooc_run KC576  10.000 576
ooc_run KC1024 10.000 1024

puts "EES_VIVADO_RESULT DONE"
