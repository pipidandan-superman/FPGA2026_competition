#!/bin/sh
# run_l3.sh - board-side launcher for board_l3_doorbell.py (root, after r2 load).
exec /usr/local/share/pynq-venv/bin/python3 /home/xilinx/csr_board_run02/board_l3_doorbell.py l3r1
