# enable_enet0_export_xsa.tcl — FALLBACK PATH B (REQUIRES EXPLICIT USER AUTHORIZATION)
#
# ⚠ frozen-2_fpga boundary: this script opens the frozen Vivado project and
#   regenerates BD output products / exports XSA. Per AGENTS.md and
#   .codex/skills/project-workspace-policy, this exact action must be
#   explicitly requested by the user in the current instruction before running.
#   Preferred path is still obtaining the teammate's frozen BIT+XSA
#   (7cb11f7d... / 30644b31...), see REPRO_STATUS.md §3.
#
# What it does (matches 2026-09-08 integration record §1/§8 and
# 2_fpga/0_diaplay_test/doc/ethernet_bringup_checklist.md §1):
#   1. open the frozen display_test project
#   2. enable ENET0: RGMII MIO 16..27, MDIO MIO 52..53, 1000 Mbps, reset MIO 47
#   3. validate BD, generate output products
#   4. export XSA (with bit) into the 2026-09-10 run directory
#   5. (optional, RUN_BITSTREAM=1) launch synthesis/implementation/bitstream
#
# Usage:
#   vivado.bat -mode batch -source enable_enet0_export_xsa.tcl
#   env RUN_BITSTREAM=1 for full bit build (long)
#
# NOTE: teammates' PCW diff (§8 of the integration report) also touched
#   GPIO-EMIO/MIO keys beyond ENET0; this script reproduces the ENET0
#   essentials only. Resulting artifacts will NOT be hash-identical to the
#   frozen pair and must be validated as a NEW run (never claimed equal to
#   7cb11f7d...).

set run_dir "E:/Work/Projects/AMD_proj/FPGA_competition_2026/4_metrics/logs/2026-09-10_repro_prep_run01"
set xpr "E:/Work/Projects/AMD_proj/FPGA_competition_2026/2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr"

open_project $xpr
open_bd_design [get_files -of_objects [get_filesets sources_1] "*display_test.bd"]

set ps [get_bd_cells -hierarchical -filter {VLNV =~ "*processing_system7*"}]
if {[llength $ps] != 1} { puts "ERROR: PS7 cell not unique: $ps"; exit 1 }
set ps [lindex $ps 0]

set_property -dict [list \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
    CONFIG.PCW_ENET0_RESET_IO {MIO 47} \
    CONFIG.PCW_ENET0_ENET0_TYPE {RGMII} \
    CONFIG.PCW_ENET0_SPEED {1000} \
] $ps

validate_bd_design
generate_target all [get_files "*display_test.bd"]

set xsa_out $run_dir/display_test_wrapper_enet0_rebuild.xsa
write_hw_platform -force -include_bit $xsa_out
puts "XSA_EXPORTED $xsa_out"

if {[info exists ::env(RUN_BITSTREAM)] && $::env(RUN_BITSTREAM) == 1} {
    reset_run synth_1
    reset_run impl_1
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
    puts "BITSTREAM_RUN_DONE"
}
exit 0
