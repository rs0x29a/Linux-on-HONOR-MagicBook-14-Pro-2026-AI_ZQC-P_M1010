#!/usr/bin/env bash
# install-alc269-fix.sh — fetch the running kernel's alc269.c from the
# upstream stable tree, apply our one-line SND_PCI_QUIRK addition for
# HONOR ZQC-P M1010 (PCI SSID 1ee7:209d), build the codec module
# out-of-tree against the installed kernel headers, and drop the
# resulting snd-hda-codec-alc269.ko.zst over the in-tree one. The
# original is backed up so uninstall_patch.sh can restore it.
#
# This is a workaround for as long as the upstream patch under
# patch/headset-mic/zqc-p/M1010/alc269-headset-mic.patch has not yet landed in the kernel
# being used. Once the entry is in
# the running kernel's alc269.c, this script becomes a no-op (it will
# detect the existing entry and skip the rebuild).
#
# Reruns are safe — running it after a kernel update will rebuild
# against the new headers automatically.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

# Override with KVER=... to build for a kernel other than the running one -
# needed when a kernel update is installed but not yet booted, and used by
# the pacman hook in patch/auto-rebuild/.
KVER="${KVER:-$(uname -r)}"
BUILD_DIR="/usr/lib/modules/${KVER}/build"
INTREE_DIR="/usr/lib/modules/${KVER}/kernel/sound/hda/codecs/realtek"
UPDATES_DIR="/usr/lib/modules/${KVER}/updates"
KO_NAME="snd-hda-codec-alc269.ko.zst"
KO_INTREE="${INTREE_DIR}/${KO_NAME}"
KO_OVERLAY="${UPDATES_DIR}/${KO_NAME}"
BACKUP="/root/${KO_NAME}.orig"
WORK=$(mktemp -d /tmp/alc269-fix-XXXXXX)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

req() { command -v "$1" >/dev/null || { echo "missing required tool: $1" >&2; exit 1; }; }
# Tier B: the subsystem id and the choice of fixup are model specific, and
# getting either wrong reconfigures the codec pins on real hardware.
source "${SCRIPT_DIR}/../../lib/gate.sh"
honor_gate headset-mic

fatal() { echo "[fatal] $*" >&2; exit 1; }

# patch/headset-mic/<model>/<board>/, the same two words the profile used.
variant_find "$SCRIPT_DIR" || fatal \
"this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
        Covered: $(variant_known "$SCRIPT_DIR")
        The quirk is a pin configuration written for one codec on one board, so
        a machine has to be added deliberately. See patch/headset-mic/README.md."

AUDIO_SSID="$(gate_param audio_ssid)" || fatal \
"$(profile_get model) does not record audio_ssid. Read it with:
          for d in /sys/bus/pci/devices/*; do
              case \"\$(cat \$d/class)\" in 0x0401*|0x0403*)
                  echo \"\$(cat \$d/subsystem_vendor):\$(cat \$d/subsystem_device)\";;
              esac
          done"

FIXUP_NAME="$(recipe_param fixup)" || fatal \
"patch/headset-mic/${VARIANT_FOR}/recipe.conf does not record fixup, so there is
        no way to know which alc269.c fixup this board needs. That has to be
        worked out on the machine itself."

# The board directory says which codec it was written against; the machine says
# what it has. A pin configuration handed to the wrong codec is not a no-op.
variant_check_device "$AUDIO_SSID" || fatal \
"$(profile_get model) board ${PROFILE_BOARD:-?} was written against codec
        $(recipe_get device), and this machine reports $AUDIO_SSID. Nothing has
        been built. Please open an issue with both ids."

SSID_VEN="0x${AUDIO_SSID%%:*}"
SSID_DEV="0x${AUDIO_SSID##*:}"
QUIRK_DESC="HONOR $(profile_get model)"

# The fixup body further down is C written for one board: pin 0x19
# reconfigured and chained into the headset-mode lifecycle. There is no generic
# machinery to synthesise another one, so a model needing a different fixup
# needs its body added here first.
if [[ "$FIXUP_NAME" != "ALC256_FIXUP_HONOR_ZQC_P_M1010_MIC" ]]; then
    fatal "the profile asks for fixup '$FIXUP_NAME', but this installer only
        knows how to emit ALC256_FIXUP_HONOR_ZQC_P_M1010_MIC. Add the body for
        '$FIXUP_NAME' to patch/headset-mic/install.sh before installing."
fi
echo "[ok] machine $(variant_note)"
echo "[ok] codec ${SSID_VEN}:${SSID_DEV}, fixup ${FIXUP_NAME}"

legacy_drop /etc/wireplumber/wireplumber.conf.d/51-honor-zqcp-mic-priority.conf

req curl
req zstdcat
req zstd
req make
if distro_kernel_config_has CONFIG_CC_IS_CLANG=y "$KVER"; then
    MODULE_CC=clang
    MODULE_LLVM="LLVM=1 LLVM_IAS=1"
else
    MODULE_CC=gcc
    MODULE_LLVM=
fi
req "$MODULE_CC"
req depmod
req modprobe
req strings
# This used to warn that hda-verb was missing and that honor-mic-jack-init.service
# would therefore not work. That service was the previous iteration of this fix
# and this installer removes it a few steps further down, so the warning sent
# people to install alsa-tools for something that was about to be deleted. It
# was still doing that in a user log in issue 11. The quirk needs nothing from
# userspace: it is a pin configuration in the codec driver.

echo "[*] kernel = ${KVER}"
echo "[*] target = ${KO_OVERLAY}"

# --- WirePlumber: keep the internal DMIC as the default capture source -------
# The quirk uses JACK_DETECT_OVERRIDE, so the jack input is always reported
# present and WirePlumber ranks it (priority.session 2000) above the built-in
# digital microphone array (1648). That makes an empty jack the default
# recording device, and it breaks the mic-mute LED, because the kernel's
# control-LED group only tracks the DMIC control. Rank the jack input below
# the array; it stays fully usable, it is simply no longer the default.
WP_RULE="${SCRIPT_DIR}/51-honor-mic-priority.conf"
WP_DIR="/etc/wireplumber/wireplumber.conf.d"
if [[ -f "$WP_RULE" ]]; then
    echo "[*] installing ${WP_DIR}/$(basename "$WP_RULE")"
    install -d -m 0755 "$WP_DIR"
    install -m 0644 "$WP_RULE" "$WP_DIR/"

    # WirePlumber remembers a manually chosen default source and that choice
    # outranks the priority rule. Drop a stale one so the rule decides.
    WP_USER="${SUDO_USER:-}"
    if [[ -n "$WP_USER" && "$WP_USER" != "root" ]]; then
        WP_HOME=$(getent passwd "$WP_USER" | cut -d: -f6)
        rm -f "${WP_HOME}/.local/state/wireplumber/default-nodes"
        WP_RD="/run/user/$(id -u "$WP_USER" 2>/dev/null || echo 0)"
        if [[ -d "$WP_RD" ]]; then
            sudo -u "$WP_USER" \
                XDG_RUNTIME_DIR="$WP_RD" \
                DBUS_SESSION_BUS_ADDRESS="unix:path=${WP_RD}/bus" \
                systemctl --user restart wireplumber 2>/dev/null \
                && echo "[ok] wireplumber restarted for ${WP_USER}" \
                || echo "[*] restart wireplumber (or log out and back in) to apply"
        fi
    else
        echo "[*] restart wireplumber (or log out and back in) to apply"
    fi
else
    echo "[warn] ${WP_RULE##*/} not found next to this script - skipping the"
    echo "       capture-priority rule. The 3.5 mm jack input may become the"
    echo "       default source and the mic-mute LED will not follow Fn+F7."
fi


# Remove the previous-iteration systemd workaround if it's still installed.
# It was a userspace hotfix for the same problem this kernel fixup now
# solves at the source; keeping it active would pointlessly fire an extra
# hda-verb on every boot/resume.
remove_legacy_jack_service() {
    if systemctl list-unit-files honor-mic-jack-init.service >/dev/null 2>&1 \
       && systemctl is-enabled honor-mic-jack-init.service >/dev/null 2>&1; then
        echo "[*] removing legacy honor-mic-jack-init.service (no longer needed — fixed in kernel)"
        systemctl disable --now honor-mic-jack-init.service >/dev/null 2>&1 || true
    fi
    rm -f /etc/systemd/system/honor-mic-jack-init.service \
          /usr/local/bin/honor-mic-jack-init.sh
    systemctl daemon-reload 2>/dev/null || true
}

# Detect if the in-tree module already has our quirk (e.g. a future kernel
# update has merged the upstream patch). In that case skip the rebuild.
# Wrap in subshell because `grep -q` closes its stdin on first match, which
# SIGPIPEs zstdcat → with `set -o pipefail` the pipeline would return failure
# and we'd needlessly rebuild.
has_quirk() {
    [[ -f "$1" ]] || return 1
    ( set +o pipefail; zstdcat "$1" 2>/dev/null | grep -aqF $'\xe7\x1e\x9d\x20' )
}
# An older revision of this script installed the patched module *over* the
# in-tree one, which a kernel package update then silently reverted. If that
# is still the case here, put the pristine module back before continuing, but
# only when the backup actually belongs to this kernel.
if [[ -f "$BACKUP" ]] && has_quirk "$KO_INTREE"; then
    BACKUP_VERMAGIC=$(modinfo -F vermagic "$BACKUP" 2>/dev/null | awk '{print $1}')
    if [[ "$BACKUP_VERMAGIC" == "$KVER" ]]; then
        echo "[*] undoing a legacy in-place install: restoring $KO_INTREE"
        install -m 0644 "$BACKUP" "$KO_INTREE"
    else
        echo "[warn] $KO_INTREE carries the quirk and a backup exists, but the"
        echo "       backup is for ${BACKUP_VERMAGIC:-an unknown kernel}, not ${KVER}."
        echo "       Leaving the in-tree module alone."
    fi
fi

if has_quirk "$KO_INTREE"; then
    echo "[ok] in-tree alc269 already contains the $(profile_get model) quirk — nothing to do."
    if [[ -f "$KO_OVERLAY" ]]; then
        echo "[*] removing redundant overlay $KO_OVERLAY"
        rm -f "$KO_OVERLAY"
        rmdir --ignore-fail-on-non-empty "$UPDATES_DIR" 2>/dev/null || true
        depmod -a "$KVER"
    fi
    remove_legacy_jack_service
    exit 0
fi

if has_quirk "$KO_OVERLAY"; then
    echo "[ok] patched overlay already present at $KO_OVERLAY — nothing to do."
    remove_legacy_jack_service
    exit 0
fi

# Verify build infrastructure is present.
if [[ ! -f "${BUILD_DIR}/Makefile" || ! -f "${BUILD_DIR}/Module.symvers" ]]; then
    echo "[fatal] kernel build dir incomplete: ${BUILD_DIR}" >&2
    echo "        install the matching linux-*-headers package and re-run."
    exit 1
fi
if [[ ! -d "${BUILD_DIR}/sound/hda/codecs/realtek" ]]; then
    echo "[fatal] ${BUILD_DIR}/sound/hda/codecs/realtek missing" >&2
    echo "        the kernel headers package does not expose the sound/hda subtree;"
    echo "        a different distro / kernel layout is needed to rebuild this module."
    exit 1
fi

# Fetch upstream sources matching the running kernel's tag, from the
# stable-tree mirror. Which tag that is, and the proof that it really is this
# kernel, are lib/ksrc.sh's problem.
ksrc_resolve

echo "[*] fetching sources at tag ${KSRC_TAG}"
mkdir -p "${WORK}/helpers"
ksrc_fetch "sound/hda/codecs/realtek/alc269.c"            "${WORK}/alc269.c"
ksrc_fetch "sound/hda/codecs/realtek/realtek.h"           "${WORK}/realtek.h"
ksrc_fetch "sound/hda/codecs/generic.h"                   "${WORK}/generic.h"
ksrc_fetch "sound/hda/codecs/side-codecs/hda_component.h" "${WORK}/hda_component.h"
ksrc_fetch "sound/hda/common/hda_local.h"                 "${WORK}/hda_local.h"
ksrc_fetch "sound/hda/common/hda_auto_parser.h"           "${WORK}/hda_auto_parser.h"
ksrc_fetch "sound/hda/common/hda_beep.h"                  "${WORK}/hda_beep.h"
ksrc_fetch "sound/hda/common/hda_jack.h"                  "${WORK}/hda_jack.h"
for f in thinkpad ideapad_hotkey_led hp_x360 ideapad_s740; do
    ksrc_fetch "sound/hda/codecs/helpers/${f}.c"          "${WORK}/helpers/${f}.c"
done

# Flatten the source-tree include paths so we don't need to mirror the
# full sound/hda subtree.
sed -i 's|#include "../helpers/|#include "helpers/|g'                   "${WORK}/alc269.c"
sed -i 's|#include "../generic.h"|#include "generic.h"|g; s|#include "../side-codecs/hda_component.h"|#include "hda_component.h"|g' "${WORK}/realtek.h"

# Apply our quirk.
#
# We do NOT use the simple ALC2XX_FIXUP_HEADSET_MIC the way BRB-X M1010
# does. That fixup's pincfg `0x03a1103c` has JACK_DETECT_OVERRIDE=0
# (use the codec's real impedance detection) and only handles
# HDA_FIXUP_ACT_PRE_PROBE — it never invokes the codec's headset-mode
# probe/init paths. On the ZQC-P PCB this leaves pin 0x19 in a state
# where GET_PIN_SENSE returns 0 after boot/suspend until the user
# physically unplugs and replugs the jack: the SOF DSP capture pathway
# is never activated and recording from `pcm0c HDA Analog` is silent.
#
# Instead we add a new fixup `ALC256_FIXUP_HONOR_ZQC_P_M1010_MIC` that:
#   1. Sets pin 0x19 to `0x01a1913c` (JACK_DETECT_OVERRIDE=1, "always
#      present, ignore the impedance circuit"); same pattern many other
#      Realtek/HONOR/Dell quirks use ("use as headset mic, without its
#      own jack detect"). This bypasses the unreliable hardware detect
#      on this PCB.
#   2. Chains to `ALC269_FIXUP_HEADSET_MODE_NO_HP_MIC`. That existing
#      kernel fixup calls `alc_fixup_headset_mode_no_hp_mic` →
#      `alc_fixup_headset_mode` which handles PRE_PROBE (parse flag),
#      PROBE (`alc_probe_headset_mode`) AND INIT
#      (`alc_update_headset_mode`, run on every codec init including
#      after S3/S4 resume). This is the piece our previous one-line
#      patch was missing.
#
# After this fixup the headset mic works out of the box across cold
# boot, warm reboot and suspend/resume cycles, with no need for any
# userspace daemon or hda-verb tricks.
if grep -q "$FIXUP_NAME" "${WORK}/alc269.c"; then
    echo "[ok] upstream already has the $(profile_get model) fixup — building unmodified."
else
    FIXUP_NAME="$FIXUP_NAME" SSID_VEN="$SSID_VEN" SSID_DEV="$SSID_DEV" \
    QUIRK_DESC="$QUIRK_DESC" python3 <<PYEOF
import os
fixup_name = os.environ["FIXUP_NAME"]
ssid_ven   = os.environ["SSID_VEN"]
ssid_dev   = os.environ["SSID_DEV"]
quirk_desc = os.environ["QUIRK_DESC"]
src_path = "${WORK}/alc269.c"
with open(src_path) as f:
    src = f.read()

# 1. Add new enum value right after ALC2XX_FIXUP_HEADSET_MIC.
enum_marker = "\tALC2XX_FIXUP_HEADSET_MIC,\n"
enum_add    = "\t%s,\n" % fixup_name
if enum_marker not in src:
    raise SystemExit("could not find ALC2XX_FIXUP_HEADSET_MIC enum entry")
src = src.replace(enum_marker, enum_marker + enum_add, 1)

# 2. Add fixup table entry right after the ALC2XX_FIXUP_HEADSET_MIC body.
#    We use a PINS-only fixup chained to the existing
#    ALC269_FIXUP_HEADSET_MODE_NO_HP_MIC, which gives us the canonical
#    PRE_PROBE + PROBE + INIT (incl. S3/S4 resume) headset-mode lifecycle.
#
#    Note: a "mic-mute LED should follow the analog capture switch as
#    well as the DMIC one" change would belong in SOF / wireplumber
#    plumbing, not in this quirk table — analog Capture Switch toggles
#    on this hardware don't go through hda_generic's mic-mute hook
#    because the audio chain is owned by the SOF DSP. We're not trying
#    to solve that in alc269.c.
body_marker = "\t[ALC2XX_FIXUP_HEADSET_MIC] = {\n\t\t.type = HDA_FIXUP_FUNC,\n\t\t.v.func = alc2xx_fixup_headset_mic,\n\t},\n"
body_add = (
    "\t[%s] = {\n" % fixup_name +
    "\t\t.type = HDA_FIXUP_PINS,\n"
    "\t\t.v.pins = (const struct hda_pintbl[]) {\n"
    "\t\t\t{ 0x19, 0x01a1913c }, /* use as headset mic, without its own jack detect */\n"
    "\t\t\t{ }\n"
    "\t\t},\n"
    "\t\t.chained = true,\n"
    "\t\t.chain_id = ALC269_FIXUP_HEADSET_MODE_NO_HP_MIC,\n"
    "\t},\n"
)
if body_marker not in src:
    raise SystemExit("could not find ALC2XX_FIXUP_HEADSET_MIC body")
src = src.replace(body_marker, body_marker + body_add, 1)

# 4. Add SND_PCI_QUIRK referring to the new fixup.
quirk_marker = '\tSND_PCI_QUIRK(0x1ee7, 0x2078, "HONOR BRB-X M1010", ALC2XX_FIXUP_HEADSET_MIC),\n'
quirk_add    = '\tSND_PCI_QUIRK(%s, %s, "%s", %s),\n' % (ssid_ven, ssid_dev, quirk_desc, fixup_name)
if quirk_marker not in src:
    raise SystemExit("could not find HONOR BRB-X M1010 quirk to anchor on")
src = src.replace(quirk_marker, quirk_marker + quirk_add, 1)

with open(src_path, "w") as f:
    f.write(src)
PYEOF
    if ! grep -q "${SSID_VEN}, ${SSID_DEV}" "${WORK}/alc269.c"; then
        echo "[fatal] could not insert the SND_PCI_QUIRK line — upstream layout changed" >&2
        echo "        review patch/headset-mic/zqc-p/M1010/alc269-headset-mic.patch and adjust." >&2
        exit 1
    fi
    echo "[ok] inserted SND_PCI_QUIRK for ${AUDIO_SSID} ${QUIRK_DESC}"
fi

# KDIR is baked in from $BUILD_DIR rather than derived from `uname -r`, so a
# KVER override actually reaches the build.
cat > "${WORK}/Makefile" <<EOF
KDIR := ${BUILD_DIR}
PWD  := \$(shell pwd)

obj-m += snd-hda-codec-alc269.o
snd-hda-codec-alc269-y := alc269.o

ccflags-y += -I\$(src)

default:
	\$(MAKE) -C \$(KDIR) M=\$(PWD) CC=${MODULE_CC} ${MODULE_LLVM} modules

clean:
	\$(MAKE) -C \$(KDIR) M=\$(PWD) clean
EOF

echo "[*] building module"
make -C "$WORK" -s 2>&1 | tail -10
if [[ ! -f "${WORK}/snd-hda-codec-alc269.ko" ]]; then
    echo "[fatal] build did not produce snd-hda-codec-alc269.ko" >&2
    exit 1
fi

echo "[*] installing patched module as an overlay"
zstd -19 -q --force "${WORK}/snd-hda-codec-alc269.ko" -o "${WORK}/${KO_NAME}"
install -d -m 0755 "$UPDATES_DIR"
install -m 0644 "${WORK}/${KO_NAME}" "$KO_OVERLAY"
depmod -a "$KVER"

# Drop the legacy systemd hotfix if a previous run of this script
# installed it — the kernel-side fixup makes it redundant.
remove_legacy_jack_service

echo
echo "════════════════════════════════════════════════════════════════════"
echo "  ALC256 $(profile_get model) quirk installed."
echo
echo "  After a fresh boot, the analog 3.5mm-jack headset microphone"
echo "  will appear as 'HiFi__Headset__source' in PipeWire and as the"
echo "  'Headset Mic' input under GNOME/KDE/niri sound settings."
echo
echo "  Pin 0x19 uses pincfg 0x01a1913c (JACK_DETECT_OVERRIDE=1) and the"
echo "  fixup chains to the kernel's existing headset_mode_no_hp_mic init,"
echo "  so the analog mic path is wired up at codec probe + every init,"
echo "  including after S3/S4 resume. No userspace jack-detect helper"
echo "  is needed."
echo
echo "  Installed as an overlay at: $KO_OVERLAY"
echo "  The in-tree module is left untouched; delete the overlay and run"
echo "  'depmod -a' to revert."
echo
echo "  Kernel updates are handled automatically if patch/auto-rebuild/ is"
echo "  installed. Otherwise re-run this script after every kernel update."
echo "════════════════════════════════════════════════════════════════════"
