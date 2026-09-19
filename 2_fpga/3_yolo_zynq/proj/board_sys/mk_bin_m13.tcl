set OUT E:/competition/2_fpga/3_yolo_zynq/proj/board_sys
write_cfgmem -format BIN -interface SMAPx32 -size 16 -loadbit "up 0x0 $OUT/yolo_a2_board/yolo_a2_board.runs/impl_1/yolo_sys_wrapper.bit" -file $OUT/yolo_a2.bin -force
