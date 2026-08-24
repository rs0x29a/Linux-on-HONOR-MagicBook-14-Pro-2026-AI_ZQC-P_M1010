#!/usr/bin/env bash
# Install the opt-in, fail-safe fan-curve controller.

set -euo pipefail
(( EUID == 0 )) || { echo "Must be run as root." >&2; exit 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/../../lib/gate.sh"
honor_gate fan

TARGET="${FAN_CURVE:-}"
[[ -n "$TARGET" ]] || {
    echo "Choose a validated curve explicitly, e.g. FAN_CURVE=0xAA bash $0" >&2
    echo "0xA0 is stock; 0xAA/0xAB engage earlier. 0xAC is forbidden." >&2
    exit 2
}
case "${TARGET^^}" in 0XA0|0XAA|0XAB) ;; *) echo "Unsafe or unknown FAN_CURVE=$TARGET" >&2; exit 2 ;; esac
FAILSAFE_TEMP="${FAILSAFE_TEMP:-85}"
[[ "$FAILSAFE_TEMP" =~ ^[0-9]+$ ]] && (( FAILSAFE_TEMP >= 70 && FAILSAFE_TEMP <= 95 )) || {
    echo "FAILSAFE_TEMP must be an integer from 70 to 95C" >&2
    exit 2
}

modprobe acpi_call 2>/dev/null || true
[[ -w /proc/acpi/call ]] || {
    echo "acpi_call is required. Install/load the distro acpi_call module, then re-run." >&2
    exit 1
}

install -d -m 0755 /usr/local/lib/honor
install -m 0755 "$SRC_DIR/honor-fan-curve.sh" /usr/local/lib/honor/
install -m 0644 "$SRC_DIR/honor-fan-curve.service" /etc/systemd/system/
cat > /etc/honor-fan-curve.conf <<EOF
# Validated values only: 0xA0 stock, 0xAA/0xAB earlier engagement.
TARGET=$TARGET
FAILSAFE_TEMP=$FAILSAFE_TEMP
POLL_SECONDS=${POLL_SECONDS:-5}
EOF
chmod 0644 /etc/honor-fan-curve.conf
systemctl daemon-reload
systemctl enable --now honor-fan-curve.service
echo "Fan curve controller enabled with $TARGET; it reverts to 0xA0 at ${FAILSAFE_TEMP:-85}C."
