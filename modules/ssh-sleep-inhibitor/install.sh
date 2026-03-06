#!/bin/bash
# Installs a logind sleep inhibitor that activates while SSH sessions are open.
# This blocks automatic/idle sleep without blocking explicit suspend.

set -euo pipefail

MODULE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# --- Copy files ---
cp "$MODULE_DIR/files/etc/pam_session.sh" /etc/pam_session.sh
chmod 755 /etc/pam_session.sh

cp "$MODULE_DIR/files/etc/systemd/system/ssh-sleep-inhibitor.service" \
   /etc/systemd/system/ssh-sleep-inhibitor.service

# --- Hook into PAM sshd if not already present ---
PAM_SSHD=/etc/pam.d/sshd
PAM_LINE="session    optional     pam_exec.so quiet /etc/pam_session.sh"

if ! grep -qF "pam_session.sh" "$PAM_SSHD"; then
    echo "$PAM_LINE" >> "$PAM_SSHD"
    echo "  Added pam_exec line to $PAM_SSHD"
else
    echo "  pam_exec line already present in $PAM_SSHD, skipping"
fi

# --- Ensure targets are not masked ---
systemctl unmask sleep.target suspend.target 2>/dev/null || true

# --- Reload systemd ---
systemctl daemon-reload

echo "  SSH sleep inhibitor installed. It will activate on next SSH login."
