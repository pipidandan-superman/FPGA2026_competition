# ============================================================
# Path detail probe on ooc_v26_routed.dcp -- iteration 13 design
# input (oc_g_d1_r -> row_addr DSP PCIN, -0.031) + next families
# ============================================================
open_checkpoint E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_v26_routed.dcp
report_timing -delay_type max -max_paths 2 \
    -from [get_cells u_array/oc_g_d1_r_reg[*]] \
    -to   [get_pins  u_array/row_addr_d2_r0/PCIN[*]] \
    -input_pins -significant_digits 3 \
    -file E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_v26_rowaddr_path.rpt
# what is behind this family: next 25 paths
report_timing -delay_type max -max_paths 25 -path_type summary \
    -file E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_v26_top25.rpt
puts "PROBE_DONE"
