#!/bin/bash
set -euo pipefail
export XILINX_XRT=/usr
APP_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
exec /usr/local/share/pynq-venv/bin/python3 -u "$APP_DIR/camera_action_v1.py" \
    --bit "$APP_DIR/display_test_axi_action_uart.bit" \
    --manifest "$APP_DIR/release_manifest.json" "$@"
