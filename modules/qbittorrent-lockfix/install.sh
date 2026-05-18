#!/bin/bash
# Fixes qBittorrent (Flatpak) leaving a stale lockfile after a crash,
# which prevents it from restarting until the lockfile is manually removed.
# Creates a user-tmpfiles rule to clean it up on login via systemd-tmpfiles.

set -euo pipefail

TMPFILES_DIR="$HOME/.config/user-tmpfiles.d"
TMPFILES_CONF="$TMPFILES_DIR/qbittorrent.conf"

mkdir -p "$TMPFILES_DIR"
echo 'r %h/.var/app/org.qbittorrent.qBittorrent/config/qBittorrent/lockfile - - - -' > "$TMPFILES_CONF"
echo "  Tmpfiles rule written to $TMPFILES_CONF."

systemctl --user enable systemd-tmpfiles-clean.timer
echo "  Enabled systemd-tmpfiles-clean.timer."
