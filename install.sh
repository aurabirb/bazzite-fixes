#!/bin/bash
# Main installer. Runs install.sh for each module under modules/.
# Usage: ./install.sh [module ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

mapfile -t all_modules < <(ls "$MODULES_DIR")

[[ $# -eq 0 || ${1:-} == -h || ${1:-} == --help ]] && {
    echo "Usage: ./install.sh <module [...]|--all>"
    echo "       sudo ./install.sh ...  (modules with *)"
    echo ""
    echo "Modules:"
    for m in "${all_modules[@]}"; do
        [[ -f "$MODULES_DIR/$m/no-root-required" ]] && echo "  $m" || echo "* $m"
    done
    exit 0
}

if [[ ${1:-} == --all ]]; then
    modules=("${all_modules[@]}")
else
    modules=("$@")
fi

for module in "${modules[@]}"; do
    [[ ! -d "$MODULES_DIR/$module" ]] && { echo "[$module] Unknown module" >&2; exit 1; }
    [[ ! -f "$MODULES_DIR/$module/no-root-required" ]] && needs_root=1
done
[[ ${needs_root:-0} -eq 1 && $EUID -ne 0 ]] && { echo "Run as root: sudo ./install.sh" >&2; exit 1; }

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
