# shellcheck shell=bash
#
# Device profile parser and the trust tiers that decide what an installer is
# allowed to do. Source this, do not execute it.
#
# A profile is strict key=value. It is PARSED, never sourced: profiles arrive
# through issues from people we do not know, and `source`-ing one would be
# arbitrary code execution as root.
#
# Comments are whole lines beginning with '#'. There are no inline comments, so
# a '#' inside a value is just a character.

# --- schema -------------------------------------------------------------------
PROFILE_KEYS=(
    # identity and trust
    model name year platform dgpu
    status origin verified_kernel verified_bios verified_distro
    dmi_vendor dmi_product dmi_sku dmi_board dmi_board_version
    # hardware inventory: facts, all of them fillable from a hardware dump
    touchscreen_hid touchpad_hid audio_ssid fingerprint_usb
    panel backlight_max ec_fan0 ec_fan1 battery_charge_presets camera_usb
    # fix parameters: not readable off the machine. Somebody had to measure or
    # choose these with that laptop in front of them, which is the difference
    # between a reported profile and a verified one.
    param_backlight_min param_audio_fixup
    # which fixes apply
    fixes
)

# --- trust tiers --------------------------------------------------------------
# A  Derives its inputs from the running machine, or matches on a device id and
#    simply finds nothing on hardware it was not meant for. Safe to offer on a
#    profile nobody has verified.
# B  Carries model specific constants. Getting them wrong misconfigures real
#    hardware, so these need status=verified.
# C  Installs a binary taken from one machine's firmware, with no way to check
#    at run time that it belongs there.
#
# oled-backlight looks like tier A because it reads the VBT off the running
# machine, but backlight_min was measured on one panel. Until somebody measures
# it on theirs it is tier B.
#
# acpi-override is tier A, which needs explaining because it installs firmware.
# It does not decide from the profile. Before installing anything it finds the
# live table by its OEM table id and compares the md5 against the stock table
# this repository carries, and refuses unless they are equal. That is a direct
# measurement of the running machine and it is strictly stronger than asking
# which model this is: the I2C_DEVT table turns out to be byte-identical between
# ZQC-P and XWC-P, so the model was never the thing that mattered. A profile
# still has to list the fix for it to run at all.
# -g because this file may be sourced from inside a function, where a plain
# `declare` would make the array local and it would vanish on return.
declare -gA FIX_TIER=(
    [micmute]=A
    [touchpad-edge]=A
    [fingerprint]=A
    [cdclk-ptl]=A
    [psr-band]=A
    [edp-dsc]=A
    [auto-rebuild]=A
    [headset-mic]=B
    [sof-audio]=B
    [battery]=B
    [hotkeys]=B
    [hotkey-actions]=A
    [keyboard-backlight]=B
    [fan-curve]=B
    [fan]=B
    [oled-backlight]=B
    [acpi-override]=A
)

declare -gA PROFILE=()
PROFILE_FILE=""

_profile_err() { printf 'profile: %s\n' "$*" >&2; }

# profile_load <file>  -> 0 on success, 1 on a malformed file
profile_load() {
    local file="$1" lineno=0 line key val known
    [[ -r "$file" ]] || { _profile_err "cannot read $file"; return 1; }

    PROFILE=()
    PROFILE_FILE="$file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))

        # trim both ends
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        if [[ "$line" == \#* ]]; then
            # A device profile is data. Everything that needs explaining belongs
            # in docs/hardware/<model>.md, so that a diff of a profile stays
            # readable and one fact does not end up recorded in two places that
            # then drift apart. TEMPLATE.conf is the exception: it exists to be
            # read, and its comments are the field reference.
            if [[ "$(basename "$file")" != "TEMPLATE.conf" && -z "${PROFILE_QUIET:-}" ]]; then
                printf 'profile: %s:%s: comment in a device profile.\n' "$file" "$lineno" >&2
                printf '    Profiles carry data. The explanation belongs in docs/hardware/.\n' >&2
            fi
            continue
        fi
        [[ -z "$line" ]] && continue

        if [[ "$line" != *=* ]]; then
            _profile_err "$file:$lineno: not a key=value line: $line"
            return 1
        fi

        key="${line%%=*}"
        val="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"

        if [[ ! "$key" =~ ^[a-z][a-z0-9_]*$ ]]; then
            _profile_err "$file:$lineno: bad key name '$key'"
            return 1
        fi

        known=0
        for k in "${PROFILE_KEYS[@]}"; do
            [[ "$k" == "$key" ]] && { known=1; break; }
        done
        if (( ! known )); then
            _profile_err "$file:$lineno: unknown key '$key'.
    A typo here would silently drop a value, so it is an error, not a warning.
    Valid keys are listed in devices/TEMPLATE.conf."
            return 1
        fi

        # Values end up as arguments to installers that run as root. A profile
        # is never sourced, so this cannot execute on its own, but keeping the
        # charset boring means a value can never grow teeth downstream either.
        if [[ ! "$val" =~ ^[A-Za-z0-9\ _.,:+/()-]*$ ]]; then
            _profile_err "$file:$lineno: value of '$key' contains characters that are not allowed here.
    Permitted: letters, digits, space, and _ . , : + / ( ) -"
            return 1
        fi

        PROFILE["$key"]="$val"
    done < "$file"

    profile_validate || return 1
}

# profile_validate -> 0 if the loaded profile makes sense
profile_validate() {
    local f
    for f in model dmi_vendor dmi_product status; do
        if [[ -z "${PROFILE[$f]:-}" ]]; then
            _profile_err "${PROFILE_FILE}: '$f' is required and is empty"
            return 1
        fi
    done

    case "${PROFILE[status]}" in
        verified|reported|probed|draft) ;;
        *) _profile_err "${PROFILE_FILE}: status must be verified, reported, probed or draft, got '${PROFILE[status]}'"
           return 1 ;;
    esac

    case "${PROFILE[platform]:-unknown}" in
        pantherlake|arrowlake|meteorlake|raptorlake|amd|unknown) ;;
        *) _profile_err "${PROFILE_FILE}: unrecognised platform '${PROFILE[platform]}'"
           return 1 ;;
    esac

    case "${PROFILE[dgpu]:-unknown}" in
        none|nvidia|unknown) ;;
        *) _profile_err "${PROFILE_FILE}: dgpu must be none, nvidia or unknown, got '${PROFILE[dgpu]}'"
           return 1 ;;
    esac

    local fix
    for fix in ${PROFILE[fixes]:-}; do
        if [[ -z "${FIX_TIER[$fix]:-}" ]]; then
            _profile_err "${PROFILE_FILE}: fixes lists '$fix', which has no trust tier.
    Add it to FIX_TIER in lib/profile.sh before listing it here."
            return 1
        fi
    done
}

# profile_get <key> -> value, empty if unset
profile_get() { printf '%s' "${PROFILE[$1]:-}"; }

# profile_has <key> -> 0 if the key carries a real value
profile_has() {
    local v="${PROFILE[$1]:-}"
    [[ -n "$v" && "$v" != unknown ]]
}

# profile_lists_fix <fix> -> 0 if this model declares the fix as applicable
profile_lists_fix() {
    local fix want="$1"
    for fix in ${PROFILE[fixes]:-}; do
        [[ "$fix" == "$want" ]] && return 0
    done
    return 1
}

# fix_allowed <fix> -> 0 if it may run against the loaded profile.
#
# Everything is allowed on a verified profile. On reported, probed and draft
# only tier A, which by construction cannot carry another machine's constants.
#
# probed is the weakest of the three that carry real data: the ids came out of
# a hardware probe database, so they are genuine readings off a real machine,
# but nobody has run a single fix against one. It is deliberately no more
# permissive than draft.
fix_allowed() {
    local tier="${FIX_TIER[$1]:-C}"
    [[ "${PROFILE[status]:-draft}" == verified ]] && return 0
    [[ "$tier" == A ]]
}
