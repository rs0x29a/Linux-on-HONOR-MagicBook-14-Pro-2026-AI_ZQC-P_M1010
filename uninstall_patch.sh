#!/usr/bin/env bash
# uninstall_patch.sh — revert everything apply_patch.sh installed. Run as root.
#
# Deliberately NOT `set -e`. This is the recovery path: a machine reaching for
# it may already be in an odd state — a kernel whose module tree is gone, a
# bootloader config somebody edited by hand — and a failure in step 7 must not
# stop step 12 from running. Every step reports for itself and the exit status
# reflects the total.

set -uo pipefail

UNINSTALL_FAILURES=0
step_failed() { printf '    [warn] %s\n' "$*" >&2; UNINSTALL_FAILURES=$((UNINSTALL_FAILURES + 1)); }

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/distro.sh"

echo "[1/15] Remove patched SSDT"
rm -fv /usr/lib/firmware/acpi/SSDT27_TPD0.aml
rmdir --ignore-fail-on-non-empty /usr/lib/firmware/acpi 2>/dev/null || true

echo "[2/15] Remove the initramfs mechanism that staged it"
rm -fv /etc/initcpio/install/acpi_override
# Debian and Ubuntu: the CPIO handed to GRUB, and its GRUB_EARLY_INITRD entry.
distro_acpi_override_remove || true

echo "[3/15] Strip acpi_override from the initramfs config and this repo's parameters from the cmdline"
if [[ -f /etc/mkinitcpio.conf ]]; then
    sed -i 's/ acpi_override//' /etc/mkinitcpio.conf
    echo "    HOOKS=$(grep -E '^HOOKS=' /etc/mkinitcpio.conf)"
fi

# Whichever file this distribution keeps the command line in.
distro_cmdline_remove 'i8042\.dumbkbd=1' || true
# The PSR level from patch/psr-band. Removing it hands PSR2 selective update
# back to the driver, which is what a full revert means, band and all.
distro_cmdline_remove '(xe|i915)\.enable_psr=[0-9]+' || true
if CMDFILE="$(distro_cmdline_file)"; then
    echo "    $(grep -hE 'CMDLINE|^[^#]' "$CMDFILE" | head -1)"
fi

KVER=$(uname -r)

echo "[4/15] Remove the ALC256 codec-quirk overlay and the capture-priority rule"
rm -fv "/usr/lib/modules/${KVER}/updates/snd-hda-codec-alc269.ko.zst" 2>/dev/null || true
rm -fv /etc/wireplumber/wireplumber.conf.d/51-honor-mic-priority.conf 2>/dev/null || true
rmdir --ignore-fail-on-non-empty /etc/wireplumber/wireplumber.conf.d /etc/wireplumber 2>/dev/null || true

echo "[4b/15] Restore original snd-hda-codec-alc269.ko.zst if a legacy in-place install is present"
ALC_PATH="/usr/lib/modules/${KVER}/kernel/sound/hda/codecs/realtek/snd-hda-codec-alc269.ko.zst"
ALC_BACKUP="/root/snd-hda-codec-alc269.ko.zst.orig"
if [[ -f "$ALC_BACKUP" ]]; then
    cp -av "$ALC_BACKUP" "$ALC_PATH"
    rm -fv "$ALC_BACKUP"
else
    echo "    no backup at $ALC_BACKUP — patched module (if any) left in place."
    echo "    reinstall the linux-headers / linux package to restore the original."
fi

# Earlier iterations of install-alc269-fix.sh installed a systemd hotfix
# service to fire EXECUTE_PIN_SENSE on every boot. The current kernel-side
# fixup makes it unnecessary — remove it if it's still present.
if systemctl list-unit-files honor-mic-jack-init.service >/dev/null 2>&1 \
   && systemctl is-enabled honor-mic-jack-init.service >/dev/null 2>&1; then
    systemctl disable --now honor-mic-jack-init.service 2>/dev/null || true
fi
rm -f /etc/systemd/system/honor-mic-jack-init.service \
      /usr/local/bin/honor-mic-jack-init.sh
systemctl daemon-reload 2>/dev/null || true

echo "[5/15] Remove SOF IPC4 fix overlay (if present)"
SOF_OVERLAY="/usr/lib/modules/${KVER}/updates/snd-sof.ko.zst"
SOF_BACKUP="/root/snd-sof.ko.zst.orig"
if [[ -f "$SOF_OVERLAY" ]]; then
    rm -fv "$SOF_OVERLAY"
else
    echo "    no overlay at $SOF_OVERLAY — already absent."
fi
[[ -f "$SOF_BACKUP" ]] && echo "    in-tree backup at $SOF_BACKUP retained for next install."

echo "[6/15] Remove the auto-rebuild package-manager hooks"
# Both styles: pacman hooks on Arch, /etc/kernel/postinst.d on Debian and
# Ubuntu. Removing a file that was never installed is not an error.
rm -fv /etc/pacman.d/hooks/95-honor-kernel-modules.hook \
       /etc/pacman.d/hooks/96-honor-libfprint.hook \
       /etc/kernel/postinst.d/95-honor-kernel-modules \
       /etc/systemd/system/honor-autorebuild.path \
       /etc/systemd/system/honor-autorebuild.service \
       /usr/local/lib/honor/rebuild.sh \
       /usr/local/lib/honor/deferred.sh \
       /etc/honor-autorebuild.conf
rmdir --ignore-fail-on-non-empty /usr/local/lib/honor 2>/dev/null || true
systemctl disable --now honor-autorebuild.path >/dev/null 2>&1 || true
systemctl daemon-reload 2>/dev/null || true

echo "[7/15] Remove the HID-BPF mic-mute fixup and any legacy module overlays"
systemctl disable --now honor-hid-bpf-reapply.service 2>/dev/null || true
rm -fv /etc/systemd/system/honor-hid-bpf-reapply.service \
       /usr/local/lib/honor/hid-bpf-reapply.sh
systemctl daemon-reload 2>/dev/null || true
rm -fv /etc/udev-hid-bpf/honor-ftsc1000-micmute.bpf.o \
       /etc/udev/rules.d/99-hid-bpf-honor-ftsc1000-micmute.rules
udevadm control --reload 2>/dev/null || true
for pair in \
    "/usr/lib/modules/${KVER}/updates/hid-multitouch.ko.zst:/root/hid-multitouch.ko.zst.orig" \
    "/usr/lib/modules/${KVER}/updates/huawei-wmi.ko.zst:/root/huawei-wmi.ko.zst.orig"
do
    OVERLAY="${pair%%:*}"; BACKUP="${pair##*:}"
    [[ -f "$OVERLAY" ]] && rm -fv "$OVERLAY"
    [[ -f "$BACKUP" ]] && echo "    in-tree backup at $BACKUP retained."
done

rmdir --ignore-fail-on-non-empty "/usr/lib/modules/${KVER}/updates" 2>/dev/null || true
depmod -a "$KVER" 2>/dev/null || step_failed "depmod -a $KVER failed (no module tree for the running kernel?)"

echo "[8/15] Remove the touchpad edge-gesture HID-BPF program"
rm -fv /etc/udev-hid-bpf/honor-tops0102-edge.bpf.o \
       /etc/udev/rules.d/99-hid-bpf-honor-tops0102-edge.rules
udevadm control --reload 2>/dev/null || true

echo "[9/15] Revert the OLED backlight VBT"
if [[ -x "$(dirname "${BASH_SOURCE[0]}")/patch/oled-backlight/uninstall.sh" ]]; then
    REGEN=0 bash "$(dirname "${BASH_SOURCE[0]}")/patch/oled-backlight/uninstall.sh" || \
        echo "    [warn] revert failed, see patch/oled-backlight/uninstall.sh"
else
    echo "    patch/oled-backlight/uninstall.sh not found — removing by hand"
    sed -i "s# \(xe\|i915\)\.vbt_firmware=[^ \"]*##" /etc/default/limine 2>/dev/null || true
    sed -i "/^FILES=/ { s#/usr/lib/firmware/honor/zqc-p-vbt.bin *##; s#^FILES=( *)#FILES=()#; }" \
        /etc/mkinitcpio.conf 2>/dev/null || true
    rm -fv /usr/lib/firmware/honor/zqc-p-vbt.bin
fi

echo "[10/15] Remove the locally built xe.ko overlay"
# One module, several patches. There is no partial removal: taking the overlay
# away reverts every fix that lived inside it, so say which ones those were.
if [[ -f "/usr/lib/modules/${KVER}/updates/xe.ko.zst" ]]; then
    if [[ -r /var/lib/honor/xe-module.stamp ]]; then
        echo "    it carried: $(sed -n 's/^patches=//p' /var/lib/honor/xe-module.stamp)"
    fi
    rm -fv "/usr/lib/modules/${KVER}/updates/xe.ko.zst"
    rmdir --ignore-fail-on-non-empty "/usr/lib/modules/${KVER}/updates" 2>/dev/null || true
    depmod -a "$KVER" 2>/dev/null || step_failed "depmod -a $KVER failed"
    echo "    back to the packaged module: $(modinfo -k "$KVER" xe | grep -E '^filename:')"
    echo "    the boot-time display glitch on 7.1.6+ comes back, and the panel"
    echo "    goes back to 6 bits per colour with dithering."
else
    echo "    not installed"
fi
rm -fv /var/lib/honor/xe-module.stamp 2>/dev/null || true
rmdir --ignore-fail-on-non-empty /var/lib/honor 2>/dev/null || true

# Everything installed at runtime used to carry "zqcp" in its name. In an
# uninstall a blanket sweep is right: we are removing all of it anyway.
echo "[11/15] Remove the battery charge limit and its units"
systemctl disable --now honor-battery-threshold.service >/dev/null 2>&1 || true
systemctl disable honor-battery-threshold-resume.service >/dev/null 2>&1 || true
rm -fv /etc/systemd/system/honor-battery-threshold.service \
       /etc/systemd/system/honor-battery-threshold-resume.service \
       /usr/local/lib/honor/honor-battery-threshold.sh \
       /etc/honor-battery.conf
systemctl daemon-reload 2>/dev/null || true
if [[ -w /sys/devices/platform/huawei-wmi/charge_control_thresholds ]]; then
    echo "0 100" > /sys/devices/platform/huawei-wmi/charge_control_thresholds
    echo "    charge limit removed (0 100)"
fi

echo "[12/15] Remove the hotkey keymap overlay"
rm -fv "/usr/lib/modules/${KVER}/updates/huawei-wmi.ko"* \
       /etc/udev/hwdb.d/61-honor-keyboard.hwdb
command -v systemd-hwdb >/dev/null && systemd-hwdb update 2>/dev/null || true
depmod -a "$KVER" 2>/dev/null || true
modprobe -r huawei-wmi 2>/dev/null || true
modprobe huawei-wmi 2>/dev/null || true
echo "    back to the packaged module"

echo "[13/15] Remove the hotkey action service"
systemctl disable --now honor-hotkey-actions.service >/dev/null 2>&1 || true
# Read the camera id BEFORE deleting the file that holds it.
CAM_ID=""
[[ -f /etc/honor-hotkey-actions.conf ]] && \
    CAM_ID="$(sed -n 's/^CAMERA_USB=//p' /etc/honor-hotkey-actions.conf | tr -d '"' | head -1)"
rm -fv /etc/systemd/system/honor-hotkey-actions.service \
       /usr/local/lib/honor/honor-hotkey-actions.py \
       /etc/honor-hotkey-actions.conf
# Leave the camera authorised on the way out. Only the camera: writing 1 to
# every `authorized` under /sys/bus/usb/devices would also re-authorise devices
# somebody had deliberately switched off, and would do it even on a machine
# where this fix was never installed.
systemctl daemon-reload 2>/dev/null || true
if [[ -n "$CAM_ID" ]]; then
    for d in /sys/bus/usb/devices/*/; do
        [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
        [[ "$(cat "$d/idVendor"):$(cat "$d/idProduct")" == "$CAM_ID" ]] || continue
        [[ -w "$d/authorized" ]] && echo 1 > "$d/authorized" 2>/dev/null \
            && echo "    re-authorised the webcam ($CAM_ID)"
    done
else
    echo "    no camera id on record; if your webcam is missing, re-authorise it"
    echo "    with: echo 1 | sudo tee /sys/bus/usb/devices/<dev>/authorized"
fi

# The keyboard backlight is a separate DKMS module because it owns the EC LED.
echo "[14a/15] Remove the EC keyboard backlight"
modprobe -r honor-zqcp-kbdlight 2>/dev/null || true
if command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null | grep -q '^honor-zqcp-kbdlight'; then
    dkms remove -m honor-zqcp-kbdlight -v 1.0 --all >/dev/null 2>&1 || \
        step_failed "dkms remove honor-zqcp-kbdlight/1.0 failed"
fi
rm -rfv /usr/src/honor-zqcp-kbdlight-1.0 \
        /etc/modules-load.d/honor-zqcp-kbdlight.conf 2>/dev/null || true
rm -fv /usr/lib/modules/*/updates/honor-zqcp-kbdlight.ko* \
       /lib/modules/*/updates/honor-zqcp-kbdlight.ko* 2>/dev/null || true

echo "[14b/15] Remove the fan curve controller"
systemctl disable --now honor-fan-curve.service >/dev/null 2>&1 || true
rm -fv /etc/systemd/system/honor-fan-curve.service \
       /etc/honor-fan-curve.conf \
       /usr/local/lib/honor/honor-fan-curve.sh 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

echo "[14/15] Remove the fan sensor module"
# apply_patch.sh installs this by default, so uninstall has to take it out.
# Order matters: unload first, then let DKMS deregister, then remove the files.
modprobe -r honor-ec-sensors 2>/dev/null || rmmod honor_ec_sensors 2>/dev/null || true
if command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null | grep -q '^honor-ec-sensors'; then
    dkms remove -m honor-ec-sensors -v 1.0 --all >/dev/null 2>&1 \
        && echo "    removed DKMS module honor-ec-sensors" \
        || step_failed "dkms remove honor-ec-sensors/1.0 failed; remove it by hand"
fi
rm -rfv /usr/src/honor-ec-sensors-1.0 \
        /etc/modules-load.d/honor-ec-sensors.conf 2>/dev/null || true
rm -fv /usr/lib/modules/*/updates/honor-ec-sensors.ko* \
       /lib/modules/*/updates/honor-ec-sensors.ko* 2>/dev/null || true

echo "[14b/15] Remove anything left under the pre-rename names"
modprobe -r honor-zqcp-hwmon 2>/dev/null || rmmod honor_zqcp_hwmon 2>/dev/null || true
if command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null | grep -q '^honor-zqcp-hwmon'; then
    dkms remove -m honor-zqcp-hwmon -v 1.0 --all >/dev/null 2>&1 || true
    echo "    removed DKMS module honor-zqcp-hwmon"
fi
rm -rfv /usr/src/honor-zqcp-hwmon-1.0 \
        /usr/local/lib/honor-zqcp \
        /var/lib/honor-zqcp \
        /etc/modules-load.d/honor-zqcp-hwmon.conf \
        /etc/honor-zqcp-autorebuild.conf \
        /etc/pacman.d/hooks/95-honor-zqcp-kernel-modules.hook \
        /etc/pacman.d/hooks/96-honor-zqcp-libfprint.hook \
        /etc/wireplumber/wireplumber.conf.d/51-honor-zqcp-mic-priority.conf \
        /etc/udev/rules.d/99-honor-zqcp-backlight-nonzero.rules 2>/dev/null || true
rm -fv /usr/lib/modules/*/updates/honor-zqcp-hwmon.ko* 2>/dev/null || true

echo "[15/15] Rebuild initramfs + bootloader config"
distro_initramfs_rebuild || step_failed "rebuild the initramfs yourself before rebooting"
distro_bootloader_update || step_failed "regenerate your bootloader config yourself before rebooting"

echo
echo "Done. Reboot to fully revert. Touchpad/touchscreen will be unavailable"
echo "again until apply_patch.sh is re-run or a different fix is installed."
echo "Analog 3.5mm-jack headset mic input will also disappear."
echo "SOF DSP will fall back to the in-tree (unpatched) module — expect"
echo "occasional DSP panics on suspend/resume per thesofproject/sof#10700."
echo "The touchscreen's vendor HID collection will be exported as a phantom"
echo "KEY_MICMUTE device again, so the mic will start muting itself."
echo "The touchpad left-edge brightness gesture and the raised OLED backlight"
echo "floor are reverted too."
echo
echo "Not touched, remove separately if you want it gone:"
echo "  fingerprint  reinstall your distribution's libfprint package"

if (( UNINSTALL_FAILURES )); then
    echo
    echo "$UNINSTALL_FAILURES step(s) reported a problem, listed above. Everything else"
    echo "was reverted. The usual cause is a machine whose running kernel has no"
    echo "module tree, which nothing here can fix and which a reboot usually can."
    exit 1
fi
