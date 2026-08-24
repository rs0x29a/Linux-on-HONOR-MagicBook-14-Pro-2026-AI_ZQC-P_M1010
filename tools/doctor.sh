#!/usr/bin/env bash
# Read-only support diagnostic for HONOR MagicBook Linux fixes.
# Usage: bash tools/doctor.sh [--json]

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

json=0
[[ "${1:-}" == "--json" ]] && json=1

val() {
    local path="$1"
    if [[ -r "$path" ]]; then
        tr '\n' ' ' < "$path" | sed 's/[[:space:]]*$//' | sed 's/"/\\"/g'
    else
        printf 'unavailable'
    fi
}

has() { command -v "$1" >/dev/null 2>&1; }

vendor="$(val /sys/class/dmi/id/sys_vendor)"
product="$(val /sys/class/dmi/id/product_name)"
board="$(val /sys/class/dmi/id/board_name)"
board_version="$(val /sys/class/dmi/id/board_version)"
kernel="$(uname -r 2>/dev/null || printf unavailable)"
distro="unknown"
if [[ -r /etc/os-release ]]; then
    distro="$(. /etc/os-release 2>/dev/null; printf '%s %s' "${NAME:-unknown}" "${VERSION_ID:-}")"
fi
initramfs="none"
has limine-mkinitcpio && initramfs="limine-mkinitcpio"
has mkinitcpio && initramfs="mkinitcpio"
has dracut && initramfs="dracut"
has update-initramfs && initramfs="update-initramfs"

acpi="missing"
if command -v journalctl >/dev/null 2>&1 && journalctl -k -b 2>/dev/null | grep -qiE 'table upgrade|I2C_DEVT'; then
    acpi="seen-in-current-boot-log"
fi
[[ -f /usr/lib/firmware/acpi/SSDT27_TPD0.aml ]] && acpi="firmware-table-present:$acpi"
[[ -f /boot/acpi_override.cpio ]] && acpi="early-cpio-present:$acpi"

lockdown="unavailable"
[[ -r /sys/kernel/security/lockdown ]] && lockdown="$(val /sys/kernel/security/lockdown)"
secure_boot="unavailable"
if has mokutil; then secure_boot="$(mokutil --sb-state 2>/dev/null | tr '\n' ' ')"; fi
leds="$(find /sys/class/leds -maxdepth 1 -mindepth 1 -printf '%f ' 2>/dev/null | sed 's/[[:space:]]*$//' || printf unavailable)"
backlights="$(find /sys/class/backlight -maxdepth 1 -mindepth 1 -printf '%f ' 2>/dev/null | sed 's/[[:space:]]*$//' || printf unavailable)"
fan="$(find /sys/class/hwmon -name name -exec grep -l '^honor_ec$' {} + 2>/dev/null | sed 's#/name$##' | head -1)"
fan="${fan:-unavailable}"
micmute_input="$(find /sys/class/input -name name -exec grep -il 'huawei.*wmi\|micmute' {} + 2>/dev/null | sed 's#/name$##' | head -1)"
micmute_input="${micmute_input:-unavailable}"
micmute_led="$(find /sys/class/leds -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null | grep -E '(^|:)micmute$' | head -1)"
micmute_led="${micmute_led:-unavailable}"

if (( json )); then
    esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    printf '{\n'
    printf '  "dmi":{"vendor":"%s","product":"%s","board":"%s","board_version":"%s"},\n' "$(esc "$vendor")" "$(esc "$product")" "$(esc "$board")" "$(esc "$board_version")"
    printf '  "system":{"kernel":"%s","distro":"%s","initramfs":"%s"},\n' "$(esc "$kernel")" "$(esc "$distro")" "$(esc "$initramfs")"
    printf '  "boot":{"acpi_override":"%s","lockdown":"%s","secure_boot":"%s"},\n' "$(esc "$acpi")" "$(esc "$lockdown")" "$(esc "$secure_boot")"
    printf '  "devices":{"leds":"%s","backlights":"%s","fan_hwmon":"%s","micmute_input":"%s","micmute_led":"%s"}\n' "$(esc "$leds")" "$(esc "$backlights")" "$(esc "$fan")" "$(esc "$micmute_input")" "$(esc "$micmute_led")"
    printf '}\n'
    exit 0
fi

printf 'HONOR Linux support doctor (read-only)\n\n'
printf 'DMI:         %s / %s / %s / %s\n' "$vendor" "$product" "$board" "$board_version"
printf 'System:      %s | %s | initramfs: %s\n' "$distro" "$kernel" "$initramfs"
printf 'ACPI:        %s\n' "$acpi"
printf 'Lockdown:    %s\n' "$lockdown"
printf 'Secure Boot: %s\n' "$secure_boot"
printf 'LEDs:        %s\n' "$leds"
printf 'Backlights:  %s\n' "$backlights"
printf 'Fan hwmon:   %s\n' "$fan"
printf 'Mic-mute:    input=%s | led=%s\n' "$micmute_input" "$micmute_led"
printf '\nAttach `bash tools/doctor.sh --json` to hardware issues.\n'
