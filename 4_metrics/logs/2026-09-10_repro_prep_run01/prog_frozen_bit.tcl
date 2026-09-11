# prog_frozen_bit.tcl — Program the frozen C1.2 bitstream onto EES-331 via Vivado HW Manager
#
# Usage (Git Bash / cmd):
#   E:/WorkApps/Xilinx/Vivado_2025_2/2025.2/Vivado/bin/vivado.bat -mode tcl \
#     -source prog_frozen_bit.tcl -tclargs <absolute/path/to/display_test_wrapper.bit>
#
# Expected target: xc7z020 (EES-331), JTAG via on-board/external programmer.
# Exit codes: 0 = PROGRAM_DONE, 1 = usage/file error, 2 = JTAG/device error.

if {$argc < 1} {
    puts "ERROR: usage: vivado -mode tcl -source prog_frozen_bit.tcl -tclargs <bitfile>"
    exit 1
}
set bitfile [lindex $argv 0]
if {![file exists $bitfile]} {
    puts "ERROR: bitfile not found: $bitfile"
    exit 1
}
puts "INFO: programming [file normalize $bitfile]"

open_hw_manager
connect_hw_server -allow_non_jtag
if {[catch {open_hw_target} msg]} {
    puts "ERROR: cannot open hw target: $msg"
    exit 2
}
set devs [get_hw_devices xc7z020*]
if {[llength $devs] == 0} {
    puts "ERROR: no xc7z020 device visible on JTAG. Check programmer/cable/power."
    exit 2
}
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE [file normalize $bitfile] $dev
program_hw_devices $dev
puts "PROGRAM_DONE [file tail $bitfile]"

close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
