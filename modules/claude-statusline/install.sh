#!/bin/bash
# Installs the custom Claude Code statusline script and configures ~/.claude/settings.json
# to use it.
# Requires: bash, jq, curl (curl is used at runtime by the script for rate limit fetching)

set -euo pipefail

MODULE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

TARGET_USER="${SUDO_USER:-$USER}"
if command -v getent &>/dev/null; then
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
else
    TARGET_HOME=$(eval echo "~$TARGET_USER")
fi

CLAUDE_DIR="$TARGET_HOME/.claude"
SCRIPT_DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# Install the statusline script
mkdir -p "$CLAUDE_DIR"
cp "$MODULE_DIR/files/home/.claude/statusline.sh" "$SCRIPT_DEST"
chmod 755 "$SCRIPT_DEST"
chown "$TARGET_USER" "$SCRIPT_DEST" 2>/dev/null || true
echo "  Statusline script installed to $SCRIPT_DEST."

# Configure settings.json atomically
tmp=$(mktemp)
{ cat "$SETTINGS" 2>/dev/null || echo '{}'; } \
    | jq --arg cmd "$SCRIPT_DEST" '.statusLine = {"type": "command", "command": $cmd}' > "$tmp"
mkdir -p "$(dirname "$SETTINGS")"
cp "$tmp" "$SETTINGS"
chmod 644 "$SETTINGS"
chown "$TARGET_USER" "$SETTINGS" 2>/dev/null || true
rm -f "$tmp"
echo "  ~/.claude/settings.json updated."
