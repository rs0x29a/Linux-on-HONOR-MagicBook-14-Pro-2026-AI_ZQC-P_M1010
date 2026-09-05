#!/usr/bin/env bash
# Build and install the HID-BPF fixup that removes the phantom KEY_MICMUTE
# device created from a touchscreen's vendor collection.
#
# See README.md in this directory for the root cause.
#
# Nothing here is tied to one laptop. The touchscreen id comes from the board
# section of the device profile and is then confirmed against the HID bus, and
# the program itself comes from <model>/<board>/, one directory per machine.
# Adding a machine is adding a directory.
#
# Reruns are safe. Nothing here has to be repeated after a kernel update:
# the BPF object is CO-RE and libbpf relocates it against the running
# kernel's BTF.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/etc/udev-hid-bpf"
STATE_CONF="/etc/honor-micmute.conf"
KVER="$(uname -r)"
WORK=$(mktemp -d /var/tmp/honor-hidbpf-XXXXXX)

trap 'rm -rf "$WORK"' EXIT

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. is this fix meant for this machine ------------------------------------
# Tier A: the program is bound to one HID id, so it never attaches on a machine
# without that touchscreen.
source "${SCRIPT_DIR}/../../lib/gate.sh"
honor_gate micmute

# The profile lists what the board is known to ship; go and see which of those
# is actually here. A value that is merely written down is not a reason to build
# a program for a chip that is not fitted.
rc=0; HID_ID="$(gate_probe_hid touchscreen_hid)" || rc=$?
case "$rc" in
    1) die "$(profile_get model) board ${PROFILE_BOARD:-?} does not record touchscreen_hid.
    Find it in 'ls /sys/bus/hid/devices/' and add it to that board's section." ;;
    2) die "none of the touchscreens $(profile_get model) is known to ship is on
    this HID bus. Looked for: $(profile_get touchscreen_hid)
    Either this unit has a different one, in which case please add it to the
    board section and open an issue, or the panel has no touchscreen." ;;
esac

HID_VID="0x${HID_ID%%:*}"
HID_PID="0x${HID_ID##*:}"
# sysfs spells HID device names in upper case: 0018:2808:5662.0001
HID_SYSFS="${HID_ID^^}"

# Which directory under this fix describes the machine in front of us. The
# layout mirrors the profile: patch/micmute/<model>/<board>/, so the two words
# the profile used to identify this machine are the two words that name the
# directory. See lib/variant.sh.
variant_find "$SCRIPT_DIR" || die \
    "this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
    Covered: $(variant_known "$SCRIPT_DIR")

    The fixup rewrites one vendor usage page in one chip's report descriptor,
    so it cannot simply be pointed at a different touchscreen. To add this
    machine, create patch/micmute/$(printf '%s' "$(profile_get model)" | tr 'A-Z' 'a-z')/${PROFILE_BOARD:-BOARD}/
    with a recipe.conf; if its touchscreen is one already covered here, that is
    a recipe.conf with same_as= and nothing else. See patch/micmute/README.md."

# The profile said what the board ships and the directory says what it was
# written against; the bus says what is actually fitted. Disagreement is worth
# stopping for, because a program built for a chip that is not there loads and
# silently does nothing.
variant_check_device "$HID_ID" || die \
    "$(profile_get model) board ${PROFILE_BOARD:-?} is recorded with touchscreen
    $(recipe_get device), and this unit has $HID_ID on the bus.
    Nothing has been built. Please open an issue with the two ids: either this
    unit is unusual, or that board section is wrong."

SRC="${VARIANT_DIR}/$(recipe_get program)"
[[ -f "$SRC" ]] || die "${VARIANT_DIR}/recipe.conf names a program that is not there: $(recipe_get program)"
OBJ_NAME="$(basename "${SRC%.c}").o"

log "machine   = $(variant_note)"
log "touchscreen $HID_ID: $(recipe_get name)"
recipe_warn_unverified

legacy_move /usr/local/lib/honor-zqcp /usr/local/lib/honor

MISSING=()
for t in clang bpftool curl udev-hid-bpf udevadm; do
    command -v "$t" >/dev/null || MISSING+=("$t")
done
[[ -r /usr/include/bpf/bpf_helpers.h && -r /usr/include/bpf/bpf_tracing.h ]] \
    || MISSING+=(libbpf-dev)
if (( ${#MISSING[@]} )); then
    die "missing required tool(s): ${MISSING[*]}
    $(distro_pkg_hint "${MISSING[@]}")
    udev-hid-bpf is not packaged everywhere; if your distribution has no such
    package, build it from https://gitlab.freedesktop.org/libevdev/udev-hid-bpf"
fi

distro_kernel_config_has CONFIG_HID_BPF=y \
    || warn "CONFIG_HID_BPF=y not confirmed in this kernel's config - continuing anyway."

[[ -r /sys/kernel/btf/vmlinux ]] \
    || die "/sys/kernel/btf/vmlinux missing - the kernel needs CONFIG_DEBUG_INFO_BTF=y."

log "kernel  = ${KVER}"

# --- 2. fetch the kernel's BPF prog headers -----------------------------------
# The tag is resolved rather than spelled out from the release string: a 7.2.0
# kernel is v7.2 upstream, and getting that wrong is what took this fix off a
# working machine. See lib/ksrc.sh.
ksrc_resolve
log "headers = ${KSRC_TAG}"
for h in hid_bpf.h hid_bpf_helpers.h; do
    ksrc_fetch "drivers/hid/bpf/progs/${h}" "${WORK}/${h}"
done
if grep -q 'hid_report_descriptor_helpers.h' "${WORK}/hid_bpf_helpers.h"; then
    ksrc_fetch "drivers/hid/bpf/progs/hid_report_descriptor_helpers.h" \
               "${WORK}/hid_report_descriptor_helpers.h"
fi
bpftool btf dump file /sys/kernel/btf/vmlinux format c > "${WORK}/vmlinux.h"

# --- 3. build -----------------------------------------------------------------
# HID_VID and HID_PID are the recipe's contract with this installer: a program
# under a board directory compiles for whichever unit of that chip is fitted, and
# falls back to the ids it was written against when built by hand.
log "building ${OBJ_NAME}"
cp "$SRC" "${WORK}/"
CLANG_INCLUDES=(-I"$WORK")
for d in /usr/include/*-linux-gnu; do
    [[ -r "$d/asm/errno.h" ]] && { CLANG_INCLUDES+=("-I$d"); break; }
done
clang -O2 -g -target bpf -mcpu=v3 -D__TARGET_ARCH_x86 \
      -DHID_VID="${HID_VID}" -DHID_PID="${HID_PID}" \
      "${CLANG_INCLUDES[@]}" -Wno-missing-declarations \
      -c "${WORK}/$(basename "$SRC")" -o "${WORK}/${OBJ_NAME}" 2>&1 \
    | grep -vE "does not declare anything|^ *[0-9]+ \||^ +\^|In file included from|warnings? generated" \
    || true
[[ -f "${WORK}/${OBJ_NAME}" ]] || die "build produced no object"

udev-hid-bpf inspect "${WORK}/${OBJ_NAME}" >/dev/null \
    || die "udev-hid-bpf does not recognise the built object"

# --- 4. install ---------------------------------------------------------------
log "installing to ${INSTALL_DIR}/${OBJ_NAME}"
udev-hid-bpf install --force "${WORK}/${OBJ_NAME}" >/dev/null
udevadm control --reload

# --- 5. boot-time re-apply service --------------------------------------------
# The udev attach races with the hid-generic -> hid-multitouch handover at
# boot; see the comment at the top of hid-bpf-reapply.sh. This service fixes
# it up once the device has settled, and is a no-op when the race was won.
#
# What it has to look for is decided here, not written into the script: the
# script is installed as it is in the repository and reads this file, so it
# works on whatever touchscreen this machine turned out to have.
log "installing the boot-time re-apply service"
install -d -m 0755 /usr/local/lib/honor
install -m 0755 "${SCRIPT_DIR}/hid-bpf-reapply.sh" /usr/local/lib/honor/
cat > "$STATE_CONF" <<EOF
# Written by patch/micmute/install.sh. Read by
# /usr/local/lib/honor/hid-bpf-reapply.sh, which the boot-time re-apply
# service runs. Re-run that installer rather than editing this.
HID_ID=${HID_ID}
BPF_OBJECT=${INSTALL_DIR}/${OBJ_NAME}
EOF
chmod 0644 "$STATE_CONF"
install -m 0644 "${SCRIPT_DIR}/honor-hid-bpf-reapply.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable honor-hid-bpf-reapply.service >/dev/null 2>&1 \
    || warn "could not enable honor-hid-bpf-reapply.service"
# An enabled unit that cannot start is worse than no unit: it fails quietly at
# every boot and the phantom device comes back. Prove it runs now.
if ! systemctl start honor-hid-bpf-reapply.service; then
    systemctl status --no-pager honor-hid-bpf-reapply.service >&2 || true
    die "the re-apply service did not start. Without it the fixup is lost at
    the next boot whenever udev loses the attach race."
fi

# --- 6. apply to the live device and verify -----------------------------------
DEV="$(gate_hid_devpath "$HID_ID")" || DEV=""

if [[ -z "$DEV" ]]; then
    warn "No ${HID_ID} HID device present. The fixup is installed and will be"
    warn "applied when the device appears."
    exit 0
fi

# Detach first: re-attaching is what makes the kernel recompute the fixed
# report descriptor. A plain trigger does nothing when the program is already
# loaded but was attached too early to take effect.
log "applying to ${DEV##*/}"
udev-hid-bpf remove "$DEV" >/dev/null 2>&1 || true
sleep 1
udev-hid-bpf add "$DEV" "${INSTALL_DIR}/${OBJ_NAME}" >/dev/null 2>&1 \
    || die "udev-hid-bpf could not attach the program to the device"

# The device is re-probed asynchronously, so look for the state rather than
# waiting a fixed time and hoping.
phantom_path() {
    local d
    for d in /sys/class/input/input*; do
        [[ "$(cat "$d/name" 2>/dev/null)" == *"${HID_SYSFS}"*UNKNOWN* ]] && { printf '%s' "$d"; return 0; }
    done
    return 1
}
phantom_gone() { ! phantom_path >/dev/null; }
gate_wait_until 10 phantom_gone \
    || die "phantom device is still present: $(cat "$(phantom_path)/name")"

log "phantom KEY_MICMUTE device is gone."

cat <<EOF

════════════════════════════════════════════════════════════════════
  Installed.

  Touchscreen : ${HID_ID}, $(recipe_get name)
  BPF object  : ${INSTALL_DIR}/${OBJ_NAME}
  Read by     : ${STATE_CONF}
  Boot fixup  : honor-hid-bpf-reapply.service

  Nothing to redo after a kernel update.

  Uninstall:
      sudo systemctl disable --now honor-hid-bpf-reapply.service
      sudo rm ${INSTALL_DIR}/${OBJ_NAME} ${STATE_CONF} \\
              /etc/systemd/system/honor-hid-bpf-reapply.service \\
              /usr/local/lib/honor/hid-bpf-reapply.sh
      sudo systemctl daemon-reload && sudo udevadm control --reload
      reboot

  Verify (must print nothing):
      grep -l UNKNOWN /sys/class/input/input*/name | xargs -r grep -H ${HID_ID%%:*}
════════════════════════════════════════════════════════════════════
EOF
