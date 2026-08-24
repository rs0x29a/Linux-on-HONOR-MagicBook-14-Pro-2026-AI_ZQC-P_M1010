#!/usr/bin/env bash
# Safe opt-in selector for the ZQC-P EC fan curve.
# Manual PWM duty control is not exposed by this firmware; this controls the
# validated early-engagement curves through the firmware's IFCI method.

set -u
CONF=/etc/honor-fan-curve.conf
CALL=/proc/acpi/call
STOCK=0xA0

load_config() {
    TARGET=0xA0
    FAILSAFE_TEMP=85
    POLL_SECONDS=5
    [[ -r "$CONF" ]] && . "$CONF"
}

normalise_curve() {
    local c="${1^^}"
    [[ "$c" == 0X* ]] && c="0x${c#0X}"
    printf '%s' "$c"
}

valid_curve() {
    case "$(normalise_curve "$1")" in
        0xA0|0xAA|0xAB) return 0 ;;
        *) return 1 ;;
    esac
}

call_acpi() {
    [[ -w "$CALL" ]] || { echo "acpi_call is unavailable at $CALL" >&2; return 1; }
    printf '%s\n' "$1" > "$CALL"
    cat "$CALL"
}

apply_curve() {
    local curve
    curve="$(normalise_curve "$1")"
    valid_curve "$curve" || { echo "refusing unsafe fan curve: $curve" >&2; return 1; }
    # IFCI reads a buffer with the selector at byte offset 2. The firmware
    # accepts A0..AC; AC is deliberately excluded because it stops both fans.
    local arg="b0000${curve#0x}00"
    local result
    result="$(call_acpi "\\IFCI $arg")" || return 1
    if grep -qiE 'error|fail|not found' <<< "$result"; then
        echo "IFCI rejected $curve: $result" >&2
        return 1
    fi
    printf 'fan curve: %s (%s)\n' "$curve" "$result"
}

reset_curve() { apply_curve "$STOCK"; }

max_temp_c() {
    local z type temp max=0
    for z in /sys/class/thermal/thermal_zone*/; do
        [[ -r "$z/type" && -r "$z/temp" ]] || continue
        type="$(cat "$z/type")"
        [[ "$type" =~ (x86_pkg_temp|coretemp|cpu-thermal|TCPU) ]] || continue
        temp="$(cat "$z/temp" 2>/dev/null)"
        [[ "$temp" =~ ^[0-9]+$ ]] || continue
        (( temp > max )) && max=$temp
    done
    printf '%s\n' "$((max / 1000))"
}

monitor() {
    load_config
    valid_curve "$TARGET" || { echo "invalid TARGET=$TARGET" >&2; return 1; }
    apply_curve "$TARGET" || return 1
    while :; do
        local temp
        temp="$(max_temp_c)"
        if (( temp == 0 )); then
            echo "no CPU thermal sensor found; reverting to stock curve" >&2
            reset_curve || true
            return 1
        fi
        if (( temp >= FAILSAFE_TEMP )); then
            echo "temperature ${temp}C reached failsafe ${FAILSAFE_TEMP}C; reverting to stock"
            reset_curve || true
            sleep 30
        else
            sleep "${POLL_SECONDS:-5}"
        fi
    done
}

load_config
case "${1:-status}" in
    apply) apply_curve "${2:-$TARGET}" ;;
    reset) reset_curve ;;
    monitor) monitor ;;
    status)
        echo "configured target: $(normalise_curve "$TARGET")"
        echo "failsafe: ${FAILSAFE_TEMP}C"
        call_acpi '\\GFCI b000000' || true
        ;;
    *) echo "usage: $0 {apply [0xA0|0xAA|0xAB]|reset|monitor|status}" >&2; exit 2 ;;
esac
