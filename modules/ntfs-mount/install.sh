#!/bin/bash
# Allows wheel group users to mount/unmount drives without a password prompt.
# Disables SteamOS automount so GNOME/udisks2 handles NTFS drives instead
# (SteamOS automount does not handle NTFS correctly).
# Installs a user systemd service that auto-mounts NTFS drives at login.

set -euo pipefail

MODULE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Resolve the real user when run via sudo
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# --- System-level files (root) ---

cp "$MODULE_DIR/files/etc/polkit-1/rules.d/10-wheel-mount.rules" \
   /etc/polkit-1/rules.d/10-wheel-mount.rules
cp "$MODULE_DIR/files/etc/polkit-1/rules.d/11-ntfs-mount.rules" \
   /etc/polkit-1/rules.d/11-ntfs-mount.rules
systemctl reload polkit 2>/dev/null || pkill -HUP polkit 2>/dev/null || true
echo "  Polkit rules installed."

# Disable SteamOS automount so udisks2/GNOME handles NTFS drives
# Equivalent to: ln -sf /dev/null /etc/udev/rules.d/99-steamos-automount.rules && udevadm control --reload-rules
# Reverse with:  ujust enable-steamos-automount
ujust disable-steamos-automount
echo "  SteamOS automount disabled (udisks2 will handle NTFS drives)."

# --- System-level script (fixed path required for polkit rule) ---

install -Dm755 "$MODULE_DIR/files/usr/local/bin/ntfs-mount.sh" \
    /usr/local/bin/ntfs-mount.sh

# --- User-level service ---

install -Dm644 "$MODULE_DIR/files/home/.config/systemd/user/ntfs-mount.service" \
    "$TARGET_HOME/.config/systemd/user/ntfs-mount.service"

chown "$TARGET_USER:$TARGET_USER" \
    "$TARGET_HOME/.config/systemd/user/ntfs-mount.service"

sudo -u "$TARGET_USER" systemctl --user daemon-reload
sudo -u "$TARGET_USER" systemctl --user enable ntfs-mount.service
echo "  ntfs-mount user service installed and enabled for $TARGET_USER."
