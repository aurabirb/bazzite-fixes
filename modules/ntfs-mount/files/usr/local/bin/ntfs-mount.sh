#!/bin/bash
# Mounts/unmounts all NTFS partitions via udisks2.
# Must run as root (via pkexec) so ntfsfix can clear the dirty bit.
# udisksctl is called as the original calling user (PKEXEC_UID) so udisks2
# applies uid/gid ownership correctly — otherwise drives mount as root.

TARGET_UID="${PKEXEC_UID:-$(id -u)}"
TARGET_USER=$(id -un "$TARGET_UID")

lsblk --filter "TYPE==\"part\" && FSTYPE==\"ntfs\"" -no KNAME | while read -r DEV; do
  LABEL=$(lsblk -no LABEL "/dev/$DEV" 2>/dev/null)
  [ -z "$LABEL" ] && continue
  MOUNTPOINT="/run/media/$TARGET_USER/$LABEL"

  if [ "${1:-mount}" == "unmount" ] || ! mountpoint -q "$MOUNTPOINT"; then
    # Clear dirty bit before mounting so drive isn't forced read-only after unclean shutdown
    [ "${1:-mount}" == "mount" ] && ntfsfix -d "/dev/$DEV"
    sudo -u "#$TARGET_UID" /usr/bin/udisksctl "${1:-mount}" -b "/dev/$DEV" --no-user-interaction
  else
    echo "$DEV is already mounted at $MOUNTPOINT"
  fi
done
