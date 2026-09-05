#!/usr/bin/env bash
# Give the HONOR hotkeys something to do.
#
# patch/hotkeys/ makes the keys arrive as key events. That is where the kernel's
# job ends: KEY_PROG1 means "programmable key one" and no desktop binds it, and
# nothing turns KEY_CAMERA_ACCESS_TOGGLE into a camera that is actually off.
#
#   sudo bash install.sh
#   sudo CAMERA_KEY=0 bash install.sh        # leave the camera key alone
#   sudo POWER_PROFILE_KEY=0 bash install.sh # leave the performance key alone
#
# Reruns are safe.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR=/usr/local/lib/honor
CONF=/etc/honor-hotkey-actions.conf

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. gate ------------------------------------------------------------------
# Tier A: it listens on a device matched by name and writes only to the USB
# device the profile names. On hardware without either, it does nothing.
source "${SCRIPT_DIR}/../../lib/gate.sh"
honor_gate hotkey-actions

# Every fix is looked up the same way, including the ones that carry no
# numbers of their own: patch/hotkey-actions/<model>/<board>/ records that this
# machine was considered and on what evidence. See lib/variant.sh.
variant_find "$SCRIPT_DIR" || die \
    "this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
    Covered: $(variant_known "$SCRIPT_DIR")"
log "machine: $(variant_note)"

command -v python3 >/dev/null || die "python3 is required"

# --- 2. what it should act on -------------------------------------------------
CAMERA_USB="$(gate_param camera_usb CAMERA_USB)" || CAMERA_USB=""
POWER_PROFILE_KEY="${POWER_PROFILE_KEY:-1}"
CAMERA_KEY="${CAMERA_KEY:-1}"

if [[ "$POWER_PROFILE_KEY" == "1" ]] && ! command -v powerprofilesctl >/dev/null; then
    warn "powerprofilesctl not found, so the performance key will have nothing
    to switch. Install power-profiles-daemon, or pass POWER_PROFILE_KEY=0."
fi

if [[ "$CAMERA_KEY" == "1" ]]; then
    if [[ -z "$CAMERA_USB" ]]; then
        warn "$(profile_get model) does not record camera_usb, so the camera key
    stays inert. Find the webcam in 'lsusb' and add it to the profile."
        CAMERA_KEY=0
    elif ! lsusb -d "$CAMERA_USB" >/dev/null 2>&1; then
        warn "no USB device $CAMERA_USB present; the camera key will do nothing
    until it appears."
    fi
fi

log "performance key: $([[ "$POWER_PROFILE_KEY" == 1 ]] && echo "cycles power profiles" || echo "off")"
log "camera key     : $([[ "$CAMERA_KEY" == 1 ]] && echo "toggles $CAMERA_USB on the USB bus" || echo "off")"

# --- 3. install ---------------------------------------------------------------
install -d -m 0755 "$LIB_DIR"
install -m 0755 "${SCRIPT_DIR}/honor-hotkey-actions.py" "${LIB_DIR}/"
install -m 0644 "${SCRIPT_DIR}/honor-hotkey-actions.service" /etc/systemd/system/

cat > "$CONF" <<EOF
# Written by patch/hotkey-actions/install.sh.
# Set a key to 0 to leave it alone, then: systemctl restart honor-hotkey-actions
POWER_PROFILE_KEY=$POWER_PROFILE_KEY
CAMERA_KEY=$CAMERA_KEY
CAMERA_USB="$CAMERA_USB"
EOF
chmod 0644 "$CONF"

systemctl daemon-reload
systemctl enable honor-hotkey-actions.service >/dev/null 2>&1 \
    || die "could not enable honor-hotkey-actions.service"
systemctl restart honor-hotkey-actions.service \
    || die "could not start honor-hotkey-actions.service; see journalctl -u honor-hotkey-actions"
sleep 1
systemctl is-active --quiet honor-hotkey-actions.service \
    || die "the service is not running; see journalctl -u honor-hotkey-actions"
log "service running"

cat <<EOF

════════════════════════════════════════════════════════════════════
  Hotkey actions installed.

  Performance key : $([[ "$POWER_PROFILE_KEY" == 1 ]] && echo "cycles power-saver -> balanced -> performance" || echo "off")
  Camera key      : deauthorises the webcam on the USB bus, so it leaves
                    /dev/video* entirely. Press again to bring it back.

  Watch it work:
      journalctl -u honor-hotkey-actions -f

  Camera state by hand, if you ever need it:
      lsusb | grep -i camera
      cat /sys/bus/usb/devices/*/authorized

  Turn one off:
      sudo CAMERA_KEY=0 bash $0
════════════════════════════════════════════════════════════════════
EOF
