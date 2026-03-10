#!/bin/bash
# Installs the custom Claude Code statusline script and configures ~/.claude/settings.json
# to use it.
# Requires: bash, jq, curl (curl is used at runtime by the script for rate limit fetching)

set -euo pipefail

MODULE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

CLAUDE_DIR="$TARGET_HOME/.claude"
SCRIPT_DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# Install the statusline script (install -D also creates $CLAUDE_DIR if needed)
install -Dm755 -o "$TARGET_USER" -g "$TARGET_USER" \
    "$MODULE_DIR/files/home/.claude/statusline.sh" "$SCRIPT_DEST"
echo "  Statusline script installed to $SCRIPT_DEST."

# Configure settings.json atomically
tmp=$(mktemp)
{ cat "$SETTINGS" 2>/dev/null || echo '{}'; } \
    | jq --arg cmd "$SCRIPT_DEST" '.statusLine = {"type": "command", "command": $cmd}' > "$tmp"
install -Dm644 -o "$TARGET_USER" -g "$TARGET_USER" "$tmp" "$SETTINGS"
rm -f "$tmp"
echo "  ~/.claude/settings.json updated."
