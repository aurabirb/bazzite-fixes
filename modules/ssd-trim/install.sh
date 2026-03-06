#!/bin/bash
# Enables TRIM on non-rotational USB/SATA SSDs via udev.
# fstrim.timer (enabled by default) already covers all mounts including
# /run/media/, so no override needed there.
# NVMe drives expose TRIM natively and are unaffected.

set -euo pipefail

MODULE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

cp "$MODULE_DIR/files/etc/udev/rules.d/60-ssd-trim.rules" \
   /etc/udev/rules.d/60-ssd-trim.rules

udevadm control --reload-rules
udevadm trigger --subsystem-match=scsi_disk

echo "  SSD TRIM udev rule installed. Any connected non-rotational drives will be re-probed."
echo "  fstrim.timer is already enabled and covers all mounts including /run/media/."
