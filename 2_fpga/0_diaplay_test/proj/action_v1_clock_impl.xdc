# Implementation-only: these objects exist after all OOC IP is linked.
# M19 board reference enters the PLL through the clock wizard's IBUF.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ *clk_wiz_0/inst/clk_in1_display_test_clk_wiz_0_0}]
set_property COMPENSATION BUF_IN [get_cells -hierarchical -filter {REF_NAME == PLLE2_ADV && NAME =~ *clk_wiz_0*}]
# Existing EES-331 camera PCLK on AA22 uses the proven non-CCIO path.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_0_IBUF]
