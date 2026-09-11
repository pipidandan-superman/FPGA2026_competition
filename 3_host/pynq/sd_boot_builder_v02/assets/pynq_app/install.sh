#!/bin/bash
# Install into the PYNQ SD root filesystem. Preserve every replaced config.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo'; exit 1; }
SOURCE=$(cd -- "$(dirname -- "$0")" && pwd)
DEST=/home/xilinx/ees331_camera
PYTHON=/usr/local/share/pynq-venv/bin/python3
[[ -x "$PYTHON" ]] || { echo 'PYNQ virtual environment not found'; exit 1; }
grep -aq 'EES-331' /proc/device-tree/model || { echo 'This installer is for EES-331 only'; exit 1; }
mountpoint -q /boot || { echo '/boot must be the SD boot partition'; exit 1; }
for name in camera.py run_camera.sh overlay.bit overlay.hwh uEnv.txt ees331_camera.network ees331-camera.service; do
    [[ -f "$SOURCE/$name" ]] || { echo "Missing $name"; exit 1; }
done
mkdir -p "$DEST"
BACKUP="$DEST/backup/$(date +%Y%m%d_%H%M%S)_$$"
mkdir -p "$BACKUP"
for path in /boot/uEnv.txt /etc/network/interfaces.d/ees331_camera /etc/systemd/system/ees331-camera.service; do
    if [[ -f "$path" ]]; then
        cp -a "$path" "$BACKUP/$(basename "$path")"
    fi
done
if [[ "$SOURCE" != "$DEST" ]]; then
    for name in camera.py run_camera.sh overlay.bit overlay.hwh; do
        [[ ! -f "$DEST/$name" ]] || cp -a "$DEST/$name" "$BACKUP/"
        install -m 644 "$SOURCE/$name" "$DEST/$name"
    done
fi
install -m 644 "$SOURCE/uEnv.txt" /boot/uEnv.txt
install -m 644 "$SOURCE/ees331_camera.network" /etc/network/interfaces.d/ees331_camera
install -m 644 "$SOURCE/ees331-camera.service" /etc/systemd/system/ees331-camera.service
systemctl daemon-reload
systemctl enable ees331-camera.service
sync
echo "INSTALLED; backups=$BACKUP"
echo 'Reboot from SD, then check: systemctl status ees331-camera'
