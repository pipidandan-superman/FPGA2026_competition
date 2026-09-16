# ============================================================
# Path detail probe on ooc_v25_routed.dcp -- iteration 12 design
# input (sum_r -> DSP PCIN, -0.079)
# ============================================================
open_checkpoint E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_v25_routed.dcp
report_timing -delay_type max -max_paths 3 \
    -from [get_cells u_array/u_requant/sum_r_reg[*]] \
    -to   [get_pins  u_array/u_requant/prod_c_w__2/PCIN[*]] \
    -input_pins -significant_digits 3 \
    -file E:/competition/2_fpga/3_yolo_zynq/proj/ooc_gate/ooc_v25_pathdetail.rpt
puts "PATHDETAIL_DONE"
