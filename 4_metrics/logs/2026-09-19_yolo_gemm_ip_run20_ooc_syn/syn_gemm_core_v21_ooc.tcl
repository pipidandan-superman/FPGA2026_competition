# =====================================================================
# syn_gemm_core_v21_ooc.tcl - run20: WNS A+B timing-closure gate (run16
# decision A+B, user authorized 2026-09-19). OOC synthesis of
# yolo_gemm_core V1.1 (tail V2.1 magic-add RNE + array V2.2 mirror):
# TARGET WNS >= 0 @ 100 MHz. Same real-IP flow as run16:
# read_ip x5 (4x TDP bank BMG + 1x LUT BMG), GENERATE_SYNTH_CHECKPOINT
# false -> inline IP synthesis, one configuration (Kc is purely logical
# since bank V2.0.1 -- no P_KC generic), 100 MHz board target clock.
# Judgement (redo plan): BRAM36 = 12 (bank) + BRAM18 = 1 (LUT), no FF
# explosion, WNS measured FRESH (run10b's -6.383 on the pre-IP core is
# NOT authority), no new critical warnings. OOC: create_clock +
# in->out false_path; internal reg-reg fully timed.
# Run: cmd //c vivado.bat -mode batch -source syn_gemm_core_bmg_ooc.tcl -notrace -nojournal
# =====================================================================

set part   xc7z020clg484-1
set refdir {E:/competition/2_fpga/3_yolo_zynq/rtl}
set gdir   {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM}
set ipdir  {E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/ip}
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
    read_ip [file join $ipdir gemm_bm_w_g0 gemm_bm_w_g0.xci]
    read_ip [file join $ipdir gemm_bm_w_g1 gemm_bm_w_g1.xci]
    read_ip [file join $ipdir gemm_bm_x_g0 gemm_bm_x_g0.xci]
    read_ip [file join $ipdir gemm_bm_x_g1 gemm_bm_x_g1.xci]
    read_ip [file join $ipdir gemm_bm_lut   gemm_bm_lut.xci]
} emsg]} { bail "read: $emsg" }

puts "EES_SYNTH_STAGE IP_SYNTH_OOC"
if {[catch {
    generate_target all [get_ips]
    synth_ip [get_ips]
} emsg]} { bail "ip synth: $emsg" }

puts "EES_SYNTH_STAGE BEGIN_BMG (Kc logical, period=10.000ns)"
if {[catch {
    synth_design -top yolo_gemm_core -part $part -mode out_of_context \
        -generic [list P_TO=8 P_TN=16]
} emsg]} { bail "synth: $emsg" }
if {[catch {
    create_clock -period 10.000 -name clk_i [get_ports clk_i]
    set_false_path -from [all_inputs] -to [all_outputs]

    report_utilization -file [file join $outdir util_bmg.rpt]
    report_timing_summary -max_paths 8 -file [file join $outdir timing_bmg.rpt]

    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    puts "EES_SYNTH_RESULT BMG WNS=$wns WHS=$whs period=10.000ns"
    set ndsp [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == DSP && REF_NAME =~ DSP48E1*}]]
    puts "EES_SYNTH_RESULT BMG DSP48E1=$ndsp"
    set nb36 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB36*}]]
    set nb18 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB18*}]]
    puts "EES_SYNTH_RESULT BMG BRAM36=$nb36 BRAM18=$nb18 (judge: 12 bank + 1 lut)"
    set nff [llength [get_cells -hierarchical -filter {IS_SEQUENTIAL && PRIMITIVE_GROUP == REGISTER}]]
    puts "EES_SYNTH_RESULT BMG FF_cells=$nff"
} emsg]} { puts "EES_SYNTH_FAIL BMG report: $emsg" }
catch {close_design}
puts "EES_SYNTH_STAGE END_BMG"

puts "EES_VIVADO_RESULT DONE"
