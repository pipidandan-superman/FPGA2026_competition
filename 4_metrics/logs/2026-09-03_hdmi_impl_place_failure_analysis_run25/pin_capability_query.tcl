create_project -in_memory -part xc7z020clg484-1
link_design -part xc7z020clg484-1
foreach pin {M19 AA22 Y8} {
    puts "=== PIN $pin ==="
    set obj [get_package_pins -quiet $pin]
    if {[llength $obj] == 0} { puts "NOT_FOUND"; continue }
    puts "BANK=[get_property BANK $obj]"
    puts "PIN_FUNC=[get_property PIN_FUNC $obj]"
}
puts "=== MRCC PINS RELEVANT BANKS ==="
foreach bank {33 34 13} {
    set pins [get_package_pins -quiet -filter "PIN_FUNC =~ *MRCC* && BANK == $bank"]
    puts "BANK $bank: [join [lsort $pins] {, }]"
}
exit
