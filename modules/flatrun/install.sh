#!/bin/bash
# Installs the flatrun shell function, which lets you launch a Flatpak by a
# partial name without needing the full app ID.
# Usage: flatrun <partial-name> [args...]

set -euo pipefail

BASHRC_D="$HOME/.bashrc.d"
DEST="$BASHRC_D/flatrun.sh"

mkdir -p "$BASHRC_D"
cat > "$DEST" << 'EOF'
flatrun() { flatpak run $(flatpak list --columns=ref | grep -i "$1" | head -1 | cut -d/ -f1) "${@:2}"; }
EOF
echo "  flatrun function installed to $DEST."
echo "  Run 'source $DEST' or open a new shell to use it."
