#!/bin/bash
# Configures udisks2 to use the ntfs3 kernel driver by default (faster than
# ntfs-3g fuse), with proper uid/gid mapping and discard support.
# Edits /etc/udisks2/mount_options.conf in place rather than overwriting it.

set -euo pipefail

CONF=/etc/udisks2/mount_options.conf

# Ensure the file and [defaults] section exist
if [[ ! -f "$CONF" ]]; then
    echo "[defaults]" > "$CONF"
elif ! grep -q "^\[defaults\]" "$CONF"; then
    echo "[defaults]" >> "$CONF"
fi

# Sets or replaces a key under [defaults]. If the key exists anywhere in the
# file it is updated in place; otherwise it is appended after [defaults].
set_option() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$CONF"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$CONF"
        echo "  Updated: ${key}=${value}"
    else
        # Insert after [defaults] line
        sed -i "/^\[defaults\]/a ${key}=${value}" "$CONF"
        echo "  Added:   ${key}=${value}"
    fi
}

set_option "ntfs_drivers"        "ntfs3,ntfs"
set_option "ntfs:ntfs3_defaults" "uid=\$UID,gid=\$GID,discard"

systemctl restart udisks2 2>/dev/null || true

echo "  ntfs3 driver set as default in $CONF"
