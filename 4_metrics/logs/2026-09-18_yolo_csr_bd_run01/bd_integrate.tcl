# =====================================================================
# bd_integrate.tcl - integrate yolo_control_subsystem (V2001 module
# reference) into display_test BD @ 0x43C1_0000/64KB.
# PS7: M_AXI_GP0 + FCLK0 100MHz + FCLK_RESET0_N.
# Reset: proc_sys_reset (FCLK_RESET0_N active-low ext_reset_in,
# dcm_locked tied 1) -> synchronous peripheral_aresetn release.
# Run by run_vivado_batch_ees.ps1 (vivado -mode batch). Idempotent:
# every step guards on existing objects so a rerun converges.
# =====================================================================

set projdir {E:/competition/2_fpga/3_yolo_zynq/proj/axi_test}
set rtl     {E:/competition/2_fpga/3_yolo_zynq/rtl/ps_axi_pl}

proc net_on {pin} {
    return [get_bd_nets -quiet -of [get_bd_pins $pin]]
}
proc inet_on {pin} {
    return [get_bd_intf_nets -quiet -of [get_bd_intf_pins $pin]]
}

puts "EES_VIVADO_STAGE BD_OPEN"
open_project $projdir/axi_test.xpr

# ---------------------------------------------------------------------
# 1) add RTL + BMG XCIs to sources_1 (only if absent)
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE SRC_ADD"
foreach f {yolo_csr_pkg.sv yolo_axi_lite_slave.sv yolo_reg_file.sv \
           yolo_desc_walker.sv yolo_result_ring.sv \
           yolo_desc_table.sv yolo_buf_table.sv yolo_quant_table.sv \
           yolo_lut_table.sv yolo_ring_table.sv \
           yolo_control_subsystem.v} {
    if {[llength [get_files -quiet -of [get_filesets sources_1] [file tail $f]]] == 0} {
        add_files -fileset sources_1 [file join $rtl $f]
        puts "SRC_ADD added  $f"
    } else {
        puts "SRC_ADD present $f"
    }
}
foreach ip {yolo_desc_bram yolo_buf_bram yolo_quant_bram \
            yolo_lut_bram yolo_ring_bram} {
    if {[llength [get_files -quiet ${ip}.xci]] == 0} {
        add_files -fileset sources_1 [file join $rtl ip $ip $ip.xci]
        puts "SRC_ADD added  $ip.xci"
    } else {
        puts "SRC_ADD present $ip.xci"
    }
}
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------
# 2) PS7: enable GP0 master + FCLK0 + FCLK_RESET0_N
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE PS_CFG"
open_bd_design [get_files display_test.bd]
set ps [get_bd_cells processing_system7_0]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
] $ps
# FCLK0 frequency is a dynamic param; PS7 default is 100 MHz (target)
if {[catch {set f0 [get_property CONFIG.PCW_FCLK0_PERIPHERAL_FREQMHZ $ps]} emsg]} {
    puts "PS_CFG FCLK0 freq param absent (PS7 default 100 MHz assumed)"
} else {
    puts "PS_CFG FCLK0 freq = $f0 MHz"
}

# ---------------------------------------------------------------------
# 3) cells: interconnect 1S1M, module reference, proc_sys_reset, vcc
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE CELLS"
if {[llength [get_bd_cells -quiet axi_ic0]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic0
}
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] \
    [get_bd_cells axi_ic0]

if {[llength [get_bd_cells -quiet u_yolo_csr]] == 0} {
    create_bd_cell -type module -reference yolo_control_subsystem u_yolo_csr
}

if {[llength [get_bd_cells -quiet rst_sys]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_sys
    # FCLK_RESET0_N is active low
    set_property CONFIG.C_EXT_RESET_HIGH {0} [get_bd_cells rst_sys]
}
if {[llength [get_bd_cells -quiet vcc_rst]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 vcc_rst
    set_property CONFIG.CONST_VAL {1} [get_bd_cells vcc_rst]
}

# ---------------------------------------------------------------------
# 4) wiring (all connections guarded -> idempotent rerun)
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE WIRING"
# clocks
if {[llength [net_on axi_ic0/S00_ACLK]] == 0} {
    connect_bd_net [get_bd_pins $ps/FCLK_CLK0] \
        [get_bd_pins axi_ic0/ACLK] \
        [get_bd_pins axi_ic0/S00_ACLK] \
        [get_bd_pins axi_ic0/M00_ACLK] \
        [get_bd_pins u_yolo_csr/s_axi_aclk] \
        [get_bd_pins $ps/M_AXI_GP0_ACLK]
}
if {[llength [net_on rst_sys/slowest_sync_clk]] == 0} {
    connect_bd_net [get_bd_pins $ps/FCLK_CLK0] \
        [get_bd_pins rst_sys/slowest_sync_clk]
}

# reset: strip any direct FCLK_RESET0_N wiring (from an earlier pass),
# then route through proc_sys_reset for a synchronous release
foreach pin {axi_ic0/ARESETN axi_ic0/S00_ARESETN axi_ic0/M00_ARESETN \
             u_yolo_csr/s_axi_aresetn} {
    set n [net_on $pin]
    if {[llength $n] != 0} {
        delete_bd_objs $n
        puts "WIRING removed old reset net on $pin"
    }
}
if {[llength [net_on rst_sys/ext_reset_in]] == 0} {
    connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] \
        [get_bd_pins rst_sys/ext_reset_in]
}
if {[llength [net_on axi_ic0/ARESETN]] == 0} {
    connect_bd_net [get_bd_pins rst_sys/peripheral_aresetn] \
        [get_bd_pins axi_ic0/ARESETN] \
        [get_bd_pins axi_ic0/S00_ARESETN] \
        [get_bd_pins axi_ic0/M00_ARESETN] \
        [get_bd_pins u_yolo_csr/s_axi_aresetn]
}
# dcm_locked MUST be driven 1 (undriven -> synth 0 -> permanent reset)
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
        [get_bd_intf_pins u_yolo_csr/s_axi]
}

# ---------------------------------------------------------------------
# 5) address map: u_yolo_csr @ 0x43C1_0000, 64 KB
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE ADDRESS"
assign_bd_address
set segs [get_bd_addr_segs -of_objects [get_bd_cells u_yolo_csr]]
puts "ADDRESS inferred segs: $segs"
# offset/range are read-only on the slave-side seg; set them on the
# master-side mirrored segment under processing_system7_0/Data
set_property range  64K        [get_bd_addr_segs processing_system7_0/Data/SEG_u_yolo_csr_reg0]
set_property offset 0x43C10000 [get_bd_addr_segs processing_system7_0/Data/SEG_u_yolo_csr_reg0]
puts "ADDRESS offset now: [get_property OFFSET [get_bd_addr_segs processing_system7_0/Data/SEG_u_yolo_csr_reg0]]"

# ---------------------------------------------------------------------
# 6) validate + save
# ---------------------------------------------------------------------
puts "EES_VIVADO_STAGE VALIDATE"
validate_bd_design

save_bd_design
set_property top display_test_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# irq_o is intentionally left unconnected for this bring-up (Level 5
# board check comes later)

close_project
puts "EES_VIVADO_STAGE BD_DONE"
puts "EES_VIVADO_RESULT PASS"
