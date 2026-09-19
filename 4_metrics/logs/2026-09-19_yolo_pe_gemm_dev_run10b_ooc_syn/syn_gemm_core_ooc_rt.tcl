# =====================================================================
# syn_gemm_core_ooc_rt.tcl - run10b retiming 探针：同 run10b 双配置，
# 仅加 synth_design -retiming（不动任何 RTL——冻结纪律下的纯综合选项
# 探索）。目的：共享尾末级（sh2_r→y_r，41 级逻辑 16.38ns）能否靠
# 寄存器搬移切分；若仍违例则 P1.4 定案交用户决策。
# Run: cmd //c vivado.bat -mode batch -source syn_gemm_core_ooc_rt.tcl -notrace -nojournal
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
    puts "EES_SYNTH_STAGE BEGIN_$tag (KC=$kc, period=${period}ns, retiming=on)"
    if {[catch {
        synth_design -top yolo_gemm_core -part $part -mode out_of_context \
            -retiming -generic [list P_TO=8 P_TN=16 P_KC=$kc]
    } emsg]} { puts "EES_SYNTH_FAIL $tag synth: $emsg"; catch {close_design}; return }
    if {[catch {
        create_clock -period $period -name clk_i [get_ports clk_i]
        set_false_path -from [all_inputs] -to [all_outputs]

        report_utilization -file [file join $outdir util_$tag.rpt]
        report_timing_summary -max_paths 8 -file [file join $outdir timing_$tag.rpt]

        set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
        set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
        puts "EES_SYNTH_RESULT $tag WNS=$wns WHS=$whs KC=$kc period=${period}ns retiming=on"
    } emsg]} { puts "EES_SYNTH_FAIL $tag report: $emsg" }
    catch {close_design}
    puts "EES_SYNTH_STAGE END_$tag"
}

ooc_run KC576RT  10.000 576
ooc_run KC1024RT 10.000 1024

puts "EES_VIVADO_RESULT DONE"
