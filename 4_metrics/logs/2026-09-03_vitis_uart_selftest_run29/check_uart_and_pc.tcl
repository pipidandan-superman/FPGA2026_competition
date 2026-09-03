connect
targets 2
stop
puts \"PC_BEGIN\"
rrd pc
puts \"PC_END\"
puts \"UART_REGS_BEGIN\"
mrd 0xE0001000 4
puts \"UART_REGS_END\"
con
disconnect
exit
