# shellcheck shell=bash
#
# The parts of an installer that differ between distributions.
#
# Where a fact can be observed rather than inferred, it is observed: the module
# compression is read off the distribution's own modules, not looked up by
# distribution name. That way a distribution nobody here has ever run still
# gets the right answer.
#
# Every function reports failure clearly instead of guessing. A wrong guess in
# here ends with an initramfs that was never rebuilt, or a kernel command line
# edited in a file the bootloader does not read.

_distro_say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
_distro_warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

# --- identity -----------------------------------------------------------------

# arch | debian | fedora | suse | unknown
distro_family() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-}")"
        like="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}")"
    fi
    case " $id $like " in
        *" arch "*|*" archlinux "*) echo arch ;;
        *" debian "*|*" ubuntu "*)  echo debian ;;
        *" fedora "*|*" rhel "*)    echo fedora ;;
        *" suse "*|*" opensuse "*)  echo suse ;;
        *)
            # ID_LIKE is not always set; fall back to the package manager.
            if   command -v pacman  >/dev/null; then echo arch
            elif command -v apt-get >/dev/null; then echo debian
            elif command -v dnf     >/dev/null; then echo fedora
            elif command -v zypper  >/dev/null; then echo suse
            else echo unknown; fi ;;
    esac
}

# --- packages -----------------------------------------------------------------

distro_pkg_install() {
    (( $# )) || return 0
    case "$(distro_family)" in
        arch)   pacman -S --needed --noconfirm "$@" ;;
        debian) apt-get update -qq && apt-get install -y "$@" ;;
        fedora) dnf install -y "$@" ;;
        suse)   zypper --non-interactive install "$@" ;;
        *)      _distro_warn "no known package manager; install these yourself: $*"
                return 1 ;;
    esac
}

# distro_kernel_headers_pkg <kver> -> the package name providing that kernel's
# headers, empty if it cannot be worked out.
distro_kernel_headers_pkg() {
    local kver="$1"
    case "$(distro_family)" in
        arch)
            local kpkg
            kpkg=$(pacman -Qqo "/usr/lib/modules/${kver}/vmlinuz" 2>/dev/null | head -1 || true)
            [[ -n "$kpkg" ]] && printf '%s-headers' "$kpkg" ;;
        debian) printf 'linux-headers-%s' "$kver" ;;
        fedora) printf 'kernel-devel-%s' "$kver" ;;
        suse)   printf 'kernel-devel' ;;
    esac
    # Always succeed. "Cannot be worked out" is an empty string, not a failure:
    # callers assign this in `PKG="$(distro_kernel_headers_pkg …)"`, and under
    # `set -e` a non-zero return there would abort the installer instead of
    # letting it print the advice it has ready for exactly that case.
    return 0
}

# --- kernel config ------------------------------------------------------------

# Where the running or given kernel's .config can be read. Arch enables
# CONFIG_IKCONFIG_PROC and ships /proc/config.gz; Debian and Ubuntu do not, and
# put it in /boot instead.
distro_kernel_config_path() {
    local kver="${1:-$(uname -r)}"
    if [[ "$kver" == "$(uname -r)" && -r /proc/config.gz ]]; then
        echo /proc/config.gz; return 0
    fi
    local c
    for c in "/boot/config-${kver}" \
             "/usr/lib/modules/${kver}/build/.config" \
             "/lib/modules/${kver}/build/.config" \
             "/usr/lib/modules/${kver}/config"; do
        [[ -r "$c" ]] && { echo "$c"; return 0; }
    done
    return 1
}

# Print the config, decompressing if needed.
distro_kernel_config_cat() {
    local p
    p="$(distro_kernel_config_path "${1:-}")" || return 1
    case "$p" in
        *.gz) zcat "$p" ;;
        *)    cat "$p" ;;
    esac
}

# distro_kernel_config_has <CONFIG_FOO=y> [kver]
#
# Deliberately not `... | grep -q`: grep -q exits at the first match, the
# decompressor upstream of it dies of SIGPIPE, and under `set -o pipefail`,
# which every installer here uses, the pipeline then reports failure even
# though the option was found. Read the config once, match against it after.
distro_kernel_config_has() {
    local cfg
    cfg="$(distro_kernel_config_cat "${2:-}" 2>/dev/null)" || return 1
    [[ -n "$cfg" ]] || return 1
    grep -q "^$1\$" <<< "$cfg"
}

# --- modules ------------------------------------------------------------------

distro_module_dir() {
    local kver="${1:-$(uname -r)}"
    [[ -d "/usr/lib/modules/${kver}" ]] && { echo "/usr/lib/modules/${kver}"; return 0; }
    [[ -d "/lib/modules/${kver}" ]]     && { echo "/lib/modules/${kver}"; return 0; }
    return 1
}

# Read the compression off the distribution's own modules rather than assuming
# it from the distribution name: Arch uses .ko.zst, Debian .ko or .ko.xz
# depending on release, and both change over time.
distro_module_suffix() {
    local kver="${1:-$(uname -r)}" dir f
    dir="$(distro_module_dir "$kver")" || { echo ".ko"; return 0; }
    f="$(find "${dir}/kernel" -name '*.ko*' -print -quit 2>/dev/null || true)"
    case "$f" in
        *.ko.zst) echo ".ko.zst" ;;
        *.ko.xz)  echo ".ko.xz" ;;
        *.ko.gz)  echo ".ko.gz" ;;
        *)        echo ".ko" ;;
    esac
}

# distro_module_install <built.ko> <name> [kver]
# Compresses to match the distribution and drops the result into the modules
# updates/ overlay, which depmod searches before kernel/.
distro_module_install() {
    local built="$1" name="$2" kver="${3:-$(uname -r)}" dir suffix dest
    dir="$(distro_module_dir "$kver")" || { _distro_warn "no module tree for $kver"; return 1; }
    suffix="$(distro_module_suffix "$kver")"
    dest="${dir}/updates/${name}${suffix}"
    install -d "${dir}/updates"
    case "$suffix" in
        .ko.zst) zstd -q -f -19 -T0 "$built" -o "$dest" ;;
        .ko.xz)  xz -T0 -c "$built" > "$dest" ;;
        .ko.gz)  gzip -c "$built" > "$dest" ;;
        *)       install -m644 "$built" "$dest" ;;
    esac
    chmod 644 "$dest"
    depmod -a "$kver"
    printf '%s' "$dest"
}

# --- initramfs ----------------------------------------------------------------

distro_initramfs_rebuild() {
    if command -v limine-mkinitcpio >/dev/null; then
        _distro_say "rebuilding initramfs (limine-mkinitcpio)"; limine-mkinitcpio
    elif command -v limine-update >/dev/null; then
        _distro_say "rebuilding initramfs (limine-update)"; limine-update
    elif command -v mkinitcpio >/dev/null; then
        _distro_say "rebuilding initramfs (mkinitcpio -P)"; /usr/bin/mkinitcpio -P
    elif command -v update-initramfs >/dev/null; then
        _distro_say "rebuilding initramfs (update-initramfs)"; update-initramfs -u -k all
    elif command -v dracut >/dev/null; then
        _distro_say "rebuilding initramfs (dracut)"; dracut --force --regenerate-all
    else
        _distro_warn "no initramfs generator found; rebuild it yourself before rebooting"
        return 1
    fi
}

# --- kernel command line ------------------------------------------------------

# The file that owns the default kernel command line, and how to apply a change
# to it. Limine keeps it in an array assignment, GRUB in a plain variable, so
# the two need different edits rather than one clever regex.
distro_cmdline_file() {
    local f
    for f in /etc/default/limine /etc/default/grub /etc/kernel/cmdline; do
        [[ -f "$f" ]] && { echo "$f"; return 0; }
    done
    return 1
}

# Which assignment in that file actually owns the command line. Dispatching on
# the content rather than the filename: a distribution is free to call the file
# what it likes, and both Limine and GRUB are found by what they contain.
# Which shape is this file? The last case, `plain`, means a bare one-line
# command line as systemd-boot's /etc/kernel/cmdline holds. That one is
# rewritten wholesale, so it must be recognised positively and never used as a
# fallback: a /etc/default/limine that only defines a per-kernel key, or a grub
# config whose GRUB_CMDLINE_* lines are commented out, matches none of the
# greps above and would otherwise be flattened onto a single line, taking
# root= and rootflags= with it.
_cmdline_var() {
    local f="$1"
    # /etc/kernel/cmdline is the whole command line and nothing else. Decide it
    # by path, not by content: its contents legitimately look like assignments
    # (`root=UUID=...`), so no content test can tell it from a shell config.
    [[ "$f" == */kernel/cmdline ]]                         && { echo plain;  return; }
    grep -qE '^KERNEL_CMDLINE\[[^]]*\]\+?=' "$f"          && { echo limine; return; }
    grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' "$f"           && { echo grub;   return; }
    grep -qE '^GRUB_CMDLINE_LINUX=' "$f"                   && { echo grub2;  return; }
    echo unknown
}

# distro_cmdline_add <param>   idempotent
distro_cmdline_add() {
    local param="$1" f kind key
    f="$(distro_cmdline_file)" || { _distro_warn "no kernel command line file found; add '$param' yourself"; return 1; }
    if grep -qF -- "$param" "$f"; then
        _distro_say "cmdline already contains $param"
        return 0
    fi
    kind="$(_cmdline_var "$f")"
    case "$kind" in
        limine) key='KERNEL_CMDLINE\[[^]]*\]\+?=' ;;
        grub)   key='GRUB_CMDLINE_LINUX_DEFAULT=' ;;
        grub2)  key='GRUB_CMDLINE_LINUX=' ;;
        plain)  # systemd-boot's /etc/kernel/cmdline: the whole file is the
                # command line, so rewriting it whole is correct here and only
                # here. _cmdline_var recognises this shape positively.
                printf '%s %s\n' "$(tr -d '\n' < "$f")" "$param" > "${f}.tmp"
                mv "${f}.tmp" "$f"
                grep -qF -- "$param" "$f" \
                    || { _distro_warn "failed to add '$param' to $f; add it yourself"; return 1; }
                _distro_say "added $param to $f"
                return 0 ;;
        *)      _distro_warn "$f is a bootloader config in a shape this does not
    recognise, so it will not be edited. Add '$param' to your kernel command
    line yourself and re-run."
                return 1 ;;
    esac
    # Both quote styles, and an empty value, have to work: a fresh Ubuntu ships
    # GRUB_CMDLINE_LINUX_DEFAULT="quiet splash" but an edited one may be empty
    # or single quoted.
    sed -i -E "s|^(${key}\")([^\"]*)(\")$|\1\2 ${param}\3|; \
               s|^(${key}')([^']*)(')$|\1\2 ${param}\3|" "$f"
    # That leaves a leading space when the value was empty; tidy it.
    sed -i -E "s|^(${key}[\"'])[[:space:]]+|\1|" "$f"
    grep -qF -- "$param" "$f" || { _distro_warn "failed to add '$param' to $f; add it yourself"; return 1; }
    _distro_say "added $param to $f"
}

# distro_cmdline_remove <sed-safe pattern>
# distro_cmdline_remove <extended-regex>
#
# The delimiter is \001, not '|'. It has to be a character that cannot occur in
# a caller's pattern, and '|' can: an alternation like '(xe|i915)\.enable_psr=.'
# is exactly the kind of pattern this is for, and with '|' as the delimiter sed
# fails with "unknown option to `s'" and the parameter silently stays on the
# command line.
distro_cmdline_remove() {
    # Not named 'd'. bash scoping is dynamic, so a short local here shadows the
    # caller's variable of the same name for the whole call, including inside
    # distro_cmdline_file.
    local pattern="$1" f _cmdline_delim=$'\001'
    f="$(distro_cmdline_file)" || return 0
    sed -i -E "s${_cmdline_delim}[[:space:]]*${pattern}${_cmdline_delim}${_cmdline_delim}g" "$f"
}

distro_bootloader_update() {
    if   command -v limine-update >/dev/null; then limine-update
    elif command -v update-grub   >/dev/null; then update-grub
    elif command -v grub-mkconfig >/dev/null; then grub-mkconfig -o /boot/grub/grub.cfg
    elif command -v bootctl       >/dev/null; then bootctl update >/dev/null 2>&1 || true
    else _distro_warn "update your bootloader configuration by hand"; return 1; fi
}

# --- hooks that run after a kernel package update ------------------------------

# Arch has pacman hooks; Debian has /etc/kernel/postinst.d, which is the same
# idea and is what the distribution's own DKMS integration uses.
distro_kernel_hook_supported() {
    case "$(distro_family)" in
        arch)   [[ -d /etc/pacman.d ]] ;;
        debian) [[ -d /etc/kernel ]] ;;
        fedora) command -v systemctl >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
}

# --- ACPI table overrides -----------------------------------------------------
#
# The kernel reads table overrides only from an *early*, uncompressed CPIO
# containing kernel/firmware/acpi/<name>.aml. Everything below is about getting
# one in front of the real initramfs; the .aml itself is identical either way.
# See Documentation/admin-guide/acpi/initrd_table_override.rst.
#
# Two mechanisms exist and they are not interchangeable:
#
#   mkinitcpio   an install hook calls add_file_early, and mkinitcpio builds the
#                early CPIO itself. Arch and everything derived from it
#   early-cpio   the CPIO is built here and handed to the bootloader as an
#                additional initrd image. Debian and Ubuntu, through
#                GRUB_EARLY_INITRD_LINUX_CUSTOM, which their /etc/grub.d/10_linux
#                has honoured for years
#
# Both stage from /usr/lib/firmware/acpi/, so the installer copies the .aml
# there once and does not care which mechanism follows.

ACPI_FW_DIR=/usr/lib/firmware/acpi
ACPI_EARLY_CPIO=/boot/acpi_override.cpio
ACPI_GRUB_KEY=GRUB_EARLY_INITRD_LINUX_CUSTOM

# distro_acpi_override_style -> mkinitcpio | early-cpio | none
distro_acpi_override_style() {
    if command -v mkinitcpio >/dev/null; then echo mkinitcpio; return 0; fi
    if [[ -f /etc/default/grub ]] && [[ -d /etc/grub.d ]] \
       && grep -rqs "$ACPI_GRUB_KEY" /etc/grub.d/; then echo early-cpio; return 0; fi
    echo none; return 1
}

# distro_acpi_override_install
#   Stages whatever is already in /usr/lib/firmware/acpi/*.aml. Idempotent.
#   Does NOT rebuild the initramfs or the bootloader config: the caller batches
#   those, because several fixes edit the same files.
distro_acpi_override_install() {
    local style; style="$(distro_acpi_override_style)"
    local -a amls=()
    local f
    for f in "$ACPI_FW_DIR"/*.aml; do [[ -f "$f" ]] && amls+=("$f"); done
    if (( ! ${#amls[@]} )); then
        _distro_warn "no .aml in $ACPI_FW_DIR; nothing to stage"
        return 1
    fi

    case "$style" in
    mkinitcpio)
        # The install hook is what stages the files; the caller installs it and
        # adds acpi_override to HOOKS=. Nothing to do here.
        _distro_say "ACPI override: mkinitcpio early CPIO"
        return 0 ;;

    early-cpio)
        command -v cpio >/dev/null || {
            _distro_warn "cpio is not installed, and the early CPIO cannot be built without it.
    Install it (${_DISTRO_PKG_HINT:-apt install cpio}) and re-run."
            return 1; }
        local tmp; tmp="$(mktemp -d)" || return 1
        mkdir -p "$tmp/kernel/firmware/acpi"
        # -p keeps the source timestamps, and the directories are then stamped
        # from the first table. newc records an mtime per entry, so without this
        # every run would produce a different archive and re-running the
        # installer would look like a change when nothing had changed.
        for f in "${amls[@]}"; do install -p -m0644 "$f" "$tmp/kernel/firmware/acpi/"; done
        touch -r "${amls[0]}" "$tmp/kernel" "$tmp/kernel/firmware" "$tmp/kernel/firmware/acpi"
        # -H newc and no compression: the kernel scans the head of the initrd
        # for a plain cpio and stops at the first thing it cannot read.
        # Sorted, so the entry order does not depend on the filesystem either.
        # --renumber-inodes because newc records the inode number, which comes
        # from the staging directory and is different on every run; without it
        # the archive changes byte for byte even when its contents do not.
        # The kernel ignores c_ino except for hardlinks, of which there are none.
        local -a cpio_opts=(-o -H newc --quiet)
        cpio --renumber-inodes --version >/dev/null 2>&1 && cpio_opts+=(--renumber-inodes)
        ( cd "$tmp" && find kernel -print | LC_ALL=C sort | cpio "${cpio_opts[@]}" ) \
            > "${ACPI_EARLY_CPIO}.new" || { rm -rf "$tmp"; return 1; }
        rm -rf "$tmp"
        if [[ -f "$ACPI_EARLY_CPIO" ]] && cmp -s "${ACPI_EARLY_CPIO}.new" "$ACPI_EARLY_CPIO"; then
            rm -f "${ACPI_EARLY_CPIO}.new"
            _distro_say "ACPI override: $ACPI_EARLY_CPIO is already up to date"
        else
            mv "${ACPI_EARLY_CPIO}.new" "$ACPI_EARLY_CPIO"
            chmod 0644 "$ACPI_EARLY_CPIO"
            _distro_say "ACPI override: built $ACPI_EARLY_CPIO ($(stat -c%s "$ACPI_EARLY_CPIO") bytes, ${#amls[@]} table(s))"
        fi

        # Hand it to GRUB as an extra initrd, ahead of the real one. The value
        # is a space separated list of names relative to /boot, and other things
        # may already be in it, so merge rather than overwrite.
        local base; base="$(basename "$ACPI_EARLY_CPIO")"
        local cur=""
        if grep -qE "^[[:space:]]*${ACPI_GRUB_KEY}=" /etc/default/grub; then
            cur="$(sed -nE "s/^[[:space:]]*${ACPI_GRUB_KEY}=[\"']?([^\"']*)[\"']?.*/\1/p" /etc/default/grub | head -1)"
        fi
        case " $cur " in
            *" $base "*) _distro_say "ACPI override: $ACPI_GRUB_KEY already lists $base" ;;
            *)
                local new; new="$(printf '%s %s' "$cur" "$base")"
                new="${new#"${new%%[![:space:]]*}"}"
                if grep -qE "^[[:space:]]*${ACPI_GRUB_KEY}=" /etc/default/grub; then
                    sed -i -E "s|^[[:space:]]*${ACPI_GRUB_KEY}=.*|${ACPI_GRUB_KEY}=\"${new}\"|" /etc/default/grub
                else
                    printf '\n# Added by the HONOR MagicBook fixes: early ACPI table override.\n%s="%s"\n' \
                        "$ACPI_GRUB_KEY" "$new" >> /etc/default/grub
                fi
                _distro_say "ACPI override: $ACPI_GRUB_KEY=\"$new\" in /etc/default/grub" ;;
        esac
        return 0 ;;

    *)
        _distro_warn "no ACPI table override mechanism found on this system.
    The kernel needs the .aml inside an early, uncompressed CPIO. See
    Documentation/admin-guide/acpi/initrd_table_override.rst and do it by hand;
    the tables are staged in $ACPI_FW_DIR."
        return 1 ;;
    esac
}

# distro_acpi_override_remove
#   Undoes distro_acpi_override_install. Leaves /usr/lib/firmware/acpi alone;
#   the caller owns those files.
distro_acpi_override_remove() {
    local base; base="$(basename "$ACPI_EARLY_CPIO")"
    [[ -f "$ACPI_EARLY_CPIO" ]] && { rm -f "$ACPI_EARLY_CPIO"; _distro_say "removed $ACPI_EARLY_CPIO"; }
    if [[ -f /etc/default/grub ]] && grep -qE "^[[:space:]]*${ACPI_GRUB_KEY}=" /etc/default/grub; then
        local cur new
        cur="$(sed -nE "s/^[[:space:]]*${ACPI_GRUB_KEY}=[\"']?([^\"']*)[\"']?.*/\1/p" /etc/default/grub | head -1)"
        new="$(printf '%s' "$cur" | tr ' ' '\n' | grep -vxF "$base" | tr '\n' ' ')"
        new="${new%"${new##*[![:space:]]}"}"
        if [[ -z "$new" ]]; then
            # We are the only entry, and we are the one who added the line.
            sed -i -E "/^[[:space:]]*${ACPI_GRUB_KEY}=/d;/^# Added by the HONOR MagicBook fixes: early ACPI table override\.$/d" /etc/default/grub
            _distro_say "removed $ACPI_GRUB_KEY from /etc/default/grub"
        else
            sed -i -E "s|^[[:space:]]*${ACPI_GRUB_KEY}=.*|${ACPI_GRUB_KEY}=\"${new}\"|" /etc/default/grub
            _distro_say "$ACPI_GRUB_KEY=\"$new\" in /etc/default/grub"
        fi
    fi
    return 0
}

# --- naming a package in the local dialect ------------------------------------
#
# For error messages only. An installer that needs clang and udev-hid-bpf should
# tell you how to get them on the machine you are actually on, not on the one
# this repository was written on.
#
# distro_pkg_hint <generic-name>...
#   -> a ready-to-paste install command, or a plain list if the distribution is
#      not one we know the package names for.
distro_pkg_hint() {
    local -a want=("$@") pkgs=()
    local n
    case "$(distro_family)" in
    arch)
        for n in "${want[@]}"; do
            case "$n" in
                clang)        pkgs+=(clang) ;;
                bpftool)      pkgs+=(bpf) ;;
                udev-hid-bpf) pkgs+=(udev-hid-bpf) ;;
                curl)         pkgs+=(curl) ;;
                make|gcc)     pkgs+=(base-devel) ;;
                cpio)         pkgs+=(cpio) ;;
                python3)      pkgs+=(python) ;;
                udevadm)      pkgs+=(systemd) ;;
                *)            pkgs+=("$n") ;;
            esac
        done
        printf 'pacman -S --needed %s' "$(printf '%s\n' "${pkgs[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')" ;;
    debian)
        for n in "${want[@]}"; do
            case "$n" in
                clang)        pkgs+=(clang) ;;
                bpftool)      pkgs+=(bpftool) ;;
                udev-hid-bpf) pkgs+=(udev-hid-bpf) ;;
                curl)         pkgs+=(curl) ;;
                make|gcc)     pkgs+=(build-essential) ;;
                cpio)         pkgs+=(cpio) ;;
                python3)      pkgs+=(python3) ;;
                udevadm)      pkgs+=(udev) ;;
                *)            pkgs+=("$n") ;;
            esac
        done
        printf 'apt install %s' "$(printf '%s\n' "${pkgs[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')" ;;
    fedora)
        for n in "${want[@]}"; do
            case "$n" in
                bpftool)  pkgs+=(bpftool) ;;
                make|gcc) pkgs+=(gcc make) ;;
                *)        pkgs+=("$n") ;;
            esac
        done
        printf 'dnf install %s' "$(printf '%s\n' "${pkgs[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')" ;;
    *)
        printf 'install: %s' "${want[*]}" ;;
    esac
}
