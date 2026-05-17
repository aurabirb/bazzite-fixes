#!/bin/bash
# Fixes Sunshine (Homebrew) streaming on NVIDIA GPUs with proprietary driver 590+.
#
# Problem: Sunshine fails to stream with "Couldn't import RGB Image: 00003009",
#          and crashes on display switch in Moonlight.
#
# Cause:
#   1. Homebrew's libgbm (Mesa) looks for GBM backends only in its own Cellar
#      directory and can't find NVIDIA's (/usr/lib64/gbm/nvidia-drm_gbm.so),
#      causing EGL frame import to fail with EGL_BAD_SURFACE (00003009).
#   2. With NVIDIA's GBM backend active, only the Vulkan encoder path works —
#      Homebrew's Mesa libEGL can't initialize an EGL display against NVIDIA's
#      proprietary DRI2 stack, so software and NVENC encoding both fail probe.
#   3. NVIDIA driver 590+ crashes in libnvidia-glcore when the hevc_vulkan
#      encoder reinitializes on display switch. h264_vulkan is stable.
#   4. The Homebrew systemd service starts before Wayland session variables
#      are exported, so WAYLAND_DISPLAY etc. must be injected manually.
#
# Fix:
#   1. Create a systemd service drop-in with the required environment variables,
#      pointing GBM_BACKENDS_PATH at NVIDIA's backend and pinning VK_ICD_FILENAMES
#      to NVIDIA's Vulkan ICD.
#   2. Disable HEVC and AV1 in sunshine.conf to force H.264 Vulkan encoding.

set -euo pipefail

# Change to "sunshine" if using stable instead of beta
SERVICE="sunshine-beta"

SUNSHINE_CONF="$HOME/.config/sunshine/sunshine.conf"
DROPIN_DIR="$HOME/.config/systemd/user/homebrew.${SERVICE}.service.d"

# --- Systemd service drop-in ---

mkdir -p "$DROPIN_DIR"
cat > "$DROPIN_DIR/wayland-env.conf" << 'EOF'
[Service]
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=DISPLAY=:0
Environment=GBM_BACKENDS_PATH=/usr/lib64/gbm:/usr/lib/gbm
Environment=VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json
EOF
echo "  Service drop-in written to $DROPIN_DIR/wayland-env.conf."

# --- Sunshine config ---

touch "$SUNSHINE_CONF"
grep -qxF 'hevc_mode = 0' "$SUNSHINE_CONF" || echo 'hevc_mode = 0' >> "$SUNSHINE_CONF"
grep -qxF 'av1_mode = 0'  "$SUNSHINE_CONF" || echo 'av1_mode = 0'  >> "$SUNSHINE_CONF"
echo "  hevc_mode and av1_mode disabled in $SUNSHINE_CONF."

# --- Reload and restart ---

systemctl --user daemon-reload
systemctl --user restart "homebrew.${SERVICE}.service"
echo "  Sunshine restarted."
