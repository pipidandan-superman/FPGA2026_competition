# ============================================================
# M13 board build -- yolo_sys block design (A2 loader V2)
# EES-331 XC7Z020clg484, Vivado 2025.2 batch
#   PS7 (EES-331 preset, extracted from display_test.bd) with
#   FCLK0=60MHz (first-light; OOC v28b60 gate), GP0 (CSR @0x43C1_0000) + HP0 (W read + Y write:
#   engine_top m_axi 是 BD 合并推断的单 AXI4 主，读写双通道并发，
#   DDR 控制器内仲裁) + HP1 (X read, A2 loader V2 专用);
#   engine_top V1.1 PROD-16x16。No PL external pins (all traffic
#   via PS DDR); no IRQ in v1 (PS polls STATUS).
# gate : BOARD_BITSTREAM_PASS (timing WNS >= 0) + yolo_a2.xsa
# batch: vivado -mode batch -source build_board.tcl -nojournal
# ============================================================
set ROOT E:/competition/2_fpga/3_yolo_zynq
set RTL $ROOT/rtl
set IPD $ROOT/ip
set OUT $ROOT/proj/board_sys

source $OUT/ps7_ees331.tcl   ;# -> $ps7_cfg (533 props + A2 overrides)

create_project -force yolo_a2_board $OUT/yolo_a2_board -part xc7z020clg484-1

# RTL closure (engine PROD default = 16x16) + both BMG IPs
add_files -norecurse [list \
    $RTL/yolo_engine_top.v $RTL/yolo_gemm_array.v $RTL/yolo_csr.v \
    $RTL/yolo_ctrl.v $RTL/yolo_dma.v $RTL/yolo_dma_wr.v \
    $RTL/yolo_wbuf.v $RTL/yolo_xbuf.v $RTL/yolo_xrowgen.v \
    $RTL/yolo_pe_pack.v $RTL/yolo_acc.v $RTL/yolo_requant.v \
    $RTL/yolo_silu_lut.v \
    $IPD/yolo_wbuf_bmg/yolo_wbuf_bmg.xci \
    $IPD/yolo_xbuf_bmg/yolo_xbuf_bmg.xci]
add_files -fileset constrs_1 -norecurse $OUT/yolo_sys.xdc

# ---------------- block design ----------------
create_bd_design yolo_sys

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
# 逐对 set_property：PCW_MIO_TREE_* 值带 [' ... '] 方括号，
# set_property -dict $ps7_cfg 会被二次求值（invalid command name
# "'SD"，首跑实拦）；单属性单层替换无此坑。
# 两遍次序：BANK 电压必须先于 MIOxx_IOTYPE 设置（二跑实拦：
# MIO16 LVCMOS 1.8V 校验时 bank1 电压未生效 → out of range）。
foreach {pk pv} $ps7_cfg {
    if {[string match {CONFIG.PCW_PRESET_BANK?_VOLTAGE} $pk]} {
        set_property $pk $pv [get_bd_cells ps7]
    }
}
foreach {pk pv} $ps7_cfg {
    if {![string match {CONFIG.PCW_PRESET_BANK?_VOLTAGE} $pk]} {
        set_property $pk $pv [get_bd_cells ps7]
    }
}

create_bd_cell -type module -reference yolo_engine_top engine
# module_ref 推断的 AXI 接口默认 FREQ_HZ=100MHz 且无时钟关联
# （六跑 validate 实拦 BD 41-237 FREQ_HZ 不匹配 + BD 41-967 未关联
#  时钟）→ 在自动化之前显式 60MHz + 时钟关联（冒号分隔列表）
set_property CONFIG.FREQ_HZ 60000000 [get_bd_intf_pins engine/s_axi]
set_property CONFIG.FREQ_HZ 60000000 [get_bd_intf_pins engine/m_axi]
set_property CONFIG.FREQ_HZ 60000000 [get_bd_intf_pins engine/x_m_axi]
set_property CONFIG.ASSOCIATED_BUSIF {s_axi:m_axi:x_m_axi} [get_bd_pins engine/clk_i]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_150
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 lock_1
set_property -dict {CONST_VAL {1} CONST_WIDTH {1}} [get_bd_cells lock_1]

# clocks + reset (dcm_locked MUST be tied high: unconnected = 0 keeps
# peripheral_aresetn asserted forever)
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins engine/clk_i]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_150/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_150/ext_reset_in]
connect_bd_net [get_bd_pins lock_1/dout] [get_bd_pins rst_150/dcm_locked]
connect_bd_net [get_bd_pins rst_150/peripheral_aresetn] [get_bd_pins engine/rst_n]

# AXI: GP0 -> CSR (automation inserts Lite conv + clock conv)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { Master "/ps7/M_AXI_GP0" Clk "/ps7/FCLK_CLK0" } \
    [get_bd_intf_pins engine/s_axi]

# AXI: engine m_axi (BD 合并推断: W 读 + Y 写双通道) -> HP0
# （规则方向与 GP0 段同构：config Master=引擎主，目标引针=HP 从；
#  四跑实拦：config Slave+引脚=m_axi 时规则反查从侧报
#  "No valid slave interface could be found"）
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { Master "/engine/m_axi" Clk "/ps7/FCLK_CLK0" } \
    [get_bd_intf_pins ps7/S_AXI_HP0]
# AXI: engine x_m_axi (X 行段流式读, A2) -> HP1
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { Master "/engine/x_m_axi" Clk "/ps7/FCLK_CLK0" } \
    [get_bd_intf_pins ps7/S_AXI_HP1]

# CSR at the address-map contract slot 0x43C1_0000/64K
# （五跑实拦：已分配段 OFFSET 是只读属性 [Common 17-107]；
#  GP0 自动化默认把 reg0 挂到 0x4000_0000/1G，段名 reg0 非 CTRL
#  → 删自动映射后重指）
delete_bd_objs [get_bd_addr_segs engine/s_axi/reg0]
assign_bd_address -offset 0x43C10000 -range 0x10000 \
    [get_bd_addr_segs engine/s_axi/reg0]

validate_bd_design
save_bd_design

# ---------------- top + bitstream ----------------
make_wrapper -files [get_files yolo_sys.bd] -top -import
set_property top yolo_sys_wrapper [current_fileset]

# （七跑实拦 [Vivado 12-1015]：-to_step write_bitstream 对 synth_1
#  非法（其唯一合法步是 synth_design）→ 两段式）
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# archive: XSA (contains .hwh for overlay tooling; runtime itself uses
# fixed 0x43C1_0000 via /dev/mem, no .hwh dependency)
write_hw_platform -fixed -include_bit -force $OUT/yolo_a2.xsa

open_run impl_1
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts "BOARD_TIMING wns_ns=$wns"
if {$wns >= 0} {
    puts "BOARD_BITSTREAM_PASS wns_ns=$wns xsa=$OUT/yolo_a2.xsa"
} else {
    puts "BOARD_BITSTREAM_FAIL wns_ns=$wns"
}
