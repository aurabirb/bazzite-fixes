#!/bin/bash
# Main installer. Runs install.sh for each module under modules/.
# Usage: sudo ./install.sh [module_name ...]
#   No args: runs all modules
#   With args: runs only the named modules

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo ./install.sh" >&2
    exit 1
fi

if [[ $# -gt 0 ]]; then
    modules=("$@")
else
    mapfile -t modules < <(ls "$MODULES_DIR")
fi

for module in "${modules[@]}"; do
    installer="$MODULES_DIR/$module/install.sh"
    if [[ ! -f "$installer" ]]; then
        echo "[$module] No install.sh found, skipping"
        continue
    fi
    echo "[$module] Installing..."
    bash "$installer" "$MODULES_DIR/$module"
    echo "[$module] Done"
done
