#!/usr/bin/env bash
# Re-apply the battery charge limit. Installed to /usr/local/lib/honor/ and run
# by honor-battery-threshold.service at boot and after resume.
#
# The value comes from /etc/honor-battery.conf, which the installer writes.
#
# install.sh sources this file for the apply-and-check functions below, so the
# installer and the service cannot drift apart on how the EC is armed.
set -euo pipefail

CONF=/etc/honor-battery.conf
NODE=/sys/devices/platform/huawei-wmi/charge_control_thresholds
EC_IO=/sys/kernel/debug/ec/ec0/io
WMI_DBG=/sys/kernel/debug/huawei-wmi

# The index the EC keeps at 0x85 for each of HONOR PC Manager's presets. It is
# also the mode byte \SBCM takes, which is what makes the fallback below
# possible: the two are the same number.
preset_mode() {
    case "$1" in
        "40 70")  echo 1 ;;
        "70 90")  echo 2 ;;
        "95 100") echo 3 ;;
        "0 100")  echo 0 ;;
        *) return 1 ;;
    esac
}

# ec_mode -> the EC's charge mode byte, or non-zero if the EC is not readable.
ec_mode() {
    [[ -r "$EC_IO" ]] || modprobe ec_sys 2>/dev/null || true
    [[ -r "$EC_IO" ]] || return 1
    dd if="$EC_IO" bs=1 skip=133 count=1 2>/dev/null | od -An -tu1 | tr -d ' '
}

# sbcm_arm <pair>
# Call the firmware's \SBCM (WMI function 0x15 of group 0x03) through the
# in-tree driver's debugfs hook. This is the call HONOR PC Manager makes: unlike
# \SBTT, which only stores the pair, it writes the charge mode explicitly. The
# payload is the u64 the driver hands to WMI, least significant byte first:
#     03 15 <mode> 48 <start> <stop>
# 0x48 is what every EC seen so far already holds in that field (GBCM reads it
# back), and no report of the call working uses anything else. Only the pairs
# preset_mode knows are ever sent, so a zero pair, which older ECs read as a
# request for "smart charge", cannot get through here.
sbcm_arm() {
    local pair="$1" mode start stop arg
    mode=$(preset_mode "$pair") || return 1
    (( mode > 0 )) || return 1
    [[ -w "$WMI_DBG/arg" && -r "$WMI_DBG/call" ]] || return 1
    start=${pair% *}; stop=${pair#* }
    printf -v arg '0x%02x%02x48%02x1503' "$stop" "$start" "$mode"
    echo "$arg" > "$WMI_DBG/arg"
    # The first read of `call` returns the previous call's result. Read twice.
    cat "$WMI_DBG/call" >/dev/null
    cat "$WMI_DBG/call" >/dev/null
}

# apply_preset <pair>
# Write the pair through the sysfs node, then read EC 0x85 back. If the EC did
# not arm itself and this is an armed preset, repeat the request through \SBCM.
# Sets APPLIED_MODE to the final EC mode (or "unknown" when the EC cannot be
# read) and APPLIED_VIA to sbtt or sbcm so the caller can say which one worked.
APPLIED_MODE=unknown
APPLIED_VIA=sbtt
apply_preset() {
    local pair="$1" mode
    echo "$pair" > "$NODE"
    APPLIED_MODE=unknown
    APPLIED_VIA=sbtt
    mode=$(ec_mode) || return 0
    if [[ "${mode:-0}" == "0" && "$pair" != "0 100" ]] && sbcm_arm "$pair"; then
        APPLIED_VIA=sbcm
        mode=$(ec_mode) || return 0
    fi
    APPLIED_MODE="${mode:-0}"
}

main() {
    [[ -r "$CONF" ]] || exit 0
    # shellcheck source=/dev/null
    . "$CONF"
    [[ -n "${CHARGE_PRESET:-}" ]] || exit 0
    [[ -w "$NODE" ]] || { echo "no $NODE, is huawei-wmi loaded?" >&2; exit 1; }

    local mode
    apply_preset "$CHARGE_PRESET"
    mode="$APPLIED_MODE"
    case "$mode" in
        unknown) ;;
        0)
            if [[ "$CHARGE_PRESET" != "0 100" ]]; then
                echo "warning: wrote '$CHARGE_PRESET' but the EC did not arm (charge mode 0)." >&2
                echo "         Only the presets in /etc/honor-battery.conf are enforced." >&2
            fi ;;
        *)
            if [[ "$APPLIED_VIA" == sbcm ]]; then
                echo "EC armed through SBCM (charge mode $mode); the sysfs write alone was ignored."
            fi ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
