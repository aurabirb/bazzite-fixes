#!/bin/bash
# Installs the diskclean command to ~/.local/bin. It wraps `ujust clean-system`
# (podman, unused flatpaks, rpm-ostree, brew) and adds user-level flatpaks,
# flatpak GL runtimes for old NVIDIA drivers, and a btrfs rebalance when the
# filesystem has run out of unallocated space. Opt-in: Steam's library cache,
# the Hugging Face and Homebrew caches, and the VS Code remote server.
# Usage: diskclean [--steam-cache] [--hf-cache] [--brew-cache] [--vscode-server] [--balance] [--all]

set -euo pipefail

DEST_DIR="$HOME/.local/bin"
DEST="$DEST_DIR/diskclean"

mkdir -p "$DEST_DIR"
cat > "$DEST" << 'SCRIPT'
#!/bin/bash
set -uo pipefail

usage="Usage: diskclean [--steam-cache] [--hf-cache] [--brew-cache] [--vscode-server] [--balance] [--all]"
steam=0 hf=0 brew=0 vscode=0 balance=0
for a in "$@"; do
    case "$a" in
        --steam-cache) steam=1 ;;
        --hf-cache) hf=1 ;;
        --brew-cache) brew=1 ;;
        --vscode-server) vscode=1 ;;
        --balance) balance=1 ;;
        --all) steam=1 hf=1 brew=1 vscode=1 balance=1 ;;
        *) echo "$usage" >&2; exit 1 ;;
    esac
done

before=$(df --output=avail -B1 /var | tail -1)

echo "== ujust clean-system =="
ujust clean-system
echo "== user flatpaks =="
flatpak uninstall --user --unused -y
echo "== journal =="
sudo journalctl --vacuum-size=200M

# Flatpak keeps a GL runtime for every NVIDIA driver it has seen. Only the one
# matching the running driver is used; the rest are ~1 GB each.
driver=$(cat /sys/module/nvidia/version 2>/dev/null)
if [[ -n $driver ]]; then
    echo "== old NVIDIA flatpak runtimes (keeping $driver) =="
    for scope in --user --system; do
        refs=$(flatpak list $scope --runtime --columns=ref \
            | grep -E '^org\.freedesktop\.Platform\.GL(32)?\.nvidia-' \
            | grep -v -- "nvidia-${driver//./-}/")
        [[ -n $refs ]] && flatpak uninstall $scope -y $refs
    done
fi

if [[ $steam -eq 1 ]]; then
    if pgrep -x steam >/dev/null; then
        echo "Steam is running, skipping its library cache (close Steam first)." >&2
    else
        echo "== steam librarycache =="
        rm -rf "$HOME/.local/share/Steam/appcache/librarycache"
    fi
fi
if [[ $hf -eq 1 ]]; then
    echo "== huggingface cache =="
    rm -rf "$HOME/.cache/huggingface"
fi
if [[ $brew -eq 1 ]]; then
    echo "== homebrew cache =="
    rm -rf "$HOME/.cache/Homebrew"
fi
if [[ $vscode -eq 1 ]]; then
    # VS Code reinstalls it on the next Remote-SSH connection
    if pgrep -f "$HOME/.vscode-server/" >/dev/null; then
        echo "A VS Code remote session is running, skipping ~/.vscode-server." >&2
    else
        echo "== vscode server =="
        rm -rf "$HOME/.vscode-server"
    fi
fi

# When btrfs has allocated every chunk to data, metadata can't grow and new
# files fail with ENOSPC although df shows free space. Repack mostly empty
# data chunks to return space to the unallocated pool. Runs automatically
# below 2 GiB unallocated, or always with --balance.
if [[ $(findmnt -no FSTYPE /var/home) == btrfs ]]; then
    unalloc() { sudo btrfs filesystem usage -b /var/home | awk '/Device unallocated:/ {print $3}'; }
    if [[ $balance -eq 1 || $(unalloc) -lt $((2 * 1024 ** 3)) ]]; then
        echo "== btrfs balance (unallocated: $(numfmt --to=iec "$(unalloc)")) =="
        for u in 0 10 30 50 70 85; do
            sudo btrfs balance start -dusage=$u -dlimit=10 /var/home | tail -1
        done
        echo "Unallocated now: $(numfmt --to=iec "$(unalloc)")"
    fi
fi

after=$(df --output=avail -B1 /var | tail -1)
echo "Freed: $(numfmt --to=iec $((after - before)))  (free on /var: $(numfmt --to=iec "$after"))"
SCRIPT
chmod +x "$DEST"
echo "  diskclean installed to $DEST."
echo "  Run 'diskclean' (or 'diskclean --all' to include the opt-in caches and a full rebalance)."
