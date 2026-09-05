#!/usr/bin/env bash
# Teach the in-tree huawei-wmi driver the HONOR hotkey codes it does not know,
# and silence the meaningless atkbd scancode the EC sends alongside them.
#
#   sudo bash install.sh
#   sudo KBDLIGHT_TIMEOUT=30 bash install.sh    # M1020 only; 0 disables timeout
#   sudo KVER=7.1.8-1-cachyos bash install.sh   # build for a not-yet-booted kernel
#
# Reruns are safe. Re-run after a kernel update, or install patch/auto-rebuild/.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER="${KVER:-$(uname -r)}"
SRC_REL="drivers/platform/x86/huawei-wmi.c"
HWDB_DST=/etc/udev/hwdb.d/61-honor-keyboard.hwdb
KBDLIGHT_CONF=/etc/modprobe.d/61-honor-keyboard-backlight.conf
WORK=$(mktemp -d /var/tmp/honor-hotkeys-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. is this fix meant for this machine ------------------------------------
# Tier B: the codes were read off one model. Feeding another machine's hotkey
# map to its EC-driven keymap is not destructive, but it produces keys that do
# the wrong thing, which is worse than keys that do nothing.
source "${SCRIPT_DIR}/../../lib/gate.sh"
honor_gate hotkeys

# The codes and the hwdb rule were captured on one machine and belong to its
# firmware, so they live in patch/hotkeys/<model>/<board>/ like every other
# per-machine part.
variant_find "$SCRIPT_DIR" || die \
    "this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
    Covered: $(variant_known "$SCRIPT_DIR")
    Capture that machine's codes with patch/hotkeys/capture-keys.sh and add a
    directory for it. See patch/hotkeys/README.md."
HWDB_SRC="${VARIANT_DIR}/$(recipe_get hwdb)"
[[ -f "$HWDB_SRC" ]] || die "${VARIANT_DIR}/recipe.conf names an hwdb file that is not there: $(recipe_get hwdb)"

for t in curl make; do command -v "$t" >/dev/null || die "missing required tool: $t"; done
KDIR="$(distro_module_dir "$KVER")/build"
[[ -d "$KDIR" ]] || die "no kernel build directory at $KDIR.
    Install the headers for $KVER, or pass KVER= for a kernel that has them."

log "machine = $(variant_note)"
log "kernel  = $KVER"
if [[ -n "${KBDLIGHT_TIMEOUT:-}" ]]; then
    [[ "${PROFILE_BOARD:-}" == M1020 ]] \
        || die "KBDLIGHT_TIMEOUT is only supported by the physically verified ZQC-P M1020 implementation"
    [[ "$KBDLIGHT_TIMEOUT" =~ ^[0-9]+$ ]] && (( KBDLIGHT_TIMEOUT <= 65535 )) \
        || die "KBDLIGHT_TIMEOUT must be an integer from 0 through 65535 seconds"
fi

# --- 2. fetch the driver source matching the running kernel -------------------
ksrc_resolve
log "sources = $KSRC_TAG"
ksrc_fetch "$SRC_REL" "${WORK}/huawei-wmi.c"

# --- 3. add the codes ---------------------------------------------------------
# The codes below are the ones this machine was observed emitting. Anything the
# kernel already knows is left alone, so this stays a no-op once the mappings
# land upstream.
python3 - "${WORK}/huawei-wmi.c" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path).read()

additions = [
    ("0x283", "KEY_TOUCHPAD_ON",           "HONOR: touchpad lock toggle"),
    ("0x2a3", "KEY_TOUCHPAD_OFF",          None),
    ("0x288", "KEY_CAMERA_ACCESS_TOGGLE",  "HONOR: camera shutter"),
    ("0x2b1", "KEY_KBDILLUMDOWN",          "HONOR: keyboard backlight level"),
    ("0x2b2", "KEY_KBDILLUMDOWN",          None),
    ("0x2b3", "KEY_KBDILLUMUP",            None),
    ("0x2b4", "KEY_KBDILLUMTOGGLE",        None),
    ("0x2a0", "KEY_PROG1",                 "HONOR: performance mode"),
    ("0x2a1", "KEY_PROG1",                 None),
    ("0x2a6", "KEY_PROG1",                 None),
    ("0x2a7", "KEY_REFRESH_RATE_TOGGLE",   "HONOR: refresh rate toggle"),
    ("0x2e0", "KEY_CAMERA_ACCESS_ENABLE",  "HONOR: camera module"),
    ("0x2e1", "KEY_CAMERA_ACCESS_DISABLE", None),
]
ignores = [
    ("0x2e5", "HONOR: EC keyboard-backlight notifications, not key presses"),
    ("0x2e6", None),
]

anchor = "\t{ KE_END,"
if anchor not in src:
    raise SystemExit("could not find the end of huawei_wmi_keymap")

new = []
for code, key, comment in additions:
    if re.search(r"\b%s\b" % code, src):
        continue
    if comment:
        new.append("\t/* %s */\n" % comment)
    new.append("\t{ KE_KEY,    %s, { %s } },\n" % (code, key))
for code, comment in ignores:
    if re.search(r"\b%s\b" % code, src):
        continue
    if comment:
        new.append("\t/* %s */\n" % comment)
    new.append("\t{ KE_IGNORE, %s, { KEY_RESERVED } },\n" % code)

if not new:
    print("nothing to add: this kernel already knows every code")
else:
    src = src.replace(anchor, "".join(new) + anchor, 1)
    open(path, "w").write(src)
    print("added %d keymap entries" % sum(1 for l in new if "KE_" in l))
PYEOF
python3 "${SCRIPT_DIR}/add-m1020-kbdlight.py" "${WORK}/huawei-wmi.c"

# --- 4. build -----------------------------------------------------------------
cat > "${WORK}/Makefile" <<EOF
obj-m += huawei-wmi.o
EOF

MAKEVARS=()
distro_kernel_config_has CONFIG_CC_IS_CLANG=y "$KVER" && MAKEVARS=(LLVM=1 LLVM_IAS=1)

log "building huawei-wmi.ko"
make -C "$KDIR" M="$WORK" "${MAKEVARS[@]}" modules >/dev/null 2>"${WORK}/build.err" || {
    tail -20 "${WORK}/build.err" >&2
    die "build failed"
}

NEW_VM=$(modinfo "${WORK}/huawei-wmi.ko" | awk -F': *' '/^vermagic:/{print $2}')
OLD_VM=$(modinfo -k "$KVER" huawei-wmi 2>/dev/null | awk -F': *' '/^vermagic:/{print $2}')
[[ "$NEW_VM" == "$OLD_VM" ]] || die "vermagic mismatch, refusing to install
    built:   $NEW_VM
    running: $OLD_VM"

DEST="$(distro_module_install "${WORK}/huawei-wmi.ko" huawei-wmi "$KVER")"
log "installed $DEST"

if [[ -n "${KBDLIGHT_TIMEOUT:-}" ]]; then
    cat > "$KBDLIGHT_CONF" <<EOF
# Written by patch/hotkeys/install.sh. Zero disables the keyboard-backlight timeout.
options huawei-wmi kbdlight_timeout=$KBDLIGHT_TIMEOUT
EOF
    chmod 0644 "$KBDLIGHT_CONF"
    log "keyboard backlight timeout = $KBDLIGHT_TIMEOUT seconds"
elif [[ -r "$KBDLIGHT_CONF" ]]; then
    log "preserving keyboard backlight timeout from $KBDLIGHT_CONF"
fi

# --- 5. silence the companion atkbd scancode ----------------------------------
gate_hwdb_render "$HWDB_SRC" "$HWDB_DST"
if command -v systemd-hwdb >/dev/null; then
    systemd-hwdb update && udevadm trigger --subsystem-match=input --action=change
    log "installed $HWDB_DST"
else
    warn "systemd-hwdb not found; $HWDB_DST installed but not compiled"
fi

# --- 6. load it ---------------------------------------------------------------
if [[ "$KVER" != "$(uname -r)" ]]; then
    log "built for $KVER, which is not running. It loads after you boot into it."
    exit 0
fi

modprobe -r huawei-wmi 2>/dev/null || true
modprobe huawei-wmi || die "the new module would not load; check dmesg"
log "reloaded huawei-wmi from $(modinfo -k "$KVER" huawei-wmi | awk '/^filename:/{print $2}')"

cat <<EOF

════════════════════════════════════════════════════════════════════
  Hotkeys mapped.

  Press the keys that used to do nothing and watch what arrives:

      sudo evtest /dev/input/by-path/platform-huawei-wmi-event
      journalctl -kf | grep -i 'Unknown key'      # should stay quiet now

  A code that still shows up as "Unknown key pressed" is one this model
  emits and the map does not have yet. Please open an issue with it.

  What each one is bound to is then up to the desktop: the performance-mode
  key arrives as KEY_PROG1, the touchpad lock as KEY_TOUCHPAD_ON/OFF.

  On ZQC-P M1020/C170, keyboard backlight is available to KDE and UPower at:
      /sys/class/leds/platform::kbd_backlight
  The default timeout is 15 seconds. Set another value by rerunning, for example:
      sudo KBDLIGHT_TIMEOUT=30 bash $0
  Use 0 for no timeout. The setting is kept across kernel auto-rebuilds.
════════════════════════════════════════════════════════════════════
EOF
