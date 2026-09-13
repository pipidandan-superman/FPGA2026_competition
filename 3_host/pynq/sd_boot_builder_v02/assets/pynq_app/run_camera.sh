#!/bin/bash
set -euo pipefail
export XILINX_XRT=/usr
APP_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
exec /usr/local/share/pynq-venv/bin/python3 -u "$APP_DIR/camera.py" "$@"
