#!/usr/bin/env bash
# Install the EC-backed keyboard backlight LED for ZQC-P.

set -euo pipefail
(( EUID == 0 )) || { echo "Must be run as root." >&2; exit 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER="${KVER:-$(uname -r)}"
KDIR="/lib/modules/${KVER}/build"
MODNAME=honor-zqcp-kbdlight
MODVER=1.0

source "$SRC_DIR/../../lib/gate.sh"
honor_gate keyboard-backlight

[[ -d "$KDIR" ]] || { echo "Missing kernel headers: $KDIR" >&2; exit 1; }
if [[ -e /sys/class/leds/huawei::kbd_backlight ]]; then
    echo "A huawei::kbd_backlight LED already exists; refusing a duplicate." >&2
    echo "If writes return -ENODEV, collect tools/doctor.sh --json first." >&2
    exit 1
fi

if command -v dkms >/dev/null 2>&1; then
    DEST="/usr/src/${MODNAME}-${MODVER}"
    dkms remove -m "$MODNAME" -v "$MODVER" --all >/dev/null 2>&1 || true
    rm -rf "$DEST"
    install -d "$DEST"
    install -m 644 "$SRC_DIR"/{honor-zqcp-kbdlight.c,Makefile,dkms.conf} "$DEST/"
    dkms add -m "$MODNAME" -v "$MODVER"
    dkms build -m "$MODNAME" -v "$MODVER" -k "$KVER"
    dkms install -m "$MODNAME" -v "$MODVER" -k "$KVER"
else
    work="$(mktemp -d /tmp/honor-kbdlight-XXXXXX)"
    trap 'rm -rf "$work"' EXIT
    cp "$SRC_DIR"/{honor-zqcp-kbdlight.c,Makefile} "$work/"
    make -C "$KDIR" M="$work" modules
    install -Dm644 "$work/${MODNAME}.ko" "/lib/modules/${KVER}/updates/${MODNAME}.ko"
    depmod -a "$KVER"
fi

install -Dm644 /dev/null /etc/modules-load.d/${MODNAME}.conf
printf '%s\n' "$MODNAME" > /etc/modules-load.d/${MODNAME}.conf
if [[ "$KVER" == "$(uname -r)" ]]; then
    modprobe -r "$MODNAME" 2>/dev/null || true
    modprobe "$MODNAME"
fi
echo "Keyboard backlight installed. Test: brightnessctl -d huawei::kbd_backlight set 1"
