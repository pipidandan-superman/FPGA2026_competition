# =====================================================================
# bd_integrate_template.tcl - idempotent BD integration of an RTL
# module reference into a Zynq PS block design.
#
# ADAPTATION POINTS (everything in <>):
#   <projdir>      absolute path, holds <proj>.xpr
#   <proj>         project name
#   <rtl_dir>      RTL directory (top .v + SV submodules + packages)
#   <rtl_files>    file list (V2001 top + SV deps)
#   <ip_xcis>      out-of-context IP cores used by the top (e.g. BMG)
#   <bd_name>      block design name (existing, PS7 inside)
#   <top_module>   V2001 top module name (plain Verilog-2001 only!)
#   <inst_name>    instance cell name in the BD
#   <base_addr>    mapped base (e.g. 0x43C10000)
#   <seg_range>    mapped range (e.g. 64K)
#   <fclk_mhz>     expected FCLK0 (probe only; PS7 default 100)
#
# Conventions: every create/connect is guarded so the script converges
# when rerun against a SAVED design. Finish = validate + save + PASS
# marker (a marker-based runner records FAIL without the marker).
# =====================================================================

set projdir {<projdir>}
set rtl     {<rtl_dir>}

proc net_on {pin}  { return [get_bd_nets -quiet      -of [get_bd_pins      $pin]] }
proc inet_on {pin} { return [get_bd_intf_nets -quiet -of [get_bd_intf_pins $pin]] }

puts "EES_VIVADO_STAGE BD_OPEN"
open_project $projdir/<proj>.xpr

# ---- 1) sources: RTL + OOC IP XCIs (presence-guarded) ----------------
puts "EES_VIVADO_STAGE SRC_ADD"
foreach f {<rtl_files>} {
    if {[llength [get_files -quiet -of [get_filesets sources_1] [file tail $f]]] == 0} {
        add_files -fileset sources_1 [file join $rtl $f]
        puts "SRC_ADD added  $f"
    } else { puts "SRC_ADD present $f" }
}
foreach ip {<ip_xcis>} {
    if {[llength [get_files -quiet ${ip}.xci]] == 0} {
        add_files -fileset sources_1 [file join $rtl ip $ip $ip.xci]
        puts "SRC_ADD added  $ip.xci"
    } else { puts "SRC_ADD present $ip.xci" }
}
update_compile_order -fileset sources_1

# ---- 2) PS7: GP0 master + FCLK0 + FCLK_RESET0_N ----------------------
puts "EES_VIVADO_STAGE PS_CFG"
open_bd_design [get_files <bd_name>.bd]
set ps [get_bd_cells processing_system7_0]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT  {1} \
    CONFIG.PCW_EN_RST0_PORT  {1} \
] $ps
# PCW_FCLK0_PERIPHERAL_FREQMHZ is a DYNAMIC param: probe, never set blind
if {[catch {set f0 [get_property CONFIG.PCW_FCLK0_PERIPHERAL_FREQMHZ $ps]} e]} {
    puts "PS_CFG FCLK0 freq param absent (PS7 default 100 MHz assumed)"
} else {
    puts "PS_CFG FCLK0 freq = $f0 MHz (expect <fclk_mhz>)"
}

# ---- 3) cells --------------------------------------------------------
puts "EES_VIVADO_STAGE CELLS"
if {[llength [get_bd_cells -quiet axi_ic0]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic0
}
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_ic0]

if {[llength [get_bd_cells -quiet <inst_name>]] == 0} {
    # top MUST be plain Verilog-2001 (.v); SV deps follow via compile order
    create_bd_cell -type module -reference <top_module> <inst_name>
}

if {[llength [get_bd_cells -quiet rst_sys]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_sys
    # C_EXT_RESET_HIGH is READ-ONLY: polarity auto-propagates from the
    # connected source (FCLK_RESET0_N is active low -> resolves to 0).
    # Do NOT set it manually (BD 41-737). Verify later in the cell XCI.
}
if {[llength [get_bd_cells -quiet vcc_rst]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 vcc_rst
    set_property CONFIG.CONST_VAL {1} [get_bd_cells vcc_rst]
}

# ---- 4) wiring (guarded) ---------------------------------------------
puts "EES_VIVADO_STAGE WIRING"
# clocks: interconnect needs ACLK + S00_ACLK + M00_ACLK (BD 41-758)
if {[llength [net_on axi_ic0/S00_ACLK]] == 0} {
    connect_bd_net [get_bd_pins $ps/FCLK_CLK0] \
        [get_bd_pins axi_ic0/ACLK] [get_bd_pins axi_ic0/S00_ACLK] \
        [get_bd_pins axi_ic0/M00_ACLK] \
        [get_bd_pins <inst_name>/s_axi_aclk] \
        [get_bd_pins $ps/M_AXI_GP0_ACLK]
}
if {[llength [net_on rst_sys/slowest_sync_clk]] == 0} {
    connect_bd_net [get_bd_pins $ps/FCLK_CLK0] [get_bd_pins rst_sys/slowest_sync_clk]
}
# resets: strip ANY existing direct reset wiring first (async-release
# CRITICAL BD 41-1348), then route through proc_sys_reset
foreach pin {axi_ic0/ARESETN axi_ic0/S00_ARESETN axi_ic0/M00_ARESETN \
             <inst_name>/s_axi_aresetn} {
    set n [net_on $pin]
    if {[llength $n] != 0} { delete_bd_objs $n; puts "WIRING removed old reset net on $pin" }
}
if {[llength [net_on rst_sys/ext_reset_in]] == 0} {
    connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins rst_sys/ext_reset_in]
}
if {[llength [net_on axi_ic0/ARESETN]] == 0} {
    connect_bd_net [get_bd_pins rst_sys/peripheral_aresetn] \
        [get_bd_pins axi_ic0/ARESETN] [get_bd_pins axi_ic0/S00_ARESETN] \
        [get_bd_pins axi_ic0/M00_ARESETN] \
        [get_bd_pins <inst_name>/s_axi_aresetn]
}
# dcm_locked MUST be tied 1: undriven -> synth 0 -> PERMANENT RESET
if {[llength [net_on rst_sys/dcm_locked]] == 0} {
    connect_bd_net [get_bd_pins vcc_rst/dout] [get_bd_pins rst_sys/dcm_locked]
}
# AXI interfaces
if {[llength [inet_on axi_ic0/S00_AXI]] == 0} {
    connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] \
        [get_bd_intf_pins axi_ic0/S00_AXI]
}
if {[llength [inet_on axi_ic0/M00_AXI]] == 0} {
    connect_bd_intf_net [get_bd_intf_pins axi_ic0/M00_AXI] \
        [get_bd_intf_pins <inst_name>/s_axi]
}

# ---- 5) address map ---------------------------------------------------
puts "EES_VIVADO_STAGE ADDRESS"
assign_bd_address
puts "ADDRESS inferred segs: [get_bd_addr_segs -of_objects [get_bd_cells <inst_name>]]"
# offset/range are READ-ONLY on the slave-side seg: set them on the
# master-side mirrored segment under processing_system7_0/Data
set_property range  <seg_range> \
    [get_bd_addr_segs processing_system7_0/Data/SEG_<inst_name>_reg0]
set_property offset <base_addr> \
    [get_bd_addr_segs processing_system7_0/Data/SEG_<inst_name>_reg0]
puts "ADDRESS offset now: [get_property OFFSET \
    [get_bd_addr_segs processing_system7_0/Data/SEG_<inst_name>_reg0]]"

# ---- 6) validate + save ------------------------------------------------
puts "EES_VIVADO_STAGE VALIDATE"
validate_bd_design

save_bd_design
set_property top <bd_name>_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

close_project
puts "EES_VIVADO_STAGE BD_DONE"
puts "EES_VIVADO_RESULT PASS"
