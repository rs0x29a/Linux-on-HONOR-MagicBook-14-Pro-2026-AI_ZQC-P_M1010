#!/usr/bin/env bash
# Make the battery charge limit actually take effect.
#
# The limit is already exposed by the in-tree huawei-wmi driver and GNOME and
# KDE will happily set it. It just does not work, because the EC ignores any
# pair that is not one of the presets HONOR PC Manager offers. See README.md.
#
#   sudo bash install.sh                    # the model's default preset
#   sudo CHARGE_PRESET="40 70" bash install.sh
#   sudo CHARGE_PRESET="0 100" bash install.sh   # remove the limit
#
# Reruns are safe.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE=/sys/devices/platform/huawei-wmi/charge_control_thresholds
LIB_DIR=/usr/local/lib/honor
CONF=/etc/honor-battery.conf

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. is this fix meant for this machine ------------------------------------
# Tier B: which pairs the EC arms for is a property of that model's EC firmware.
# A wrong pair is harmless, it is simply ignored, but then the limit silently
# does nothing, which is exactly the problem this fix exists to solve.
source "${SCRIPT_DIR}/../../lib/gate.sh"
honor_gate battery

variant_find "$SCRIPT_DIR" || die \
    "this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
    Covered: $(variant_known "$SCRIPT_DIR")"
log "machine: $(variant_note)"
PRESETS="$(recipe_param presets)" || die \
    "patch/battery/${VARIANT_FOR}/recipe.conf does not record presets, so there
    is no way to know which pairs this EC enforces. Find them the way README.md
    describes and write them there."

[[ -e "$NODE" ]] || die "$NODE does not exist.
    The in-tree huawei-wmi driver provides it; check that the module is loaded
    (modprobe huawei-wmi) and that this machine exposes the WMI interface."

# Existing is not the same as writable. sysfs can be read-only (a container, a
# read-only root, some lockdown configurations), and without this the failure is
# a bare 'Read-only file system' from the redirection on line 69 instead of
# something anybody can act on.
[[ -w "$NODE" ]] || die "$NODE exists but is not writable.
    sysfs is mounted read-only here, or something is blocking the write.
    Nothing has been changed."

# --- 2. pick a preset ---------------------------------------------------------
DEFAULT_PRESET="${PRESETS#* }"; DEFAULT_PRESET="${DEFAULT_PRESET%% *}"   # the middle one
CHARGE_PRESET="${CHARGE_PRESET:-${DEFAULT_PRESET//-/ }}"

# "0 100" is the documented way to disarm, so it is allowed even though it is
# not in the preset list.
if [[ "$CHARGE_PRESET" != "0 100" ]]; then
    want="${CHARGE_PRESET// /-}"
    found=0
    for p in $PRESETS; do [[ "$p" == "$want" ]] && found=1; done
    if (( ! found )); then
        # Show them the way they have to be typed, one quoted pair per entry.
        pretty=""
        for p in $PRESETS; do pretty+=" \"${p%-*} ${p#*-}\""; done
        die "'$CHARGE_PRESET' is not a preset this EC enforces.
    Writing it would appear to work and then quietly do nothing.
    $(profile_get model) enforces only:${pretty}
    or \"0 100\" to remove the limit."
    fi
fi
log "preset: $CHARGE_PRESET"

# --- 3. apply and check that the EC armed itself ------------------------------
# The same functions the boot/resume unit runs: write the pair, read EC 0x85,
# and if the EC stored the pair without arming (the M1020 out of the box), ask
# again through \SBCM, which names the mode explicitly.
# shellcheck source=honor-battery-threshold.sh
source "${SCRIPT_DIR}/honor-battery-threshold.sh"
apply_preset "$CHARGE_PRESET"
ARMED="$APPLIED_MODE"
log "wrote it: $(cat "$NODE")"

if [[ "$ARMED" == "unknown" ]]; then
    warn "could not read the EC to confirm the limit armed (ec_sys unavailable)."
    warn "The write went through; whether the EC honours it is unverified here."
elif [[ "$CHARGE_PRESET" == "0 100" ]]; then
    log "EC charge mode: ${ARMED} (0 = no limit, which is what was asked for)"
elif [[ "$ARMED" == "0" ]]; then
    if [[ -w "$WMI_DBG/arg" ]]; then
        warn "the EC did NOT arm itself (charge mode 0), not even through SBCM, so
    the limit is not in effect. Either the preset list in the profile is wrong
    for this machine, or this firmware wants a different pair."
    else
        warn "the EC did NOT arm itself (charge mode 0), so the limit is not in
    effect. The SBCM fallback needs $WMI_DBG, which this kernel does not
    expose (CONFIG_DEBUG_FS or the huawei-wmi debugfs hook is missing)."
    fi
elif [[ "$APPLIED_VIA" == sbcm ]]; then
    log "EC armed through SBCM: charge mode ${ARMED} (the sysfs write alone was ignored)"
else
    log "EC armed itself: charge mode ${ARMED}"
fi

# --- 4. make the desktop's own switch land on a pair the EC accepts -----------
# UPower takes the pair it writes from the CHARGE_LIMIT udev property, and
# upstream's 60-upower-battery.hwdb sets a catch-all 75,80 for every laptop.
# On this EC that pair is a dead letter, so the GNOME and KDE toggles appear to
# work and do nothing. Overriding the property is what makes them honest.
HWDB_SRC="${SCRIPT_DIR}/61-honor-battery-charge-limit.hwdb"
HWDB_DST=/etc/udev/hwdb.d/61-honor-battery-charge-limit.hwdb
if [[ -f "$HWDB_SRC" ]]; then
    # Keep the shipped rule in step with the preset actually chosen here.
    gate_hwdb_render "$HWDB_SRC" "$HWDB_DST" \
        "s|@HONOR_CHARGE_LIMIT@|${CHARGE_PRESET// /,}|g"
    if command -v systemd-hwdb >/dev/null; then
        systemd-hwdb update
        udevadm trigger --action=change /sys/class/power_supply/BAT* 2>/dev/null || true
        systemctl try-restart upower >/dev/null 2>&1 || true
        log "desktop switch now uses ${CHARGE_PRESET// /,} (via $HWDB_DST)"
    else
        warn "systemd-hwdb not found; $HWDB_DST installed but not compiled."
        warn "The desktop's own battery switch will keep writing its default pair."
    fi
fi

# --- 5. survive reboots and resume --------------------------------------------
# The EC keeps the pair across a reboot, but a desktop that manages the battery
# can overwrite it with a non-preset pair and silently disable the limit again,
# which is how most people end up here.
install -d -m 0755 "$LIB_DIR"
install -m 0755 "${SCRIPT_DIR}/honor-battery-threshold.sh" "${LIB_DIR}/"
install -m 0644 "${SCRIPT_DIR}/honor-battery-threshold.service" \
                "${SCRIPT_DIR}/honor-battery-threshold-resume.service" \
                /etc/systemd/system/

cat > "$CONF" <<EOF
# Written by patch/battery/install.sh.
# The EC only enforces the presets it knows; anything else is stored and
# ignored. For $(profile_get model) those are: $PRESETS
CHARGE_PRESET="$CHARGE_PRESET"
EOF
chmod 0644 "$CONF"

systemctl daemon-reload
systemctl enable --now honor-battery-threshold.service >/dev/null 2>&1 || \
    warn "could not enable honor-battery-threshold.service"
systemctl enable honor-battery-threshold-resume.service >/dev/null 2>&1 || true
log "installed $CONF and the re-apply units"

cat <<EOF

════════════════════════════════════════════════════════════════════
  Charge limit: $CHARGE_PRESET   (EC charge mode ${ARMED})

  The battery will not charge past the ceiling. If it is already above it,
  it stays there until it falls below the floor on its own; the limit is a
  charging limit, not a discharge command.

  Change it later:
      sudo CHARGE_PRESET="40 70" bash $0
      sudo CHARGE_PRESET="0 100" bash $0    # remove the limit

  Only these pairs work on $(profile_get model): $PRESETS
  Anything else is accepted by the driver, stored by the EC, and ignored.
  That is why the desktop's own battery-health slider does nothing here.
════════════════════════════════════════════════════════════════════
EOF
