#!/usr/bin/env bash
# apply_patch.sh — install every fix in this repository for the
# HONOR MagicBook Pro 14 AI (ZQC-P, model M1010).
#
# One run does the lot. Each step after the ACPI override is independent and
# only warns on failure, so a step that cannot build never blocks the rest.
#
# Optional steps can be skipped:
#   SKIP_OLED=1          leave the OLED backlight floor at the firmware value
#   SKIP_EDGE=1          leave the touchpad left-edge gesture dead
#   SKIP_FAN=1           no fan RPM readout
#   SKIP_FINGERPRINT=1   no libfprint rebuild (by far the slowest step)
#   WITH_CDCLK=1         rebuild xe.ko with the Panther Lake cdclk fix;
#                        off by default, it downloads the kernel source
#                        and compiles for a few minutes
#   VBT_MIN=<n>          backlight floor in n/255, default 12; measure yours
#                        with patch/oled-backlight/measure-floor.sh first
#
# Fixes:
#   1) Touchpad (Goodix TOPS0102 on I2C1) and touchscreen (FocalTech FTSC1000
#      on I2C2) not appearing — SSDT "I2C_DEVT" fails to load with
#      AE_AML_INTERNAL on stock firmware. Patched SSDT moves the offending
#      module-level GNUM() call into a Method (_INI), letting the table load
#      and exposing TPD0/TPL1 to Linux.
#   2) Internal keyboard quirks (key repeats / dropouts) — i8042.dumbkbd=1
#      kernel command line argument suppresses atkbd command sending
#      (see README for the trade-off with Caps Lock LED).
#   3) Analog 3.5mm-jack headset microphone unusable — PCI SSID 1ee7:209d
#      is missing from sound/hda/codecs/realtek/alc269.c quirk table.
#      Step [9/19] rebuilds snd-hda-codec-alc269.ko with the SND_PCI_QUIRK
#      entry our hardware needs (matches the existing HONOR BRB-X M1010
#      sibling); see patch/headset-mic/install.sh and the upstream patch
#      at patch/headset-mic/alc269-honor-zqc-p-m1010.patch.
#   4) PREVENTIVE — SOF DSP IPC4 copier stale-payload race on suspend/
#      resume. On Intel Panther Lake the IPC4 copier widget's
#      ipc_config_data buffer is cached at first ipc_prepare and reused;
#      on resume the host/link DMA channels are re-allocated with new
#      tags but the stale cached payload still gets sent to firmware,
#      producing a ChainDMA collision and DSP panic. Step [10/19] backports
#      the upstream fix (thesofproject/linux PR #5762 by @ujfalusi) and
#      installs the rebuilt snd-sof.ko in the modules updates/ overlay.
#      Note: on this specific HONOR ZQC-P unit the upstream race was
#      NOT reproducible (zero `DSP panic!` entries in journal across
#      six boots, and zero panics from a pavucontrol + rtcwake -m mem
#      ×3 repro). We ship it anyway because (a) the patch is a clean
#      upstream backport, (b) the workflow that triggers it is
#      application-driven and may surface later, and (c) it is
#      defensive — no behavioural change when the race doesn't fire.
#      See patch/sof-audio/install.sh and the patch file:
#      patch/sof-audio/0001-ASoC-SOF-ipc4-topology-Refresh-copier-IPC-payload-before-widget-setup.patch
#      Upstream tracking issue: thesofproject/sof#10700.
#   5) Microphone mutes and unmutes itself, mic-mute LED flickers.
#      The FocalTech FTSC1000 touchscreen (I2C HID 2808:5662) declares
#      a vendor HID collection on usage page 0xff01. That page is
#      HID_UP_HPVENDOR2 in the kernel, so hid-input maps usage
#      0xff010001 to KEY_MICMUTE with no vendor check, and the
#      collection becomes an input device whose only key is
#      KEY_MICMUTE. All 59 data bytes carry that usage and hid-input
#      sets EV_REP, so one vendor report leaves the key held down and
#      auto-repeating at ~30 Hz. Step [11/19] installs a HID-BPF
#      rdesc_fixup that rewrites the usage page to 0xff00, which
#      hid-input ignores. Touchscreen, touchpad and the real Fn+F7
#      (which arrives over WMI, not HID) are unaffected.
#      See patch/micmute/.
#   6) The OLED panel does not render its firmware-declared minimum
#      brightness evenly: the VBT says 6/255, which is 2.4% PWM duty, and
#      at that level the panel shows a colour cast and visible blotches.
#      Step [6/19] feeds the driver a VBT with the floor raised to
#      12/255, measured on two units. See patch/oled-backlight/.
#   7) A wide, faint, darker band follows the mouse pointer up and down
#      the screen. PSR2 selective update can only address a range of
#      scanlines, never a rectangle, so every partial update is full
#      width, and on this OLED the re-sent lines do not match the ones
#      the panel is still driving from its own buffer. Step [5/19] limits
#      PSR to PSR1, which has no partial updates. Confirmed by turning
#      PSR2 back on and watching the band return. See patch/psr-band/.
#   8) Since kernel 7.1.6 the screen is garbled during boot on Panther
#      Lake. The shared i915 display code masks a CDCLK_CTL pipe-select
#      field that display IP 30 no longer has, so the sanitization check
#      can never match and every driver load forces a full CDCLK PLL
#      restart while the panel is lit. Upstream commit 2ee8dbd880b1,
#      stable backport 1e9b961f9f45. The four-line upstream fix is not
#      merged anywhere yet, so step [7/19] rebuilds xe.ko with it.
#      OPT-IN, off unless WITH_CDCLK=1. See patch/cdclk-ptl/.
#   9) The internal panel is driven at 6 bits per colour with dithering.
#      Its link tops out at HBR2, which cannot carry 8 bpc at 3120x2080
#      120 Hz, and the driver is allowed to drop colour depth to make a
#      mode fit before it will consider compression. The panel supports
#      DSC, the firmware permits it, and forcing it gives 10 bpc with the
#      link less than half loaded. Step [7/19] builds the same xe.ko with
#      a patch that prefers compression over going below 8 bpc on eDP,
#      falling back to the old behaviour if DSC does not compute.
#      OPT-IN, off unless WITH_DSC=1. See patch/edp-dsc/.
#  10) Sliding along the left edge of the touchpad is a HONOR brightness
#      gesture that goes nowhere under Linux: it is reported on a vendor
#      HID collection that hid-input discards. Step [12/19] installs a
#      HID-BPF program that injects a real brightness key tap per gesture
#      report. The right edge (volume) reaches the OS through the EC as
#      ordinary key events and needs nothing. See patch/touchpad-edge/.
#  11) Fan tachometers are invisible: the ACPI fan participant's _FST is a
#      stub. Step [13/19] installs a small hwmon module that reads the EC
#      registers directly. Read-only, the EC owns the curve.
#      See patch/fan/.
#  12) The fingerprint reader (Goodix 27c6:6f94) is missing from
#      libfprint's id table. Step [14/19] rebuilds the package with two
#      lines added. See patch/fingerprint/.
#  13) The fixes in steps [9/19] and [10/19] live inside kernel modules that
#      a kernel package update replaces, and the fingerprint patch lives
#      in libfprint, which a libfprint update replaces. Step [19/19]
#      installs package-manager hooks that rebuild them automatically, so nothing
#      silently reverts. See patch/auto-rebuild/.
#
# Fn+F7 mic-mute already works out of the box on this hardware via the
# huawei-wmi driver (separate "Huawei WMI hotkeys" input device emits
# KEY_MICMUTE on every press; PipeWire toggles the source mute and the
# platform::micmute LED follows via the audio-micmute trigger). No
# keymap or udev/systemd plumbing is needed. See README for details.
#
# Targets: CachyOS / Arch-like systems with mkinitcpio + Limine.
# Must be run as root.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/patch"
TS=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/honor-fix-backup-$TS

req() { command -v "$1" >/dev/null || { echo "missing required tool: $1" >&2; exit 1; }; }
req install
req sed
req cp
# NOT req mkinitcpio. It is one of two ways to get an early CPIO in front of the
# initramfs, and the wrong one on Debian and Ubuntu; lib/distro.sh picks. It is
# also only needed at all by the ACPI override, which most profiles do not list.

#────────────────────────────────────────────────────────────────────────
# Identify the machine before touching it.
#
# Most of what follows was derived from one physical unit. Step [2/19] in
# particular installs an ACPI table dumped from that unit's firmware, and a
# foreign SSDT is not a fix that fails quietly, it is a machine that may not
# boot. So: no profile, no install.
#
# On a profile nobody has verified, only the fixes that cannot carry another
# machine's constants are offered, and only when asked for explicitly. See
# lib/profile.sh for what puts a fix in which tier.
#────────────────────────────────────────────────────────────────────────
source "$SCRIPT_DIR/lib/profile.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/distro.sh"

detect_profile "$SCRIPT_DIR/devices" && DETECT_RC=0 || DETECT_RC=$?

if (( DETECT_RC != 0 )); then
    cat >&2 <<EOF

This machine is $(detect_describe)
and no profile in devices/ describes it.

Refusing to continue. These installers carry values measured on one specific
laptop: an ACPI override built from its firmware, a PCI subsystem id for the
audio codec quirk, EC register offsets for the fan tachometers. Applied to
different hardware they do not simply fail, they misconfigure it.

If this is a HONOR MagicBook, please open an issue with a hardware dump. The
template lists the commands, all of them read-only:

    https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/new/choose

EOF
    exit 1
fi

MODEL="$(profile_get model)"
STATUS="$(profile_get status)"
# The fix installers gate themselves too, so that running one directly is just
# as safe. Passing the profile down means they do not repeat the detection or
# print the banner a second time.
export HONOR_PROFILE="$DETECT_PROFILE"
echo "Machine  : $(detect_describe)"
echo "Profile  : $MODEL ($(profile_get name)), status=$STATUS"

if [[ "$STATUS" != "verified" ]]; then
    if [[ "${ALLOW_UNVERIFIED:-0}" != "1" ]]; then
        cat >&2 <<EOF

The profile for $MODEL is marked '$STATUS', which means nobody has run these
fixes on that machine. Refusing to continue.

You can install the subset that cannot go wrong on unverified hardware, the
fixes that read their inputs off the running machine or match on a device id
and simply find nothing elsewhere:

    sudo ALLOW_UNVERIFIED=1 ./apply_patch.sh

Everything carrying model specific values stays disabled until somebody
verifies the profile and updates devices/$(basename "$DETECT_PROFILE").

EOF
        exit 1
    fi
    echo "           unverified profile, restricted to the fixes that derive their own inputs"
fi
echo

#────────────────────────────────────────────────────────────────────────
# Kernel preflight.
#
# Five of the steps below build a kernel module against the running kernel.
# They each check what they need, but they check it one at a time, so a machine
# with no headers fails four times with four different messages. Say it once,
# up front, and name the steps that will be affected.
#
# The usual cause is a rolling distribution: a kernel update is installed but
# not yet booted, so the running kernel's headers package has already been
# replaced by the new one's.
#────────────────────────────────────────────────────────────────────────
KVER_RUNNING="$(uname -r)"
echo "Kernel   : $KVER_RUNNING"

# `|| true`: distro_module_dir returns 1 when there is no module tree for the
# running kernel, and under `set -e` a failing command substitution in an
# assignment aborts the script — right before the block below whose whole
# purpose is to explain that situation.
KDIR_RUNNING="$(distro_module_dir "$KVER_RUNNING" 2>/dev/null || true)/build"
NEWEST=""
for d in /usr/lib/modules/*/ /lib/modules/*/; do
    [[ -e "${d}build/Makefile" ]] || continue
    k="$(basename "$d")"
    [[ -z "$NEWEST" ]] && NEWEST="$k"
    [[ "$(printf '%s\n%s\n' "$NEWEST" "$k" | sort -V | tail -1)" == "$k" ]] && NEWEST="$k"
done

MODULE_STEPS="[7/19] cdclk-ptl + edp-dsc, [9/19] headset-mic, [10/19] sof-audio, [13/19] fan, [16/19] hotkeys"

if [[ ! -e "${KDIR_RUNNING}/Makefile" ]]; then
    echo
    echo "  [warn] no kernel headers for the running kernel $KVER_RUNNING."
    if [[ -n "$NEWEST" && "$NEWEST" != "$KVER_RUNNING" ]]; then
        echo "         Headers are present for $NEWEST instead, which usually means a"
        echo "         kernel update is installed and waiting for a reboot."
        echo
        echo "         Either reboot first, or build for the installed kernel now so"
        echo "         it is ready afterwards:"
        echo "             sudo KVER=$NEWEST ./apply_patch.sh"
    else
        echo "         Install the headers package for it first."
    fi
    echo "         Without them these steps will fail: $MODULE_STEPS"
    echo
elif [[ -n "$NEWEST" && "$NEWEST" != "$KVER_RUNNING" ]]; then
    echo "  note   : $NEWEST is installed but $KVER_RUNNING is running."
    echo "           Modules are built for the running kernel. After you reboot,"
    echo "           re-run this, or install patch/auto-rebuild/ to have it done."
fi

# fix_enabled <name> -> 0 if this step should run.
# Three things have to agree: the profile says the model needs it, the trust
# tier allows it given the profile's status, and the user did not skip it.
fix_enabled() {
    local fix="$1"
    if ! profile_lists_fix "$fix"; then
        echo "    skipped — $MODEL does not list this fix as applicable"
        return 1
    fi
    if ! fix_allowed "$fix"; then
        echo "    skipped — tier ${FIX_TIER[$fix]} fix, needs a verified profile"
        return 1
    fi
    return 0
}

mkdir -p "$BACKUP"

#────────────────────────────────────────────────────────────────────────
# [1/19] Backup everything we are about to touch.
#────────────────────────────────────────────────────────────────────────
echo "[1/19] Backup → $BACKUP"
# Every path that any step below may edit, on any of the distributions this
# supports. Missing ones are not an error: an Arch machine has no
# /etc/default/grub and a Debian one has no /etc/mkinitcpio.conf.
for f in /etc/mkinitcpio.conf /etc/default/limine /etc/default/grub \
         /etc/kernel/cmdline /boot/limine.conf; do
    [[ -f "$f" ]] || continue
    cp -a "$f" "$BACKUP/$(basename "$f")"
    echo "    $f"
done
for d in /usr/lib/firmware/acpi /etc/initcpio/install; do
    [[ -d "$d" ]] || continue
    cp -a "$d" "$BACKUP/$(basename "$d")"
    echo "    $d/"
done
echo "    OK"

#────────────────────────────────────────────────────────────────────────
# [2/19] Install patched SSDT and mkinitcpio install hook.
#────────────────────────────────────────────────────────────────────────
echo "[2/19] Install patched SSDT + mkinitcpio hook"
ACPI_OK=1
fix_enabled acpi-override || ACPI_OK=0

# This is the one step that writes firmware into the boot path, so it gets a
# check beyond the profile gate, and the check is on the table itself rather
# than on the model.
#
# That distinction turned out to matter. The `I2C_DEVT` SSDT is byte-identical
# between ZQC-P (MagicBook Pro 14 2026) and XWC-P (MagicBook Pro 16 2026):
# same length 23708, same checksum, same OEM revision, and a line for line
# identical disassembly, verified against phreer/xwc-p-touchpad-ssdt-fix. So
# "is this the same machine" was the wrong question. "Is this the same table"
# is the right one, it is cheap to answer, and it is what actually decides
# whether the override is safe.
#
# Three outcomes:
#   live table == our stock table    -> install, whatever the model or BIOS
#   live table == our patched table  -> already installed, re-running is a no-op
#   anything else                    -> refuse. A different table means a
#                                       different machine or a BIOS that
#                                       rewrote it, and installing then risks
#                                       a machine that does not boot
if (( ACPI_OK )); then
    AML="$PATCH_DIR/acpi-override/SSDT27_TPD0.aml"
    AML_OEM=$(dd if="$AML" bs=1 skip=16 count=8 2>/dev/null | tr -d '\0 ')
    if [[ "$AML_OEM" != "I2C_DEVT" ]]; then
        echo "    [skip] $AML is not the expected table (OEM table id '$AML_OEM')."
        ACPI_OK=0
    fi
fi

# Find the live table by its OEM table id, not by file name: acpidump numbers
# the SSDTs by boot order and that number is not stable between machines.
acpi_live_table() {
    local f oem
    for f in /sys/firmware/acpi/tables/SSDT*; do
        [[ -r "$f" ]] || continue
        oem=$(dd if="$f" bs=1 skip=16 count=8 2>/dev/null | tr -d '\0 ')
        [[ "$oem" == "I2C_DEVT" ]] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

if (( ACPI_OK )); then
    STOCK_REF="$SCRIPT_DIR/dump/acpi/zqc-p/SSDT27_orig.aml"
    MD5_STOCK=$(md5sum "$STOCK_REF" 2>/dev/null | cut -d' ' -f1)
    MD5_PATCHED=$(md5sum "$AML" | cut -d' ' -f1)
    LIVE="$(acpi_live_table || true)"

    if [[ -z "$LIVE" ]]; then
        if ! compgen -G '/sys/firmware/acpi/tables/SSDT*' >/dev/null; then
            # Not the same statement at all: a container masks /sys/firmware,
            # and so do some hardened kernels. "Cannot look" must not be
            # reported as "looked and it is not there".
            echo "    [skip] cannot read /sys/firmware/acpi/tables, so the table this fix"
            echo "    replaces cannot be identified. Refusing rather than guessing."
        else
            echo "    [skip] no ACPI table with OEM table id I2C_DEVT on this machine."
            echo "    This fix is for the firmware bug in that table. Yours does not have it."
        fi
        ACPI_OK=0
    else
        MD5_LIVE=$(md5sum "$LIVE" | cut -d' ' -f1)
        if [[ "$MD5_LIVE" == "$MD5_PATCHED" ]]; then
            echo "    the override is already active (${MD5_LIVE:0:8}); re-running changes nothing"
        elif [[ -n "$MD5_STOCK" && "$MD5_LIVE" == "$MD5_STOCK" ]]; then
            echo "    firmware table matches the one this fix was built from (${MD5_LIVE:0:8})"
        else
            BIOS_NOW=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unknown)
            BIOS_WANT=$(profile_get verified_bios)
            cat <<EOF
    [skip] this machine's I2C_DEVT table is not the one this fix was built from.
        yours     ${MD5_LIVE}  ($(stat -c%s "$LIVE") bytes)
        expected  ${MD5_STOCK:-unknown}  ($(stat -c%s "$STOCK_REF" 2>/dev/null || echo ?) bytes)
    Your BIOS is ${BIOS_NOW}; the table on record came from ${BIOS_WANT}. Either a
    BIOS update rewrote it or this is a different machine. Installing anyway
    could stop it booting. Re-derive the fix from your own firmware, which is
    the same one line change: see docs/RESEARCH.md.
    FORCE_ACPI=1 installs regardless.
EOF
            [[ "${FORCE_ACPI:-0}" == "1" ]] || ACPI_OK=0
            [[ "${FORCE_ACPI:-0}" == "1" ]] && echo "    FORCE_ACPI=1 given, installing regardless."
        fi
    fi
fi

# Kernel lockdown has a check against initrd ACPI table overrides:
# acpi_table_initrd_init() calls security_locked_down(LOCKDOWN_ACPI_TABLES) and
# logs "kernel is locked down, ignoring table override". Whether it actually
# fires is not something this script can predict, and the evidence is mixed: a
# Fedora 44 machine on kernel 7.1.5 with Secure Boot on and the kernel locked
# down applied a HONOR I2C_DEVT override successfully (linux-hardware probe
# c33ebd2b1c). So this is a heads-up, not a refusal, and it names the line to
# look for afterwards.
if (( ACPI_OK )) && [[ -r /sys/kernel/security/lockdown ]] \
   && grep -qE '\[(integrity|confidentiality)\]' /sys/kernel/security/lockdown; then
    cat >&2 <<EOF
    [note] the kernel is locked down: $(cat /sys/kernel/security/lockdown)
           Some kernels refuse initrd ACPI table overrides in this state and say
           so in one line nobody looks for. After rebooting, check which of these
           two you got:
             journalctl -k -b | grep -iE "Table Upgrade: override|locked down"
           "Table Upgrade: override [SSDT- HONOR-I2C_DEVT]" means it worked.
           "kernel is locked down, ignoring table override" means it did not,
           and you need Secure Boot off or a kernel you signed yourself.
EOF
fi

ACPI_STYLE="$(distro_acpi_override_style || true)"
if (( ACPI_OK )); then
install -Dm0644 "$PATCH_DIR/acpi-override/SSDT27_TPD0.aml" \
                /usr/lib/firmware/acpi/SSDT27_TPD0.aml
echo "    /usr/lib/firmware/acpi/SSDT27_TPD0.aml"
case "$ACPI_STYLE" in
    mkinitcpio)
        install -Dm0755 "$PATCH_DIR/acpi-override/acpi_override.install" \
                        /etc/initcpio/install/acpi_override
        echo "    /etc/initcpio/install/acpi_override" ;;
    early-cpio)
        echo "    mechanism: early CPIO handed to GRUB (no mkinitcpio here)" ;;
    *)
        echo "    [skip] no way to put an early CPIO in front of the initramfs was found."
        echo "    The table is staged in /usr/lib/firmware/acpi/ and has to be wired in"
        echo "    by hand; see docs/INSTALL.md. Nothing else in this step ran."
        ACPI_OK=0 ;;
esac
fi

#────────────────────────────────────────────────────────────────────────
# [3/19] Put the override in front of the initramfs.
#
# Two mechanisms, picked by lib/distro.sh: an mkinitcpio install hook plus a
# HOOKS= entry on Arch, or a CPIO built here and given to GRUB as an additional
# initrd on Debian and Ubuntu. Same .aml either way.
#────────────────────────────────────────────────────────────────────────
echo "[3/19] Wire the override into the initramfs"
if (( ! ACPI_OK )); then
    echo "    skipped — goes with the ACPI override above"
elif [[ "$ACPI_STYLE" == early-cpio ]]; then
    # Debian and Ubuntu: build the CPIO and hand it to GRUB as an extra initrd.
    distro_acpi_override_install || ACPI_OK=0
else
if ! grep -qE '^HOOKS=.*\bacpi_override\b' /etc/mkinitcpio.conf; then
    # Insert after autodetect where there is one. A HOOKS= line without it is
    # unusual but legal, and the sed would then be a silent no-op: check rather
    # than announce success, because the result is an initramfs with no early
    # CPIO and a machine with no touchpad for no visible reason.
    sed -i 's/\bautodetect\b/autodetect acpi_override/' /etc/mkinitcpio.conf
    if ! grep -qE '^HOOKS=.*\bacpi_override\b' /etc/mkinitcpio.conf; then
        sed -i -E 's/^(HOOKS=[("'"'"']?)/\1acpi_override /' /etc/mkinitcpio.conf
    fi
    if grep -qE '^HOOKS=.*\bacpi_override\b' /etc/mkinitcpio.conf; then
        echo "    + acpi_override added to HOOKS"
    else
        echo "    [skip] could not add acpi_override to HOOKS= in /etc/mkinitcpio.conf."
        echo "    Add it yourself, right after autodetect, and re-run."
        ACPI_OK=0
    fi
else
    echo "    HOOKS already contain acpi_override — skipped"
fi
# Some older instructions put the table in FILES= instead, which does not work:
# FILES lands in the main compressed archive and the ACPI loader only reads the
# early CPIO. Drop just those paths, not the whole array, because FILES= is a
# list and somebody else's entries may be in it.
if grep -qE '^FILES=\(.*\/usr\/lib\/firmware\/acpi\/' /etc/mkinitcpio.conf; then
    sed -i -E 's@/usr/lib/firmware/acpi/[^ )"'"'"']*@@g' /etc/mkinitcpio.conf
    # tidy the double spaces that leaves inside the parentheses
    sed -i -E 's@^(FILES=\()[[:space:]]+@\1@; s@[[:space:]]+\)@)@; s@[[:space:]]{2,}@ @g' /etc/mkinitcpio.conf
    echo "    cleaned stale FILES= entry: $(grep -E '^FILES=' /etc/mkinitcpio.conf)"
fi
echo "    HOOKS=$(grep -E '^HOOKS=' /etc/mkinitcpio.conf)"
fi

#────────────────────────────────────────────────────────────────────────
# [4/19] Keep the internal keyboard usable. Older kernels need
# i8042.dumbkbd=1; kernels carrying the upstream atkbd quirk must have the
# parameter removed again so the Caps Lock LED can work.
#────────────────────────────────────────────────────────────────────────
echo "[4/19] Patch the kernel command line (i8042.dumbkbd=1)"

# Kernel versions in which the upstream atkbd_deactivate_fixup entry for this
# model shipped: the mainline release, and any stable series it was backported
# into, highest first. Empty means no entry exists upstream for that model yet.
# FMB-P also covers FMB-PM, because the kernel's DMI_MATCH is a substring test.
atkbd_quirk_since() {
    case "$1" in
        FMB-P|FMB-PM) printf '6.19' ;;
        BCC-N)        printf '7.1' ;;
        ZQC-P)        printf '7.2 7.1.10' ;;   # highest first, so the note names the right one
        *)            printf '' ;;
    esac
}

# 0 if $1 (a kernel release) is at least $2 (a version string).
kver_at_least() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$2" ]]
}

quirk_hit=""
for v in $(atkbd_quirk_since "$MODEL"); do
    kver_at_least "$(uname -r)" "$v" && { quirk_hit="$v"; break; }
done
if (( ! ACPI_OK )); then
    echo "    skipped — the keyboard workaround goes with the ACPI override"
elif [[ -n "$quirk_hit" ]]; then
    if distro_cmdline_remove 'i8042\.dumbkbd=1'; then
        echo "    upstream atkbd quirk detected ($quirk_hit); removed redundant i8042.dumbkbd=1"
    else
        echo "    no redundant i8042.dumbkbd=1 parameter found"
    fi
    cat <<EOF
    note: this kernel ($(uname -r)) carries the upstream atkbd quirk for $MODEL
          (available since $quirk_hit), so the Caps Lock LED should work.
EOF
elif distro_cmdline_add "i8042.dumbkbd=1"; then
    echo "    $(grep -hE 'CMDLINE' "$(distro_cmdline_file)" | head -1)"
else
    echo "    add i8042.dumbkbd=1 to your bootloader command line manually."
fi

#────────────────────────────────────────────────────────────────────────
# [5/19] Limit Panel Self Refresh to PSR1.
#
# PSR2 selective update can only address a range of scanlines, never a
# rectangle, so every partial update is a band the full width of the screen.
# Moving the pointer drags that band up and down with it, and on this OLED it
# is visible. PSR1 has no partial updates. See patch/psr-band/.
#
# This is a command line change like [4/19], so it runs here, before the single
# bootloader regeneration in [8/19], and passes REGEN=0 for the same reason.
#────────────────────────────────────────────────────────────────────────
echo "[5/19] Limit Panel Self Refresh to PSR1 (kernel parameter)"

if ! fix_enabled psr-band; then
    echo "    skipped — $MODEL does not list psr-band"
elif REGEN=0 bash "$PATCH_DIR/psr-band/install.sh"; then
    :
else
    echo "    FAILED — the moving band stays; everything else is unaffected."
    echo "    patch/psr-band/install.sh output above."
fi

#────────────────────────────────────────────────────────────────────────
# [6/19] Raise the OLED backlight floor through a patched VBT.
# The firmware declares a minimum of 6/255, which lands on 2.4% PWM duty,
# and this panel does not render that evenly: colour cast and blotches.
# Measured on two units, the first clean level is just under 4%; the
# installer defaults to 12/255 = 4.69%. It edits FILES= and the cmdline,
# so it runs before the single initramfs rebuild in [8/19].
# Set SKIP_OLED=1 to leave the backlight range alone, or VBT_MIN=<n> to
# override the floor after running patch/oled-backlight/measure-floor.sh.
#────────────────────────────────────────────────────────────────────────
echo "[6/19] Raise the OLED backlight minimum (patched VBT)"
if [[ "${SKIP_OLED:-0}" == "1" ]]; then
    echo "    skipped — SKIP_OLED=1"
elif ! fix_enabled oled-backlight; then
    :
elif REGEN=0 bash "$PATCH_DIR/oled-backlight/install.sh"; then
    echo "    OK"
else
    echo "    [warn] backlight fix failed — everything else still applies;"
    echo "    only the lowest brightness steps stay blotchy. Inspect"
    echo "    patch/oled-backlight/install.sh output above."
fi

#────────────────────────────────────────────────────────────────────────
# [7/19] Rebuild xe.ko with the Panther Lake CDCLK sanitization fix.
# Since 7.1.6 the shared i915 display code compares a CDCLK_CTL field that
# Panther Lake no longer has, never matches, and forces a full CDCLK PLL
# disable+enable while the panel is already lit by the GOP. The result is a
# corrupted image during boot. The upstream fix is merged to drm-intel-next
# and due in Linux 7.3, so on any kernel you can install today the module
# still has to be rebuilt locally.
# OPT-IN: this one downloads the distro kernel source (about 260 MB) and
# compiles for several minutes, and it becomes obsolete the moment the fix
# reaches your kernel. Enable it with WITH_CDCLK=1.
# It installs into modules updates/ and runs before the single initramfs
# rebuild in [8/19], because the early-KMS copy of xe.ko is the one that
# lights the panel.
#────────────────────────────────────────────────────────────────────────
echo "[7/19] Rebuild xe.ko with the patches that live inside it"

# One module, two patches, so one build. XE_SKIP keeps the two opt-ins
# separate: asking for the cdclk fix is not asking for the DSC preference.
XE_SKIP=""
[[ "${WITH_CDCLK:-0}" == "1" ]] || XE_SKIP="$XE_SKIP cdclk-ptl"
[[ "${WITH_DSC:-0}"   == "1" ]] || XE_SKIP="$XE_SKIP edp-dsc"
export XE_SKIP="${XE_SKIP# }"

if [[ "${WITH_CDCLK:-0}" != "1" && "${WITH_DSC:-0}" != "1" ]]; then
    echo "    skipped — both are opt-in because the build downloads the distro"
    echo "    kernel source (about 260 MB) and compiles for several minutes."
    echo "      WITH_CDCLK=1  boot-time screen corruption, patch/cdclk-ptl/"
    echo "      WITH_DSC=1    panel driven at 6 bpc, patch/edp-dsc/"
elif ! fix_enabled cdclk-ptl && ! fix_enabled edp-dsc; then
    :
# Either installer builds the same module and both are safe to call; the
# second one finds the work already done and says so.
elif { [[ "${WITH_CDCLK:-0}" == "1" ]] && fix_enabled cdclk-ptl \
         && REGEN=0 bash "$PATCH_DIR/cdclk-ptl/install.sh"; } \
     || { [[ "${WITH_DSC:-0}" == "1" ]] && fix_enabled edp-dsc \
         && REGEN=0 bash "$PATCH_DIR/edp-dsc/install.sh"; }; then
    echo "    OK"
else
    echo "    [warn] the xe.ko rebuild failed — everything else still applies."
    echo "    The boot-time glitch and the panel colour depth stay as they were."
    echo "    Inspect the installer output above."
fi

#────────────────────────────────────────────────────────────────────────
# [8/19] Rebuild the initramfs and regenerate the bootloader config.
#
# Both, and in that order. On Arch the two are usually the same command, so the
# second call is a no-op. On Debian and Ubuntu they are not: update-initramfs
# does not touch grub.cfg, and without update-grub neither the new command line
# nor the early ACPI CPIO from step 3 would take effect at the next boot.
#────────────────────────────────────────────────────────────────────────
echo "[8/19] Rebuild initramfs and bootloader config"
distro_initramfs_rebuild || echo "    [warn] rebuild the initramfs yourself before rebooting"
distro_bootloader_update || echo "    [warn] regenerate your bootloader config yourself before rebooting"

#────────────────────────────────────────────────────────────────────────
# [9/19] Build + install ALC256 codec quirk for the 3.5mm-jack headset mic.
# Fetches the running kernel's alc269.c from the upstream stable tree,
# adds SND_PCI_QUIRK(0x1ee7, 0x209d, "HONOR ZQC-P M1010", …) — pin 0x19
# is wired to the combo jack mic on this board, identical to the existing
# BRB-X M1010 sibling — and replaces /lib/modules/.../snd-hda-codec-alc269.ko.zst.
# Original is backed up to /root/snd-hda-codec-alc269.ko.zst.orig.
# The script is idempotent: if the in-tree module already carries the
# quirk (e.g. after upstream merge), it exits without rebuilding.
#────────────────────────────────────────────────────────────────────────
echo "[9/19] Apply ALC256 headset-mic quirk (snd-hda-codec-alc269 rebuild)"
if ! fix_enabled headset-mic; then
    :
elif bash "$PATCH_DIR/headset-mic/install.sh"; then
    echo "    OK"
else
    echo "    [warn] ALC256 quirk install failed — touchpad/touchscreen fix is"
    echo "    still applied; only the analog headset mic on the 3.5mm jack will"
    echo "    stay unavailable. Inspect patch/headset-mic/install.sh output above."
fi

#────────────────────────────────────────────────────────────────────────
# [10/19] Build + install SOF IPC4 copier-payload refresh patch
# (thesofproject/linux PR #5762 by @ujfalusi). Fetches the running
# kernel's sound/soc/sof/ tree from the upstream stable tree, applies the
# 33-line ipc4-topology.c fix, builds snd-sof.ko out-of-tree and drops
# the rebuild into /lib/modules/$KVER/updates/ as an overlay so the in-
# tree module is left untouched. Original snd-sof.ko.zst is backed up to
# /root/snd-sof.ko.zst.orig.
# The script is idempotent: if upstream has already merged the fix (or
# our overlay is already in place), it exits without rebuilding.
# Skipped silently if kernel lockdown / module.sig_enforce blocks
# unsigned modules — see patch/sof-audio/install.sh for details.
#────────────────────────────────────────────────────────────────────────
echo "[10/19] Apply SOF IPC4 copier-payload refresh (snd-sof rebuild)"
if ! fix_enabled sof-audio; then
    :
elif bash "$PATCH_DIR/sof-audio/install.sh"; then
    echo "    OK"
else
    echo "    [warn] SOF IPC4 fix install failed — earlier steps are still"
    echo "    applied; only the Fn+F7 mic-mute stability after suspend/resume"
    echo "    on Panther Lake will be affected. Inspect"
    echo "    patch/sof-audio/install.sh output above."
fi

#────────────────────────────────────────────────────────────────────────
# [11/19] Build + install the HID-BPF phantom-KEY_MICMUTE fixup.
# Builds patch/micmute/honor-ftsc1000-micmute.bpf.c against the running
# kernel's BTF and installs it through udev-hid-bpf into
# /etc/udev-hid-bpf/ with a matching udev rule. Nothing has to be
# repeated after a kernel update. Requires clang, bpftool and
# udev-hid-bpf.
#────────────────────────────────────────────────────────────────────────
echo "[11/19] Remove phantom KEY_MICMUTE device (HID-BPF descriptor fixup)"
if ! fix_enabled micmute; then
    :
elif bash "$PATCH_DIR/micmute/install.sh"; then
    echo "    OK"
else
    echo "    [warn] HID-BPF fixup install failed — earlier steps are still"
    echo "    applied; only the self-toggling microphone will be affected."
    echo "    Inspect patch/micmute/install.sh output above."
fi

#────────────────────────────────────────────────────────────────────────
# [12/19] Build + install the HID-BPF program that turns the touchpad's
# left-edge slide into brightness keys. The gesture is reported on a
# vendor collection hid-input ignores; the program injects a consumer
# key tap per gesture report. The right edge (volume) goes through the
# EC and needs nothing. Set SKIP_EDGE=1 to skip.
#────────────────────────────────────────────────────────────────────────
echo "[12/19] Touchpad left-edge slide → brightness (HID-BPF)"
if ! fix_enabled touchpad-edge; then
    :
elif [[ "${SKIP_EDGE:-0}" == "1" ]]; then
    echo "    skipped — SKIP_EDGE=1"
elif bash "$PATCH_DIR/touchpad-edge/install.sh" >/dev/null; then
    echo "    OK"
else
    echo "    [warn] edge-gesture fix failed — earlier steps still apply;"
    echo "    only the left-edge brightness gesture will stay dead."
fi

#────────────────────────────────────────────────────────────────────────
# [13/19] Build + install honor-ec-sensors, which exposes the EC fan
# tachometers to lm_sensors. Read-only: fan speed on this machine is
# EC-autonomous and cannot be driven from the OS. Uses DKMS when
# available, so kernel updates rebuild it. Set SKIP_FAN=1 to skip.
#────────────────────────────────────────────────────────────────────────
echo "[13/19] Fan RPM readout (honor-ec-sensors)"
if ! fix_enabled fan; then
    :
elif [[ "${SKIP_FAN:-0}" == "1" ]]; then
    echo "    skipped — SKIP_FAN=1"
elif bash "$PATCH_DIR/fan/install.sh" >/dev/null; then
    echo "    OK"
else
    echo "    [warn] fan sensor module failed to build — earlier steps still"
    echo "    apply; only the RPM readout will be missing."
fi

echo "[13b/19] Fan curve controller"
if [[ -z "${FAN_CURVE:-}" ]]; then
    echo "    skipped — set FAN_CURVE=0xAA or 0xAB to enable the safe early-engagement curve"
elif ! fix_enabled fan-curve; then
    :
elif bash "$PATCH_DIR/fan-curve/install.sh"; then
    echo "    OK — thermal failsafe returns the EC to stock 0xA0"
else
    echo "    [warn] fan curve controller failed — stock EC curve remains active"
fi

#────────────────────────────────────────────────────────────────────────
# [14/19] Rebuild libfprint with the Goodix 27c6:6f94 id added, as a
# pacman-owned package so it does not conflict on the next update. This
# is the slowest step by far: it downloads the libfprint sources and
# builds them. Set SKIP_FINGERPRINT=1 to skip.
#────────────────────────────────────────────────────────────────────────
echo "[14/19] Fingerprint reader (libfprint id patch)"
if ! fix_enabled fingerprint; then
    :
elif [[ "${SKIP_FINGERPRINT:-0}" == "1" ]]; then
    echo "    skipped — SKIP_FINGERPRINT=1"
elif ! command -v makepkg >/dev/null; then
    echo "    skipped — makepkg not found, not a pacman system"
elif bash "$PATCH_DIR/fingerprint/install.sh"; then
    echo "    OK"
else
    echo "    [warn] libfprint rebuild failed — earlier steps still apply;"
    echo "    only the fingerprint reader will stay unusable. Inspect"
    echo "    patch/fingerprint/install.sh output above."
fi

#────────────────────────────────────────────────────────────────────────
# [15/19] Make the battery charge limit actually take effect.
# huawei-wmi already exposes the limit and the desktop already sets it. It just
# does nothing: the EC only enforces the pairs HONOR PC Manager offers and
# silently ignores every other one, so a perfectly reasonable 75-80 leaves the
# machine charging to 100%. See patch/battery/.
# CHARGE_PRESET="40 70" picks a different preset, "0 100" removes the limit.
#────────────────────────────────────────────────────────────────────────
echo "[15/19] Battery charge limit (EC preset)"
if ! fix_enabled battery; then
    :
elif bash "$PATCH_DIR/battery/install.sh" >/dev/null; then
    echo "    OK — $(grep -oE '"'"'[0-9]+ [0-9]+'"'"' /etc/honor-battery.conf 2>/dev/null | head -1)"
else
    echo "    [warn] battery limit failed — everything else still applies."
fi

#────────────────────────────────────────────────────────────────────────
# [16/19] Map the HONOR hotkey codes the in-tree huawei-wmi does not know.
# The keys reach the driver and die there as "Unknown key pressed". A udev
# hwdb rule cannot help: sparse_keymap rejects scancodes it has never heard of,
# so this has to be a driver change. See patch/hotkeys/.
#────────────────────────────────────────────────────────────────────────
echo "[16/19] Fn hotkeys (huawei-wmi keymap)"
if ! fix_enabled hotkeys; then
    :
elif bash "$PATCH_DIR/hotkeys/install.sh" >/dev/null; then
    echo "    OK"
else
    echo "    [warn] hotkey mapping failed — the affected Fn keys stay dead."
fi

#────────────────────────────────────────────────────────────────────────
# [17/19] Give those hotkeys something to do.
# Step 15 makes the keys arrive as key events; that is where the kernel's job
# ends. KEY_PROG1 means "programmable key one" and no desktop binds it, and
# nothing turns the camera key into a camera that is actually off. A small
# service does both, so it works the same under GNOME, KDE or nothing.
#────────────────────────────────────────────────────────────────────────
echo "[17/19] Hotkey actions (performance key, camera key)"
if ! fix_enabled hotkey-actions; then
    :
elif bash "$PATCH_DIR/hotkey-actions/install.sh" >/dev/null; then
    echo "    OK"
else
    echo "    [warn] hotkey actions failed — the keys still arrive, nothing acts on them."
fi

#────────────────────────────────────────────────────────────────────────
# [18/19] Expose the EC-backed keyboard backlight.
# The ZQC-P's WMI LED path may exist but returns -ENODEV on writes. The
# dedicated driver uses the measured KBBL EC field and is DMI-gated.
#────────────────────────────────────────────────────────────────────────
echo "[18/19] Keyboard backlight (EC LED)"
if ! fix_enabled keyboard-backlight; then
    :
elif bash "$PATCH_DIR/keyboard-backlight/install.sh" >/dev/null; then
    echo "    OK"
else
    echo "    [warn] keyboard backlight failed — see patch/keyboard-backlight/README.md"
fi

#────────────────────────────────────────────────────────────────────────
# [19/19] Install package-manager hooks that re-apply the fixes a package update
# would otherwise revert: a kernel update replaces the modules patched in
# steps [9/19] and [10/19], and a libfprint update drops the fingerprint
# patch. The hooks rebuild them automatically. Arch-like systems only.
#────────────────────────────────────────────────────────────────────────
echo "[19/19] Install the auto-rebuild package-manager hooks"
if ! fix_enabled auto-rebuild; then
    :
elif command -v pacman >/dev/null && bash "$PATCH_DIR/auto-rebuild/install.sh" >/dev/null; then
    echo "    OK — kernel and libfprint updates will re-apply the fixes"
elif ! command -v pacman >/dev/null; then
    echo "    skipped — not a pacman system. Re-run patch/headset-mic/install.sh"
    echo "    and patch/sof-audio/install.sh after every kernel update."
else
    echo "    [warn] hook install failed — the fixes still work, but a kernel"
    echo "    update will revert steps [9/19] and [10/19] until you re-run them."
    echo "    Step [7/19] is not hooked either: rerun it by hand after a"
    echo "    kernel update, or drop it once the fix lands upstream."
fi

cat <<EOF

════════════════════════════════════════════════════════════════════
  DONE. Reboot to apply.
  Backup of replaced files: $BACKUP
════════════════════════════════════════════════════════════════════

After reboot, verify:

  sudo dmesg | grep -iE 'I2C_DEVT|override|table upgrade'
    expect: "Table Upgrade: override [SSDT- HONOR-I2C_DEVT]"
    expect: NO "AE_AML_INTERNAL" lines

  ls /sys/bus/acpi/devices/ | grep -iE 'TOPS|FTSC'
    expect: TOPS0102:00 (touchpad), FTSC1000:00 (touchscreen)

  cat /proc/cmdline | grep i8042
    expect: includes i8042.dumbkbd=1

  # press Fn+F7 — mic should mute/unmute and the F7 LED should follow
  # (works out of the box via huawei-wmi; no extra setup needed):
  cat /sys/class/leds/platform::micmute/trigger
    expect: contains [audio-micmute]

  # 3.5mm-jack headset mic — should appear once you plug in a CTIA-wired
  # headset and PipeWire/wireplumber rescans:
  pactl list short sources | grep -i headset
    expect: a HiFi__Headset__source endpoint

  # SOF DSP IPC4 fix — verify the overlay loaded instead of the in-tree one:
  modinfo -F filename snd_sof
    expect: /lib/modules/.../updates/snd-sof.ko.zst (not kernel/sound/soc/sof/)

  # No DSP panic should follow a suspend/resume cycle with pavucontrol running
  # (this is the direct repro from upstream thesofproject/sof#10700):
  sudo rtcwake -m mem -s 5  # × 2-3 times with pavucontrol open
  journalctl -k -b | grep -c 'DSP panic'
    expect: 0 — on this HONOR ZQC-P unit it stays at 0 with or without
            the patch (the upstream race does not trigger here in
            normal use; the patch is preventive)

  # DO NOT use grep -c 'CRASHED' /var/log/honor-fnf7-watch.log as a
  # before/after metric. That counter also flips during runtime PM D3
  # cycles and overstates real panics by orders of magnitude.

  # HID-BPF fixup is loaded for the touchscreen:
  sudo udev-hid-bpf list-loaded
    expect: 0018:2808:5662.0001 with hid_fix_rdesc_f

  # The phantom KEY_MICMUTE device must be gone. This should print nothing:
  grep -l 'UNKNOWN' /sys/class/input/input*/name | xargs -r grep -H 2808

  # The real Fn+F7 must still work. The WMI device keeps keycode 248
  # (scancode 0x287), the mic-mute LED follows the audio-micmute trigger:
  cat /sys/class/leds/platform::micmute/brightness
    expect: brightness=0 when the mic is meant to be active

  # After every kernel update, re-run patch/headset-mic/install.sh and
  # patch/sof-audio/install.sh so the codec quirk and the SOF overlay are
  # rebuilt against the new headers. patch/micmute/ needs nothing.
EOF
