#!/bin/bash
# Fixes NVIDIA suspend/resume on GNOME + Bazzite.
#
# Problem: suspend freezes for ~90s then fails, and wake-up is unreliable.
# Cause:   systemd tries to freeze the user session during suspend, but
#          GNOME holds the NVIDIA driver, causing a deadlock/timeout.
#
# Fix:
#   1. Disable user session freezing during suspend (nvidia-override.conf)
#   2. SIGSTOP gnome-shell before suspend so it releases the GPU, SIGCONT after
#   3. Wire the above into the suspend/hibernate cycle via systemd services
#
# Note: NVreg_PreserveVideoMemoryAllocations=1 and NVreg_EnableS0ixPowerManagement=1
# are normally set by Bazzite's NVIDIA package (/usr/lib/modprobe.d/). This script
# checks for them and writes /etc/modprobe.d/nvidia-suspend.conf as a fallback.

set -euo pipefail

MODULE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

install -Dm755 "$MODULE_DIR/files/usr/local/bin/suspend-gnome-shell.sh" \
    /usr/local/bin/suspend-gnome-shell.sh

install -Dm644 "$MODULE_DIR/files/etc/systemd/system/systemd-suspend.service.d/nvidia-override.conf" \
    /etc/systemd/system/systemd-suspend.service.d/nvidia-override.conf

install -Dm644 "$MODULE_DIR/files/etc/systemd/system/gnome-shell-suspend.service" \
    /etc/systemd/system/gnome-shell-suspend.service

install -Dm644 "$MODULE_DIR/files/etc/systemd/system/gnome-shell-resume.service" \
    /etc/systemd/system/gnome-shell-resume.service

# --- NVIDIA modprobe options (required for reliable suspend/resume) ---
# Normally provided by Bazzite's NVIDIA package; written to /etc as fallback.

MODPROBE_CONF=/etc/modprobe.d/nvidia-suspend.conf
MODPROBE_OPTIONS=(
    "options nvidia NVreg_PreserveVideoMemoryAllocations=1"
    "options nvidia NVreg_EnableS0ixPowerManagement=1"
    "options nvidia NVreg_TemporaryFilePath=/var/tmp"
)

for opt in "${MODPROBE_OPTIONS[@]}"; do
    key="${opt%=*}"
    if ! grep -rq "^${key}=" /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null; then
        echo "$opt" >> "$MODPROBE_CONF"
        echo "  Added modprobe option: $opt"
    fi
done

# --- Reload and enable ---

systemctl daemon-reload
systemctl enable gnome-shell-suspend.service gnome-shell-resume.service

echo "  NVIDIA suspend fix installed."
echo "  nvidia-suspend/resume/hibernate services are managed by Bazzite's NVIDIA package."
