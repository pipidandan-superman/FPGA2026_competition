set evidence E:/competition/4_metrics/logs/2026-09-06_hdmi_ila_no_display_run01
set bit_file E:/competition/2_fpga/1_zynqtest_2025/project_1/project_1.runs/impl_1/hdmi_colorbar_vtc_top.bit
set probes_file E:/competition/2_fpga/1_zynqtest_2025/project_1/project_1.runs/impl_1/debug_nets.ltx

open_hw_manager
connect_hw_server -allow_non_jtag
set targets [get_hw_targets]
puts "TARGETS=$targets"
if {[llength $targets] < 1} {error "No JTAG target found"}
set target [lindex $targets 0]
open_hw_target $target
set devices [get_hw_devices xc7z020*]
puts "DEVICES=$devices"
if {[llength $devices] != 1} {error "Expected one XC7Z020 device"}
set device [lindex $devices 0]
current_hw_device $device
set_property PROGRAM.FILE $bit_file $device
set_property PROBES.FILE $probes_file $device
set_property FULL_PROBES.FILE $probes_file $device
refresh_hw_device $device

set analyzers [get_hw_ilas -of_objects $device]
puts "ANALYZERS=$analyzers"
if {[llength $analyzers] != 1} {error "Expected one ILA"}
set analyzer [lindex $analyzers 0]
set probes [get_hw_probes -of_objects $analyzer]
puts "PROBES=$probes"
set start_probe [get_hw_probes -of_objects $analyzer -filter {NAME =~ */iic_start}]
if {[llength $start_probe] != 1} {error "Expected one iic_start probe"}
set_property TRIGGER_COMPARE_VALUE eq1'b1 $start_probe
set_property CONTROL.TRIGGER_POSITION 0 $analyzer
run_hw_ila $analyzer
if {[catch {wait_on_hw_ila -timeout 10 $analyzer} capture_error]} {
    puts "START_TRIGGER_TIMEOUT=$capture_error"
    set_property TRIGGER_COMPARE_VALUE eq1'b1 $start_probe
    run_hw_ila -trigger_now $analyzer
    wait_on_hw_ila -timeout 10 $analyzer
}
set samples [upload_hw_ila_data $analyzer]
write_hw_ila_data -force -csv_file $evidence/ila_capture.csv $samples
puts "CAPTURE_FILE=$evidence/ila_capture.csv"
close_hw_target
close_hw_manager
exit
