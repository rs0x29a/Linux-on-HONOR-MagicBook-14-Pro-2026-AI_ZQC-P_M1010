#!/usr/bin/env bash
# Build and install the HID-BPF program that turns the touchpad's left-edge
# slide into brightness keys.
#
# See README.md in this directory for what the gesture actually sends and why
# a report descriptor fixup is not enough.
#
# Nothing here is tied to one laptop. The touchpad id comes from the board
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
KVER="$(uname -r)"
WORK=$(mktemp -d /var/tmp/honor-edge-XXXXXX)

trap 'rm -rf "$WORK"' EXIT

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. prerequisites ---------------------------------------------------------
# Tier A: the program is bound to one HID id, so on a machine without that
# touchpad udev-hid-bpf simply never attaches it.
source "${SCRIPT_DIR}/../../lib/gate.sh"
honor_gate touchpad-edge

# The profile lists what the board is known to ship; go and see which of those
# is actually here.
rc=0; HID_ID="$(gate_probe_hid touchpad_hid)" || rc=$?
case "$rc" in
    1) die "$(profile_get model) board ${PROFILE_BOARD:-?} does not record touchpad_hid.
    Find it in 'ls /sys/bus/hid/devices/' and add it to that board's section." ;;
    2) die "none of the touchpads $(profile_get model) is known to ship is on
    this HID bus. Looked for: $(profile_get touchpad_hid)" ;;
esac
HID_VID="0x${HID_ID%%:*}"
HID_PID="0x${HID_ID##*:}"

# patch/touchpad-edge/<model>/<board>/, the same two words the profile used to
# identify this machine. See lib/variant.sh.
variant_find "$SCRIPT_DIR" || die \
    "this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
    Covered: $(variant_known "$SCRIPT_DIR")

    The gesture is reported on a vendor collection whose byte layout belongs to
    one chip, so the program cannot simply be pointed at another touchpad. See
    patch/touchpad-edge/README.md for what a new directory has to contain."

variant_check_device "$HID_ID" || die \
    "$(profile_get model) board ${PROFILE_BOARD:-?} is recorded with touchpad
    $(recipe_get device), and this unit has $HID_ID on the bus.
    Nothing has been built. Please open an issue with the two ids."

SRC="${VARIANT_DIR}/$(recipe_get program)"
[[ -f "$SRC" ]] || die "${VARIANT_DIR}/recipe.conf names a program that is not there: $(recipe_get program)"
OBJ_NAME="$(basename "${SRC%.c}").o"
# What `udev-hid-bpf list-loaded` calls the program: the object's base name with
# dashes turned into underscores.
PROG_TAG="$(basename "${OBJ_NAME%%.*}" | tr '-' '_')"

log "machine  = $(variant_note)"
log "touchpad $HID_ID: $(recipe_get name)"
recipe_warn_unverified

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

# hid_bpf_try_input_report() is what makes this work without a daemon. It is
# the non-sleepable injection kfunc, so it can be called from the device event
# hook; the sleepable hid_bpf_input_report() cannot.
grep -qa 'hid_bpf_try_input_report' /sys/kernel/btf/vmlinux \
    || warn "hid_bpf_try_input_report not found in the kernel BTF.
    On a kernel without it the program will fail to load."

log "kernel  = ${KVER}"

# --- 2. fetch the kernel's BPF prog headers -----------------------------------
# hid_bpf_helpers.h includes hid_report_descriptor_helpers.h, so all three are
# needed even though this program does not touch the descriptor.
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

# --- 5. apply to the live device ----------------------------------------------
DEV="$(gate_hid_devpath "$HID_ID")" || DEV=""

if [[ -z "$DEV" ]]; then
    warn "No $HID_ID touchpad present. The program is installed and will be"
    warn "attached when the device appears."
    exit 0
fi

log "attaching to ${DEV##*/}"
udev-hid-bpf remove "$DEV" >/dev/null 2>&1 || true
sleep 1
udev-hid-bpf add "$DEV" "${INSTALL_DIR}/${OBJ_NAME}" >/dev/null 2>&1 \
    || die "udev-hid-bpf could not attach the program to the device"

edge_attached() {
    udev-hid-bpf list-loaded 2>/dev/null | grep -q "$PROG_TAG" \
        || bpftool prog show 2>/dev/null | grep -q "$PROG_TAG"
}
gate_wait_until 10 edge_attached \
    || die "the program is not attached to the device"

log "attached"

cat <<EOF

════════════════════════════════════════════════════════════════════
  Installed.

  Touchpad   : ${HID_ID}, $(recipe_get name)
  BPF object : ${INSTALL_DIR}/${OBJ_NAME}

  Slide along the LEFT edge of the touchpad to change brightness.
  The right edge already changes volume through the EC and is untouched.

  Nothing to redo after a kernel update.

  Verify:
      sudo bpftool prog show | grep ${PROG_TAG}
      sudo evtest /dev/input/event\$(...)   # Consumer Control device
      # or simply watch the value while sliding:
      watch -n0.2 cat /sys/class/backlight/intel_backlight/brightness

  Uninstall:
      sudo rm ${INSTALL_DIR}/${OBJ_NAME}
      sudo udevadm control --reload
      reboot
════════════════════════════════════════════════════════════════════
EOF
