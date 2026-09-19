# =====================================================================
# sim_yolo_csr.tcl - batch simulation of the YOLO CSR subsystem
# Contract testbench tb_yolo_control_subsystem (EES markers).
# Run by: run_vivado_batch_ees.ps1 (vivado -mode batch -source ...)
# Working directory = run directory; all products stay here.
# =====================================================================

set rtl_dir {E:/competition/2_fpga/3_yolo_zynq/rtl/ps_axi_pl}
set xsimbin [file join $env(XILINX_VIVADO) bin unwrapped win64.o]

# run an external tool, echo its output, fail hard on nonzero exit
proc run_tool {args} {
    puts "% [join $args { }]"
    set rc [catch {exec {*}$args} out]
    puts $out
    if {$rc != 0} { error "TOOL_FAILED: [join $args { }]" }
}

# ---------------------------------------------------------------------
# 1) generate IP simulation products (first use of the XCIs)
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE IP_GENERATE"
create_project -in_memory -part xc7z020clg484-1
foreach ip {yolo_desc_bram yolo_buf_bram yolo_quant_bram
            yolo_lut_bram yolo_ring_bram} {
    read_ip [file join $rtl_dir ip $ip $ip.xci]
}
generate_target all -force [get_ips]
close_project

# ---------------------------------------------------------------------
# 2) compile: package + SV submodules, Verilog top, IP sim wrappers, TB
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE COMPILE"
run_tool [file join $xsimbin xvlog.exe] -sv \
    [file join $rtl_dir yolo_csr_pkg.sv] \
    [file join $rtl_dir yolo_axi_lite_slave.sv] \
    [file join $rtl_dir yolo_reg_file.sv] \
    [file join $rtl_dir yolo_desc_walker.sv] \
    [file join $rtl_dir yolo_result_ring.sv] \
    [file join $rtl_dir yolo_desc_table.sv] \
    [file join $rtl_dir yolo_buf_table.sv] \
    [file join $rtl_dir yolo_quant_table.sv] \
    [file join $rtl_dir yolo_lut_table.sv] \
    [file join $rtl_dir yolo_ring_table.sv]

run_tool [file join $xsimbin xvlog.exe] \
    [file join $rtl_dir yolo_control_subsystem.v]

run_tool [file join $xsimbin xvlog.exe] \
    {*}[glob -directory [file join $rtl_dir ip] */sim/*.v]

run_tool [file join $xsimbin xvlog.exe] -sv \
    [file join $rtl_dir tb tb_yolo_control_subsystem.sv]

# ---------------------------------------------------------------------
# 3) elaborate (precompiled BMG library from the Vivado install)
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE ELABORATE"
run_tool [file join $xsimbin xelab.exe] -debug off \
    -L blk_mem_gen_v8_4_12 -s tb_yolo_csr tb_yolo_control_subsystem

# ---------------------------------------------------------------------
# 4) run (no waveform logging; TB prints EES_VIVADO_RESULT)
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE SIMULATE"
run_tool [file join $xsimbin xsim.exe] tb_yolo_csr -runall
