#!/bin/bash
# Fixes DaVinci Resolve (Flatpak) leaving a stale qtsingleapp lockfile in /tmp
# after a crash, which prevents it from restarting until the lockfile is removed.
# Creates a user-tmpfiles rule to clean it up on login via systemd-tmpfiles.

set -euo pipefail

TMPFILES_DIR="$HOME/.config/user-tmpfiles.d"
TMPFILES_CONF="$TMPFILES_DIR/resolve.conf"

mkdir -p "$TMPFILES_DIR"
echo 'r /tmp/qtsingleapp-DaVinc-*-lockfile - - - -' > "$TMPFILES_CONF"
echo "  Tmpfiles rule written to $TMPFILES_CONF."

systemctl --user enable systemd-tmpfiles-clean.timer
echo "  Enabled systemd-tmpfiles-clean.timer."
