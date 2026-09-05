#!/usr/bin/env bash
# uninstall.sh — put the packaged huawei-wmi keymap back.
#
# Runs on its own: sudo bash $0
# See lib/uninstall.sh for why this is not gated on the device profile.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../lib/uninstall.sh"

u_log "Removing the huawei-wmi overlay and the atkbd hwdb entry"
shopt -s nullglob
u_rm "/usr/lib/modules/${KVER}/updates/huawei-wmi.ko" \
     "/usr/lib/modules/${KVER}/updates/huawei-wmi.ko.zst" \
     /etc/udev/hwdb.d/61-honor-keyboard.hwdb \
     /etc/modprobe.d/61-honor-keyboard-backlight.conf \
  || echo "    nothing installed"
shopt -u nullglob
command -v systemd-hwdb >/dev/null && systemd-hwdb update 2>/dev/null || true
u_depmod

if [[ "$KVER" == "$(uname -r)" ]]; then
    modprobe -r huawei-wmi 2>/dev/null || true
    modprobe huawei-wmi 2>/dev/null || true
    echo "    reloaded the packaged module"
fi
echo "    the HONOR-specific Fn keys go back to 'Unknown key pressed' in dmesg,"
echo "    and the extra PS/2 scancode the EC sends alongside them is noisy again."
u_done
