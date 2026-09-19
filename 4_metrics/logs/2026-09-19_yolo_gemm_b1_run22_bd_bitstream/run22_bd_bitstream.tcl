# =====================================================================
# run22_bd_bitstream.tcl - B1: axi_gemm_test BD 扩展 + 综合 + 布局布线
# + 比特流。用户指令（2026-09-19）："bd继续扩展，连线检查，正确性检查，
# 综合，布局布线，生成比特流"；RTL 一律引用（add_files 无 -copy_to，
# 不进工程目录）。
#   Stage A: 源引用添加（10 RTL + 6 IP xci）+ 编译序
#   Stage B: BD——axi_ic0 NUM_MI=2、module_ref 例化 u_yolo_gemm、
#            M01_AXI/s_axi 连接、时钟复位复刻 u_yolo_csr 模式、
#            地址 0x43C00000/64K（u_yolo_csr 0x43C10000 不动）
#   Stage C: validate_bd_design + 地址表取证 + save
#   Stage D: 清增量检查点 → reset_runs → launch impl -to write_bitstream
#   Stage E: open_run 报告（timing/util/drc）+ WNS/WHS + xsa
# Run: cmd //c vivado.bat -mode batch -source run22_bd_bitstream.tcl
# =====================================================================
set proj  {E:/competition/2_fpga/3_yolo_zynq/proj/axi_gemm_test/axi_gemm_test.xpr}
set bdf   {E:/competition/2_fpga/3_yolo_zynq/proj/axi_gemm_test/axi_gemm_test.srcs/sources_1/bd/display_test/display_test.bd}
set rtl   {E:/competition/2_fpga/3_yolo_zynq/rtl}
set run22 {E:/competition/4_metrics/logs/2026-09-19_yolo_gemm_b1_run22_bd_bitstream}

proc bail {msg} { puts "EES_BD_FAIL $msg"; exit 1 }

# ---------------- Stage A: sources by REFERENCE ----------------
puts "EES_BD_STAGE A_SOURCES"
if {[catch {open_project $proj} emsg]} { bail "open_project: $emsg" }

set srcs [list \
    $rtl/yolo_pe_pack.v \
    $rtl/GEMM/yolo_pe_core.sv \
    $rtl/GEMM/yolo_acc_dual.sv \
    $rtl/GEMM/yolo_mac_cell.sv \
    $rtl/GEMM/yolo_gemm_tail.sv \
    $rtl/GEMM/yolo_gemm_array.sv \
    $rtl/GEMM/yolo_gemm_bank.sv \
    $rtl/GEMM/yolo_gemm_feeder.sv \
    $rtl/GEMM/yolo_gemm_core.sv \
    $rtl/GEMM/yolo_gemm_top.v]
set ips [list \
    $rtl/GEMM/ip/gemm_bm_w_g0/gemm_bm_w_g0.xci \
    $rtl/GEMM/ip/gemm_bm_w_g1/gemm_bm_w_g1.xci \
    $rtl/GEMM/ip/gemm_bm_x_g0/gemm_bm_x_g0.xci \
    $rtl/GEMM/ip/gemm_bm_x_g1/gemm_bm_x_g1.xci \
    $rtl/GEMM/ip/gemm_bm_lut/gemm_bm_lut.xci \
    $rtl/GEMM/ip/gemm_bm_ycap/gemm_bm_ycap.xci]
if {[catch {add_files -fileset sources_1 $srcs} emsg]} { bail "add_files rtl: $emsg" }
if {[catch {add_files -fileset sources_1 $ips} emsg]} { bail "add_files ip: $emsg" }
if {[catch {update_compile_order -fileset sources_1} emsg]} { bail "update_compile_order: $emsg" }
# 注意：不做 -compile_order 成员检查——module_ref 例化前 yolo_gemm_top
# 不被 top 引用、不在编译序里（鸡生蛋）；fileset 成员由下方 SRC 循环验证。
foreach f [concat $srcs $ips] {
    set fo [get_files -quiet -of [get_filesets sources_1] [file tail $f]]
    if {[llength $fo] == 0} { bail "source not in fileset: $f" }
    # 引用验证：对象名即解析路径（须仍在 rtl/ 原位，未被拷进工程）
    puts "EES_BD_SRC [file tail $f] -> $fo"
}

# ---------------- Stage B: BD 扩展 ----------------
puts "EES_BD_STAGE B_BD"
if {[catch {open_bd_design $bdf} emsg]} { bail "open_bd_design: $emsg" }

# M01 端口先扩
if {[catch {set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells axi_ic0]} emsg]} {
    bail "NUM_MI: $emsg"
}
if {[llength [get_bd_intf_pins -quiet axi_ic0/M01_AXI]] == 0} { bail "M01_AXI not created" }

# module_ref 例化（与 u_yolo_csr 同机制）
if {[catch {create_bd_cell -type module -reference yolo_gemm_top u_yolo_gemm} emsg]} {
    bail "create_bd_cell: $emsg"
}
if {[llength [get_bd_intf_pins -quiet u_yolo_gemm/s_axi]] == 0} {
    bail "u_yolo_gemm/s_axi interface NOT inferred (port-name pattern check needed)"
}

# AXI / 时钟 / 复位连线（逐项复刻 u_yolo_csr 现网模式）
if {[catch {
    connect_bd_intf_net [get_bd_intf_pins axi_ic0/M01_AXI] [get_bd_intf_pins u_yolo_gemm/s_axi]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_ic0/M01_ACLK]
    connect_bd_net [get_bd_pins rst_sys/peripheral_aresetn] [get_bd_pins axi_ic0/M01_ARESETN]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins u_yolo_gemm/s_axi_aclk]
    connect_bd_net [get_bd_pins rst_sys/peripheral_aresetn] [get_bd_pins u_yolo_gemm/s_axi_aresetn]
} emsg]} { bail "connect: $emsg" }

# 地址：0x43C00000/64K（与 u_yolo_csr 0x43C10000 并列，不重叠）。
# 正典 API = assign_bd_address -offset/-range 直接指派（set_property
# offset 对地址段只读——attempt4 教训）；不做全量 assign 以免自动偏移。
set gsegs [get_bd_addr_segs -quiet u_yolo_gemm/s_axi/*]
if {[llength $gsegs] == 0} { bail "no address seg for u_yolo_gemm" }
if {[catch {
    assign_bd_address -offset 0x43C00000 -range 0x10000 $gsegs
} emsg]} { bail "assign addr: $emsg" }

# ---------------- Stage C: 验证 + 取证 + 保存 ----------------
puts "EES_BD_STAGE C_VALIDATE"
if {[catch {validate_bd_design} emsg]} { bail "validate_bd_design: $emsg" }
puts "EES_BD_NETCHECK [get_bd_intf_nets axi_ic0_M01_AXI]"
set clkpins {}
foreach p [get_bd_pins -quiet -of_objects [get_bd_nets processing_system7_0_FCLK_CLK0]] {
    lappend clkpins [get_property NAME $p]
}
puts "EES_BD_NETCLK_FCLK $clkpins"
set rstpins {}
foreach p [get_bd_pins -quiet -of_objects [get_bd_nets rst_sys_peripheral_aresetn]] {
    lappend rstpins [get_property NAME $p]
}
puts "EES_BD_NETCLK_ARESETN $rstpins"
if {[catch {save_bd_design} emsg]} { bail "save_bd_design: $emsg" }
# 地址真值验证：从保存后的 .bd JSON 取（2025.2 segment 对象的 offset
# 属性读回为空——直接验文件才是真值；CSR 旧段不得被扰动）
set bfd [open $bdf r]; set bdtxt [read $bfd]; close $bfd
if {![regexp {0x43C00000} $bdtxt]} { bail "0x43C00000 not in saved .bd" }
if {![regexp {0x43C10000} $bdtxt]} { bail "0x43C10000 missing (CSR seg disturbed)" }
puts "EES_BD_ADDR_VERIFY 0x43C00000(gemm) + 0x43C10000(csr) both in .bd"

# ---------------- Stage D: 全新综合/实现/比特流 ----------------
puts "EES_BD_STAGE D_RUNS"
catch {set_property incremental_checkpoint {} [get_runs synth_1]} icmsg
if {[llength [get_property incremental_checkpoint [get_runs synth_1]]] != 0} {
    puts "EES_BD_WARN incr checkpoint not cleared: $icmsg"
}
if {[catch {reset_run synth_1} emsg]} { bail "reset_run: $emsg" }
if {[catch {launch_runs impl_1 -to_step write_bitstream -jobs 4} emsg]} {
    bail "launch_runs: $emsg"
}
if {[catch {wait_on_run impl_1} emsg]} { bail "wait_on_run: $emsg" }
set st [get_property STATUS [get_runs impl_1]]
set pr [get_property PROGRESS [get_runs impl_1]]
puts "EES_BD_IMPL_STATUS $st"
puts "EES_BD_IMPL_PROGRESS $pr"
if {![string match "*Complete*" $st]} { bail "impl not complete: $st ($pr)" }
set bit [file join [get_property DIRECTORY [get_runs impl_1]] display_test_wrapper.bit]
if {![file exists $bit]} { bail "bitstream missing: $bit" }
puts "EES_BD_BIT $bit [file size $bit] bytes"

# ---------------- Stage E: 报告 ----------------
puts "EES_BD_STAGE E_REPORTS"
if {[catch {open_run impl_1} emsg]} { bail "open_run: $emsg" }
report_timing_summary -file $run22/impl_timing_summary.rpt
report_utilization   -file $run22/impl_utilization.rpt
report_drc           -file $run22/impl_drc.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
puts "EES_BD_WNS $wns"
puts "EES_BD_WHS $whs"
if {[catch {write_hw_platform -fixed -include_bit -force \
        $run22/axi_gemm_test_wrapper.xsa} emsg]} {
    puts "EES_BD_WARN xsa: $emsg"
}
puts "EES_BD_RESULT DONE"
