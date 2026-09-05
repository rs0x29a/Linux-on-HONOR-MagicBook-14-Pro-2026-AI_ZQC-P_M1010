#!/usr/bin/env bash
# install-fan-hwmon.sh — build and install honor-ec-sensors, exposing the
# HONOR ZQC-P M1010 EC fan tachometers to lm_sensors / hwmon consumers.
#
# Background:
#   This machine has no fan RPM readout under Linux. The ACPI fan participant
#   (INTC10D6, hwmon "acpi_fan") registers a fan1_input but reading it returns
#   -ENODEV, because the firmware's _FST is a stub. The real tachometers live
#   in EC RAM as two 16-bit little-endian words:
#
#       0x2C/0x2D -> fan 0        0x2E/0x2F -> fan 1
#
#   Measured on this unit: ~2280 / ~2000 rpm at 48 degC idle, and 3656 / 3276
#   rpm at 89 degC under a sustained compile. The same offsets were confirmed
#   independently on the sibling FMB-P (colorcube PR #21). Note this corrects
#   an earlier reading of these bytes as "PWM duty + status flag" — the DSDT
#   splits each word into two named 8-bit fields (FA0L/FA0R), which is what
#   caused the confusion.
#
#   READ-ONLY, deliberately. Fan speed on this machine is EC-autonomous and
#   cannot be driven from the OS:
#     * SFNS (manual fan duty via WMI) is gated on the EC's MFGM master flag,
#       which no AML path ever sets;
#     * the DPTF fan participant TFN1 (/sys/class/thermal/cooling_device0,
#       51 states) accepts cur_state writes but the EC ignores them —
#       verified: 0 -> 50 produced no tachometer change at all.
#   So this module reports; it does not control. See README for the full
#   discussion of why the fans feel "lazy" versus Windows PC Manager.
#
# Reruns are safe. With dkms the module is rebuilt automatically on kernel
# updates; without dkms you must re-run this after every kernel update.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

MODNAME="honor-ec-sensors"
MODVER="1.0"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Override with KVER=... to build for a kernel other than the running one -
# needed when a kernel update is installed but not yet booted, since the
# headers for the running kernel are gone at that point.
KVER="${KVER:-$(uname -r)}"
KDIR="/lib/modules/${KVER}/build"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. is this fix meant for this machine ------------------------------------
# EC offsets are model-specific driver knowledge with no firmware method behind
# them, so this is a tier B fix: it needs a profile somebody has verified.
source "${SRC_DIR}/../../lib/gate.sh"
honor_gate fan

# The offsets are recorded in one place, the board section of the device
# profile, and handed to the module as parameters. They used to live a second
# time in the driver's DMI table, which meant a machine could be described in
# devices/ and still read another board's registers, or the two could drift
# apart with nothing to notice.
#
# The driver keeps a built-in default for the one board it was measured on, so
# a bare modprobe still works there, but this installer never relies on it.
variant_find "$SRC_DIR" || die \
    "this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
    Covered: $(variant_known "$SRC_DIR")"
log "machine  = $(variant_note)"
EC_FAN0="$(recipe_param ec_fan0)" || die \
    "patch/fan/${VARIANT_FOR}/recipe.conf does not record ec_fan0.
    The tachometer offsets have to be read out of that machine's DSDT before
    this can run: see patch/fan/README.md."
EC_FAN1="$(recipe_param ec_fan1)" || die \
    "patch/fan/${VARIANT_FOR}/recipe.conf records ec_fan0 but not ec_fan1."
for _o in "$EC_FAN0" "$EC_FAN1"; do
    [[ "$_o" =~ ^0[xX][0-9a-fA-F]{1,2}$ ]] || die \
        "ec_fan0/ec_fan1 must look like 0x2c; got '$_o'."
done
log "fan tachometers at ${EC_FAN0} and ${EC_FAN1} (board ${PROFILE_BOARD:-?})"

# The module used to be called honor-zqcp-hwmon. Leaving the old one installed
# would mean two drivers racing for the same EC offsets.
# Unload first: once dkms has removed the module, modprobe can no longer
# resolve the name and the stale copy would stay resident until a reboot.
# rmmod works on the loaded module regardless of what is left on disk.
modprobe -r honor-zqcp-hwmon 2>/dev/null || rmmod honor_zqcp_hwmon 2>/dev/null || true
if command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null | grep -q '^honor-zqcp-hwmon'; then
    dkms remove -m honor-zqcp-hwmon -v 1.0 --all >/dev/null 2>&1 || true
    log "removed the pre-rename DKMS module honor-zqcp-hwmon"
fi
legacy_drop /usr/src/honor-zqcp-hwmon-1.0 \
            /etc/modules-load.d/honor-zqcp-hwmon.conf
for _old in /usr/lib/modules/*/updates/honor-zqcp-hwmon.ko*; do
    [[ -e "$_old" ]] && legacy_drop "$_old"
done

# --- 2. kernel headers --------------------------------------------------------
if [[ ! -d "$KDIR" ]]; then
    # Very common case on a rolling distro: a kernel update is installed but
    # not yet booted, so the running kernel's headers package has already been
    # replaced. Detect that and point at the installed kernel instead of
    # blindly pulling in some unrelated -headers package.
    OTHER=""
    for d in /usr/lib/modules/*/; do
        [[ -e "${d}build" ]] || continue
        OTHER+=" $(basename "$d")"
    done
    if [[ -n "$OTHER" ]]; then
        warn "No headers for the running kernel ($KVER)."
        warn "Kernels that DO have headers:${OTHER}"
        warn ""
        warn "If one of those is a newer version of the same kernel, you have a"
        warn "pending reboot. Either reboot and re-run this script, or build for"
        warn "the installed kernel now so it is ready after the reboot:"
        warn ""
        warn "    sudo KVER=<version-from-the-list-above> bash \$0"
        die "Refusing to guess which kernel you meant."
    fi

    log "Kernel headers missing for $KVER — installing"
    HDR_PKG="$(distro_kernel_headers_pkg "$KVER")"
    [[ -n "$HDR_PKG" ]] || die "Cannot work out which package provides headers
    for kernel $KVER. Install them by hand, then re-run."
    case "$(distro_family)" in
        arch)   distro_pkg_install "$HDR_PKG" base-devel ;;
        debian) distro_pkg_install "$HDR_PKG" build-essential ;;
        fedora) distro_pkg_install "$HDR_PKG" gcc make ;;
        *)      distro_pkg_install "$HDR_PKG" ;;
    esac || die "Install kernel headers for $KVER yourself, then re-run."
fi
[[ -d "$KDIR" ]] || die "Kernel headers still missing at $KDIR"
log "Kernel headers present for $KVER"

# --- 3. install via dkms if available, else plain out-of-tree build -----------
if command -v dkms >/dev/null 2>&1; then
    DEST="/usr/src/${MODNAME}-${MODVER}"
    log "Installing via DKMS to $DEST"
    REGISTERED=0
    dkms status 2>/dev/null | grep -q "^${MODNAME}/${MODVER}" && REGISTERED=1
    rm -rf "$DEST"
    install -d "$DEST"
    install -m 644 "$SRC_DIR/honor-ec-sensors.c" "$SRC_DIR/Makefile" \
                   "$SRC_DIR/dkms.conf" "$DEST/"
    # -k is required: dkms otherwise targets the running kernel, which is the
    # wrong one when we are pre-building for a not-yet-booted kernel update.
    if (( ! REGISTERED )); then
        dkms add -m "$MODNAME" -v "$MODVER"
    fi
    dkms remove  -m "$MODNAME" -v "$MODVER" -k "$KVER" >/dev/null 2>&1 || true
    dkms build   -m "$MODNAME" -v "$MODVER" -k "$KVER"
    dkms install -m "$MODNAME" -v "$MODVER" -k "$KVER"
else
    warn "dkms not installed — building out-of-tree. You will need to re-run
    this script after every kernel update. Install dkms to avoid that."
    WORK=$(mktemp -d /tmp/honor-fan-XXXXXX)
    trap 'rm -rf "$WORK"' EXIT
    cp "$SRC_DIR/honor-ec-sensors.c" "$SRC_DIR/Makefile" "$WORK/"
    # A clang-built kernel puts clang-only flags in its Makefiles, so gcc
    # chokes on -mllvm. Match whatever built the kernel.
    MAKEVARS=()
    if distro_kernel_config_has CONFIG_CC_IS_CLANG=y "$KVER"; then
        MAKEVARS=(LLVM=1 LLVM_IAS=1)
    fi
    make -C "$KDIR" M="$WORK" "${MAKEVARS[@]}" modules >/dev/null || die "build failed"
    install -d "/lib/modules/${KVER}/updates"
    install -m 644 "$WORK/${MODNAME}.ko" "/lib/modules/${KVER}/updates/"
    depmod -a "$KVER"
fi

# --- 4. load + verify ---------------------------------------------------------
echo "${MODNAME}" > /etc/modules-load.d/honor-ec-sensors.conf
log "Enabled at boot via /etc/modules-load.d/honor-ec-sensors.conf"

# The offsets travel with the module rather than being compiled into it, so the
# boot-time load gets the same ones this run did.
cat > /etc/modprobe.d/honor-ec-sensors.conf <<EOF
# Written by patch/fan/install.sh from the [board ${PROFILE_BOARD:-?}] section
# of devices/$(basename "${DETECT_PROFILE:-${HONOR_PROFILE:-?}}").
# Re-run that installer rather than editing this: the offsets belong to the
# device profile, and this file is a copy of what it says.
options ${MODNAME} fan0=${EC_FAN0} fan1=${EC_FAN1}
EOF
chmod 0644 /etc/modprobe.d/honor-ec-sensors.conf

if [[ "$KVER" != "$(uname -r)" ]]; then
    log "Built for $KVER, which is not the running kernel ($(uname -r))."
    log "It will load automatically after you reboot into $KVER. Nothing else to do."
    exit 0
fi

modprobe -r "$MODNAME" 2>/dev/null || true
modprobe "$MODNAME" || die "modprobe failed — see 'dmesg | tail'"

FOUND=""
for d in /sys/class/hwmon/hwmon*; do
    [[ "$(cat "$d/name" 2>/dev/null)" == "honor_ec" ]] || continue
    FOUND="$d"
    break
done

if [[ -z "$FOUND" ]]; then
    die "Module loaded but no honor_ec hwmon node appeared. Check 'dmesg | tail'."
fi

log "hwmon node: $FOUND"
for f in "$FOUND"/fan*_input; do
    lbl_file="${f%_input}_label"
    printf '    %-12s %s rpm\n' \
        "$(cat "$lbl_file" 2>/dev/null || basename "$f")" "$(cat "$f")"
done

cat <<'EOF'

Done. Fan speeds now show up in:

    sensors                # lm_sensors, under "honor_ec-isa-0000"
    btop / KDE sensors / GNOME extensions — anything reading hwmon

Remember: this is a read-only tachometer. The EC owns the fan curve and
ignores every OS-side control path on this machine — see patch/fan/README.md
for the measured fan behaviour and which control paths were tested.

EOF
