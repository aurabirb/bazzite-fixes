#!/bin/bash
# Builds and layers gpu-unlock (https://github.com/Zagitta/gpu-unlock), which
# lifts NVIDIA's half-rate FP16/BF16/TF32 tensor cap on GeForce cards.
#
# Upstream only ships DKMS packages, which don't work on rpm-ostree. Instead
# this builds the module for one kernel, wraps it with its firmware and dracut
# drop-in in a local RPM, and layers that. The module is kernel specific, so
# re-run this after every Bazzite update that changes the kernel. It targets
# the next-boot deployment, so it can run after `rpm-ostree upgrade` and
# before rebooting.
#
# Env overrides:
#   GPU_UNLOCK_REF=<git ref>        upstream commit/tag to build (default: pinned)
#   GPU_UNLOCK_TARGETS=<pci,...>    cards to unlock (default: every NVIDIA GPU)
#   GPU_UNLOCK_FORCE=1              rebuild even if the module already exists
#
# Undo: rpm-ostree uninstall gpu-unlock-local
#       rpm-ostree kargs --delete-if-present=gpu_unlock.targets=<value>

set -euo pipefail

MODULE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

REPO=https://github.com/Zagitta/gpu-unlock
REF="${GPU_UNLOCK_REF:-7eb51bccae0a0b7e599e084d971170e9a1e82d0c}"
PKG=gpu-unlock-local

# Build steps run as the real user; only rpm-ostree and podman need root
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
CACHE="$TARGET_HOME/.cache/gpu-unlock"
as_user() { runuser -u "$TARGET_USER" -- "$@"; }

# --- Target deployment (staged or booted, whichever boots next) ---

# Prints fields of the deployment that boots next, space separated (lists flattened)
next_deployment() {
    rpm-ostree status --json | python3 -c '
import json, sys
d = json.load(sys.stdin)["deployments"][0]
vals = [d.get(k) for k in sys.argv[1:]]
print(" ".join(" ".join(v) if isinstance(v, list) else str(v) for v in vals))' "$@"
}

read -r CHECKSUM SERIAL OSNAME < <(next_deployment checksum serial osname)
DEPLOY="/sysroot/ostree/deploy/$OSNAME/deploy/$CHECKSUM.$SERIAL"
KVER=$(ls "$DEPLOY/usr/lib/modules" | head -1)
KDIR="$DEPLOY/usr/src/kernels/$KVER"
FEDORA=$(. "$DEPLOY/usr/lib/os-release" && echo "$VERSION_ID")
echo "  Target kernel: $KVER (Fedora $FEDORA)"

[[ -d $KDIR ]] || { echo "  No kernel-devel for $KVER in the deployment ($KDIR)" >&2; exit 1; }

# --- Kernel argument: which cards to unlock ---

TARGETS="${GPU_UNLOCK_TARGETS:-$(lspci -D -d 10de: | awk '/VGA|3D/ {print $1}' | paste -sd,)}"
[[ -n $TARGETS ]] || { echo "  No NVIDIA GPU found" >&2; exit 1; }

# --- btrfs headroom ---
# When every chunk is allocated to data, metadata can't grow and any new file
# fails with ENOSPC even though df shows free space. rpm-ostree checkouts are
# metadata heavy, so make sure there is unallocated space first.

ensure_btrfs_headroom() {
    local mnt=/var/home need=$((2 * 1024 * 1024 * 1024)) free u
    [[ $(findmnt -no FSTYPE "$mnt") == btrfs ]] || return 0
    for u in 0 10 30 50 70 85; do
        free=$(btrfs filesystem usage -b "$mnt" | awk '/Device unallocated:/ {print $3}')
        ((free >= need)) && return 0
        echo "  btrfs unallocated is $((free / 1024 / 1024)) MiB, balancing data chunks under ${u}% full..."
        btrfs balance start -dusage=$u -dlimit=10 "$mnt" >/dev/null || true
    done
    free=$(btrfs filesystem usage -b "$mnt" | awk '/Device unallocated:/ {print $3}')
    ((free >= need)) || echo "  Warning: only $((free / 1024 / 1024)) MiB unallocated on btrfs, free some space if rpm-ostree fails" >&2
}

# --- Build and package the module ---

build_rpm() {
    local src="$CACHE/src" inputs="$CACHE/inputs" assets="$CACHE/assets"
    as_user mkdir -p "$CACHE"
    [[ -d $src/.git ]] || as_user git clone -q "$REPO" "$src"
    as_user git -C "$src" fetch -q origin
    as_user git -C "$src" checkout -q --detach "$REF"

    local spec="$src/packaging/rpm/gpu-unlock.spec" nv version commit
    nv=$(awk '/^%global nv / {print $3}' "$spec")
    version=$(cat "$src/VERSION")
    commit=$(as_user git -C "$src" rev-parse --short HEAD)
    echo "  Building gpu-unlock $version ($commit), NVIDIA inputs $nv"

    # Fetch the NVIDIA inputs and check them against the hashes in the spec
    as_user /usr/bin/python3 "$src/firmware/fetch_artifacts.py" "$inputs" >/dev/null
    sed -n '/^sha256sum -c/,/^EOF/p' "$spec" | grep -E '^[0-9a-f]{64} ' \
        | sed -e "s|%{SOURCE1}|NVIDIA-kernel-module-source-$nv.tar.xz|" \
              -e "s|%{SOURCE2}|NVIDIA-Linux-x86_64-$nv-no-compat32.run|" \
        | (cd "$inputs" && sha256sum --quiet -c -)

    as_user make -s -C "$src" PYTHON=/usr/bin/python3 INPUTS="$inputs" ASSETS="$assets" firmware >/dev/null
    rm -rf "$assets.src"
    as_user make -s -C "$src/kernel/gpu_unlock" clean KDIR="$KDIR" >/dev/null
    as_user make -s -C "$src/kernel/gpu_unlock" KDIR="$KDIR"
    [[ $(modinfo -F vermagic "$src/kernel/gpu_unlock/gpu_unlock.ko" | cut -d' ' -f1) == "$KVER" ]] \
        || { echo "  Module vermagic doesn't match $KVER" >&2; exit 1; }

    local stage="$WORK/stage"
    install -Dm644 -t "$stage/usr/lib/modules/$KVER/extra" "$src/kernel/gpu_unlock/gpu_unlock.ko"
    install -Dm644 -t "$stage/usr/lib/firmware/gpu-unlock/$nv" "$assets"/*.bin
    install -Dm644 "$src/packaging/boot/dracut.conf" "$stage/usr/lib/dracut/dracut.conf.d/gpu-unlock.conf"
    install -Dm644 -t "$stage/usr/share/licenses/$PKG" \
        "$src"/licenses/*.txt "$assets/NVIDIA-LICENSE" "$src/firmware/NOTICE.md"

    sed -e "s|@NAME@|$PKG|g" -e "s|@VERSION@|$version|g" -e "s|@KVER@|$KVER|g" \
        -e "s|@RELEASE@|$(echo "${KVER%.*}" | tr - _)|g" \
        -e "s|@COMMIT@|$commit|g" \
        "$MODULE_DIR/files/gpu-unlock-local.spec.in" > "$WORK/$PKG.spec"

    # Bazzite has no rpmbuild; build the RPM in a throwaway Fedora container
    podman run --rm --pull=newer -v "$stage:/stage:ro,Z" -v "$WORK:/work:Z" \
        "registry.fedoraproject.org/fedora:$FEDORA" bash -c \
        "dnf -q -y install rpm-build >/dev/null && rpmbuild -bb --quiet --define '_topdir /tmp/rb' /work/$PKG.spec && cp /tmp/rb/RPMS/*/*.rpm /work/"
    podman rmi -f "registry.fedoraproject.org/fedora:$FEDORA" >/dev/null 2>&1 || true
    RPM=$(ls "$WORK"/$PKG-*.rpm)
}

# --- Layer it ---

# rpm-ostree won't layer an unlabeled local RPM when SELinux is set to
# disabled ("Missing metadata key rpmostree.sepolicy"), so switch the config
# to permissive while it imports and put the original back afterwards.
SELINUX_CONF=/etc/selinux/config
WORK=$(mktemp -d /var/tmp/gpu-unlock.XXXXXX)
cp "$SELINUX_CONF" "$WORK/selinux-config"
restore_selinux() {
    cmp -s "$WORK/selinux-config" "$SELINUX_CONF" || cat "$WORK/selinux-config" > "$SELINUX_CONF"
}
trap 'restore_selinux; rm -rf "$WORK"' EXIT

ensure_btrfs_headroom

if [[ -f $DEPLOY/usr/lib/modules/$KVER/extra/gpu_unlock.ko && ${GPU_UNLOCK_FORCE:-0} != 1 ]]; then
    echo "  gpu_unlock is already layered for $KVER (GPU_UNLOCK_FORCE=1 to rebuild)"
else
    build_rpm
    sed -i 's/^SELINUX=disabled/SELINUX=permissive/' "$SELINUX_CONF"
    if [[ " $(next_deployment requested-local-packages) " == *" $PKG-"* ]]; then
        rpm-ostree uninstall "$PKG" --install "$RPM"
    else
        rpm-ostree install "$RPM"
    fi
    restore_selinux
fi

# dracut picks up the drop-in only if the initramfs is rebuilt locally
if [[ $(next_deployment regenerate-initramfs) != True ]]; then
    rpm-ostree initramfs --enable
fi

current=$(rpm-ostree kargs | grep -o 'gpu_unlock\.targets=[^ ]*' || true)
if [[ $current != "gpu_unlock.targets=$TARGETS" ]]; then
    [[ -n $current ]] && rpm-ostree kargs --delete="$current"
    rpm-ostree kargs --append="gpu_unlock.targets=$TARGETS"
fi

echo "  gpu-unlock staged for $KVER, targets: $TARGETS"
echo "  Reboot, then check: journalctl -k -b | grep gpu_unlock"
