# yolo_sys fabric clock: PS7 IP auto-generates the FCLK0 clock constraint
# from PCW preset (FCLK0=60MHz). Do NOT add a manual create_clock here --
# run8's create_clock on ps7/FCLK_CLK0 pin triggered [Constraints 18-1056]
# "completely overrides" the PS7 auto clock (numerically equal, but noise).
# All PL logic is on this single 60MHz domain; HP0/HP1/GP0 interfaces all
# CONFIG.FREQ_HZ=60000000 + CLK_DOMAIN=yolo_sys_ps7_0_FCLK_CLK0.
