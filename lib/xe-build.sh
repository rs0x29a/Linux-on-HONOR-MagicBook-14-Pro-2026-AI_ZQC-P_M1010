# shellcheck shell=bash
#
# Rebuilding xe.ko with the patches this repository carries. Source this from
# an installer, do not execute it.
#
# There is one xe.ko and there are several fixes that live inside it. Each of
# them used to be free to build and install its own copy, which works exactly
# until the second one exists: whichever installer ran last would produce a
# module carrying only its own change and silently drop the other. So the
# build belongs here, once, and it always carries every patch that applies to
# this machine no matter which installer asked for it.
#
# Requires lib/gate.sh to have run first: PROFILE has to be loaded, because
# whether a patch belongs in the module is a per-model question.

XE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_xe_log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
_xe_warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
_xe_die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# --- the registry -------------------------------------------------------------
# fix name -> the patch file inside patch/<fix>/. Order matters only in that
# they are applied in it; these two touch different files.
declare -gA XE_FIX_PATCH=(
    [cdclk-ptl]="0001-drm-i915-cdclk-avoid-spurious-cdclk-sanitization-on-PTL.patch"
    [edp-dsc]="0001-drm-i915-dp-prefer-DSC-over-driving-eDP-below-8-bpc.patch"
)

# Whether the tree already carries the fix *by some other route than our patch*.
# This hook exists only for the case where upstream solved the same problem in
# a different shape, so that the patch neither applies nor reverse-applies and
# there is nothing else to detect it by. It is optional: a fix without one is
# handled entirely by the apply/reverse-apply test below.
#
# The marker must be something our own patch does NOT introduce. Grepping for a
# string the patch itself adds makes every tree that already has the patch look
# like a tree that no longer needs it, and the fix then quietly drops out of the
# module while the build still succeeds. tools/selftest.sh checks this.
_xe_obsolete_cdclk_ptl() {
    # Upstream took a different shape: commit 1786d2688781 introduced a
    # has_cd2x_pipe_select() helper instead of guarding the two sites. Our
    # patch does not add that name anywhere.
    grep -q 'has_cd2x_pipe_select' \
        "$1/drivers/gpu/drm/i915/display/intel_cdclk.c" 2>/dev/null
}
# edp-dsc has no hook on purpose. It is not upstream in any shape, so there is
# nothing to detect, and the only marker available would be one of its own.

# xe_wanted_fixes
# The fixes this machine wants in its xe.ko, from the profile alone. Answerable
# without a source tree, which is what lets the "already built" check run before
# a quarter of a gigabyte is downloaded.
#
# XE_SKIP is a space separated list of fixes to leave out, XE_ONLY the
# complementary allow-list. apply_patch.sh uses
# it to keep the per-fix opt-in flags meaningful: the build is one job, but
# somebody who asked for one of these patches has not thereby asked for the
# other.
xe_wanted_fixes() {
    local fix file
    for fix in "${!XE_FIX_PATCH[@]}"; do
        file="${XE_ROOT}/patch/${fix}/${XE_FIX_PATCH[$fix]}"
        profile_lists_fix "$fix" || continue
        fix_allowed "$fix"       || continue
        [[ " ${XE_SKIP:-} " == *" $fix "* ]] && continue
        # XE_ONLY is the mirror image, an allow-list. The post-update rebuild
        # uses it to reproduce exactly the set that was installed before, which
        # is recorded in /var/lib/honor/xe-module.stamp, rather than whatever
        # the profile would ask for today.
        [[ -n "${XE_ONLY:-}" && " ${XE_ONLY} " != *" $fix "* ]] && continue
        [[ -r "$file" ]]         || { _xe_warn "patch/$fix: $file is missing, skipping"; continue; }
        printf '%s\n' "$fix"
    done | sort
}

# xe_patch_set <srcdir>
# The same list narrowed to what this particular tree still needs, as
# "fix<TAB>patchfile" lines.
xe_patch_set() {
    local src="$1" fix file
    while read -r fix; do
        [[ -n "$fix" ]] || continue
        file="${XE_ROOT}/patch/${fix}/${XE_FIX_PATCH[$fix]}"
        if declare -F "_xe_obsolete_${fix//-/_}" >/dev/null \
           && "_xe_obsolete_${fix//-/_}" "$src"; then
            _xe_warn "patch/$fix: this kernel already carries the fix, skipping"
            continue
        fi
        printf '%s\t%s\n' "$fix" "$file"
    done < <(xe_wanted_fixes)
}

# xe_build_install <requesting fix>
#
# Env knobs, all honoured from the caller's environment:
#   KVER=...     build for another installed kernel (default: the running one)
#   JOBS=N       parallel compile jobs
#   WORKDIR=...  where to unpack the source
#   KEEP_SRC=1   keep the source tree afterwards
#   REGEN=0      do not regenerate the initramfs (the caller will)
xe_build_install() {
    local caller="$1"
    local KVER="${KVER:-$(uname -r)}"
    local JOBS="${JOBS:-$(nproc)}"
    # cdclk-ptl and edp-dsc are two doors into this one function, the work
    # directory below is a fixed path, and both write the same xe.ko. The
    # per-fix lock in honor_gate does not cover that, because the two runs hold
    # different fix locks.
    honor_lock xe-module
    local WORKDIR="${WORKDIR:-/var/tmp/honor-xe}"
    local KEEP_SRC="${KEEP_SRC:-0}"
    local REGEN="${REGEN:-1}"
    local MODDIR="/usr/lib/modules/${KVER}"
    local KBASE="${KVER%%-*}"
    local MAKEVARS=() NEED=() SRCDIR="" t

    [[ -d "$MODDIR" ]] || _xe_die "no module tree for kernel $KVER"

    # --- toolchain ------------------------------------------------------------
    # The module has to be built with the same compiler family as the kernel,
    # otherwise the LTO objects do not match.
    distro_kernel_config_path "$KVER" >/dev/null \
        || _xe_die "no kernel config available for $KVER.
    Expected /proc/config.gz, /boot/config-$KVER or ${MODDIR}/build/.config."

    if distro_kernel_config_has CONFIG_CC_IS_CLANG=y "$KVER"; then
        MAKEVARS=(LLVM=1 LLVM_IAS=1 CC=clang LD=ld.lld)
        NEED=(clang ld.lld llvm-strip llvm-objcopy)
    else
        NEED=(gcc)
    fi
    NEED+=(make bc flex bison zstd curl tar depmod patch)
    for t in "${NEED[@]}"; do
        command -v "$t" >/dev/null || _xe_die "missing required tool: $t"
    done
    command -v pahole >/dev/null || _xe_warn "pahole not found, the module will be built without BTF"
    _xe_log "kernel = $KVER, jobs = $JOBS, toolchain = ${MAKEVARS[*]:-gcc}"

    # Both installers call this, and so does the post-update rebuild hook. If
    # the module on disk was built from this kernel for this same set of fixes,
    # a second compile is pure waiting. Checked here, before the source tree is
    # fetched, because that is the expensive part.
    #
    # The comparison is against the profile's list rather than the list that
    # survived the obsolescence check, because the two only diverge for a given
    # kernel, and a different kernel already fails the kver test above it.
    local want stamp_kver stamp_wanted
    want="$(xe_wanted_fixes | tr '\n' ' ')"; want="${want% }"
    if [[ "${FORCE:-0}" != "1" && -f "${MODDIR}/updates/xe.ko.zst" \
          && -r /var/lib/honor/xe-module.stamp ]]; then
        stamp_kver=$(sed -n 's/^kver=//p'   /var/lib/honor/xe-module.stamp)
        stamp_wanted=$(sed -n 's/^wanted=//p' /var/lib/honor/xe-module.stamp)
        if [[ "$stamp_kver" == "$KVER" && "$stamp_wanted" == "$want" ]]; then
            _xe_log "xe.ko is already built for $KVER for: ${want:-nothing}"
            echo "    requested by '$caller', nothing to do (FORCE=1 to rebuild)"
            return 0
        fi
    fi
    if [[ -z "$want" ]]; then
        _xe_log "no xe patch in this repository is listed for $(profile_get model)"
        return 0
    fi

    # --- source ---------------------------------------------------------------
    # Reuse a tree left behind by the era when patch/cdclk-ptl/ owned this
    # build, rather than making anybody download a quarter of a gigabyte twice.
    if [[ ! -d "$WORKDIR" && -d /var/tmp/honor-cdclk ]]; then
        _xe_log "adopting the existing source tree at /var/tmp/honor-cdclk"
        mv /var/tmp/honor-cdclk "$WORKDIR"
    fi
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || _xe_die "cannot enter $WORKDIR"

    if [[ "$KVER" == *cachyos* ]] && command -v pacman >/dev/null; then
        # CachyOS publishes the fully patched tree as a GitHub release, one per
        # package version. That is byte-for-byte what the running kernel came
        # from.
        local PKG PKGVER TAG
        PKG=$(pacman -Qqo "${MODDIR}/vmlinuz" 2>/dev/null || echo "")
        PKGVER=$(pacman -Q "${PKG:-linux-cachyos}" 2>/dev/null | awk '{print $2}')
        [[ -n "$PKGVER" ]] || _xe_die "cannot determine the linux-cachyos package version"
        TAG="cachyos-${PKGVER}"
        SRCDIR="$TAG"
        if [[ ! -d "$SRCDIR" ]]; then
            _xe_log "downloading CachyOS source tarball $TAG (about 260 MB)"
            curl -fSL --retry 3 -o "${TAG}.tar.gz" \
                "https://github.com/CachyOS/linux/releases/download/${TAG}/${TAG}.tar.gz" \
                || _xe_die "download failed. Check that the release ${TAG} exists."
            _xe_log "unpacking"
            tar xzf "${TAG}.tar.gz"
            rm -f "${TAG}.tar.gz"
        else
            _xe_log "reusing the existing source tree $SRCDIR"
        fi
    else
        local MAJOR="${KBASE%%.*}"
        SRCDIR="linux-${KBASE}"
        if [[ ! -d "$SRCDIR" ]]; then
            _xe_log "downloading vanilla linux-${KBASE} from kernel.org"
            curl -fSL --retry 3 -o "linux-${KBASE}.tar.xz" \
                "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${KBASE}.tar.xz" \
                || _xe_die "download failed"
            tar xf "linux-${KBASE}.tar.xz"
            rm -f "linux-${KBASE}.tar.xz"
        fi
        _xe_warn "building against a vanilla tree. If this distro patches drm/,
    the resulting module may not match the running kernel."
    fi
    cd "$SRCDIR" || _xe_die "cannot enter $WORKDIR/$SRCDIR"

    # --- patches --------------------------------------------------------------
    local -a set=() applied=()
    mapfile -t set < <(xe_patch_set "$PWD")
    if (( ${#set[@]} == 0 )); then
        _xe_log "nothing to build: every xe patch this repository carries is
    either already in $KVER or not listed for $(profile_get model). If an
    overlay from an earlier kernel is still installed, uninstall_patch.sh
    removes it."
        return 0
    fi

    _xe_log "patches going into this module:"
    local line fix file
    for line in "${set[@]}"; do
        fix="${line%%$'\t'*}"; file="${line#*$'\t'}"
        if patch -Np1 -R --dry-run --silent < "$file" >/dev/null 2>&1; then
            echo "    $fix: already in the tree"
        elif patch -Np1 --dry-run --silent < "$file" >/dev/null 2>&1; then
            patch -Np1 --silent < "$file" || _xe_die "patch/$fix failed to apply"
            echo "    $fix: applied"
        else
            _xe_die "patch/$fix does not apply to this tree and is not already
    in it. Either it landed upstream in a shape lib/xe-build.sh does not
    recognise, in which case patch/$fix/ is obsolete, or the source does not
    match the running kernel."
        fi
        applied+=("$fix")
    done

    # --- configure exactly like the running kernel ----------------------------
    _xe_log "restoring the running kernel's config"
    distro_kernel_config_cat "$KVER" > .config

    # vermagic must come out identical or the module will not load. On
    # Arch-like trees the release suffix lives in these two files.
    if [[ -r "${MODDIR}/build/localversion.10-pkgrel" ]]; then
        cp "${MODDIR}/build/"localversion.* .
    else
        printf '%s\n' "-${KVER#"${KBASE}"}" | sed 's/^--/-/' > localversion.90-local
    fi

    # The build has no access to the distro signing key. Signing is off anyway
    # on every machine this repo targets, so an unsigned module loads fine.
    ./scripts/config -d MODULE_SIG_ALL
    make "${MAKEVARS[@]}" olddefconfig >/dev/null
    [[ -r "${MODDIR}/build/Module.symvers" ]] && cp "${MODDIR}/build/Module.symvers" .

    # --- build ----------------------------------------------------------------
    _xe_log "preparing the tree"
    make "${MAKEVARS[@]}" -j"$JOBS" modules_prepare

    _xe_log "building drivers/gpu/drm/xe (a few minutes)"
    nice -n 5 make "${MAKEVARS[@]}" -j"$JOBS" M=drivers/gpu/drm/xe

    local KO="drivers/gpu/drm/xe/xe.ko"
    [[ -f "$KO" ]] || _xe_die "build produced no xe.ko"

    # --- finish the module the way modules_install would ----------------------
    # BTF first, then strip: .BTF is not a .debug section and survives it.
    if [[ "$KVER" == "$(uname -r)" ]] && command -v pahole >/dev/null \
       && [[ -r /sys/kernel/btf/vmlinux ]]; then
        _xe_log "generating module BTF against the running kernel's base BTF"
        LLVM_OBJCOPY=llvm-objcopy pahole -J --btf_base /sys/kernel/btf/vmlinux "$KO" \
            || _xe_warn "BTF generation failed, continuing without it"
    fi

    _xe_log "stripping and compressing"
    if command -v llvm-strip >/dev/null; then llvm-strip --strip-debug "$KO"
    else strip --strip-debug "$KO"; fi
    zstd -q -f -19 -T0 "$KO" -o "${WORKDIR}/xe.ko.zst"

    local NEW_VM OLD_VM
    NEW_VM=$(modinfo "${WORKDIR}/xe.ko.zst" | awk -F': *' '/^vermagic:/{print $2}')
    OLD_VM=$(modinfo -k "$KVER" xe 2>/dev/null | awk -F': *' '/^vermagic:/{print $2}')
    [[ "$NEW_VM" == "$OLD_VM" ]] \
        || _xe_die "vermagic mismatch, refusing to install
    built:   $NEW_VM
    running: $OLD_VM"
    _xe_log "vermagic matches: $NEW_VM"

    # --- install --------------------------------------------------------------
    install -Dm644 "${WORKDIR}/xe.ko.zst" "${MODDIR}/updates/xe.ko.zst"
    depmod "$KVER"
    _xe_log "installed ${MODDIR}/updates/xe.ko.zst carrying: ${applied[*]}"
    echo "    $(modinfo -k "$KVER" xe | grep -E '^filename:')"

    # Record what went in, so a later run of the other installer, or a bug
    # report, can say what this module actually contains.
    mkdir -p /var/lib/honor
    printf '%s\n' "# written by lib/xe-build.sh" \
                  "kver=$KVER" \
                  "srcversion=$(modinfo "${WORKDIR}/xe.ko.zst" | awk -F': *' '/^srcversion:/{print $2}')" \
                  "wanted=$want" \
                  "patches=${applied[*]}" > /var/lib/honor/xe-module.stamp

    # --- initramfs ------------------------------------------------------------
    # xe is pulled into the initramfs by the kms hook, so the early-KMS copy has
    # to be refreshed too, otherwise the stock module lights the panel.
    if [[ "$REGEN" == "1" ]]; then
        _xe_log "regenerating the initramfs"
        distro_initramfs_rebuild || _xe_warn "regenerate the initramfs yourself"
    else
        _xe_log "REGEN=0, the caller will regenerate the initramfs"
    fi

    # --- cleanup --------------------------------------------------------------
    if [[ "$KEEP_SRC" != "1" ]]; then
        _xe_log "removing the source tree (KEEP_SRC=1 to keep it)"
        cd /
        rm -rf "${WORKDIR:?}/${SRCDIR:?}"
    fi
}

# xe_uninstall <fix>
#
# Removes the locally built xe.ko overlay. There is no partial removal: the
# overlay is one module carrying whichever patches were asked for, so taking it
# away reverts all of them. It says which, from the stamp, rather than leaving
# somebody to find out at the next boot.
#
# Called from patch/cdclk-ptl/uninstall.sh and patch/edp-dsc/uninstall.sh, which
# are two doors into the same room.
xe_uninstall() {
    local fix="${1:-}" kver="${KVER:-$(uname -r)}" moddir carried=""
    moddir="/usr/lib/modules/${kver}"
    [[ -d "$moddir" ]] || moddir="/lib/modules/${kver}"

    if [[ -r /var/lib/honor/xe-module.stamp ]]; then
        carried="$(sed -n 's/^patches=//p' /var/lib/honor/xe-module.stamp)"
    fi

    if [[ ! -f "${moddir}/updates/xe.ko.zst" && ! -f "${moddir}/updates/xe.ko" ]]; then
        echo "    no locally built xe.ko for ${kver}"
        rm -f /var/lib/honor/xe-module.stamp 2>/dev/null || true
        rmdir --ignore-fail-on-non-empty /var/lib/honor 2>/dev/null || true
        return 0
    fi

    if [[ -n "$carried" && -n "$fix" && "$carried" != "$fix" ]]; then
        printf '    the overlay carries: %s\n' "$carried"
        printf '    all of it goes, not just %s. To keep the rest, re-run its\n' "$fix"
        printf '    installer afterwards with XE_SKIP=%s.\n' "$fix"
    elif [[ -n "$carried" ]]; then
        printf '    it carried: %s\n' "$carried"
    fi

    rm -fv "${moddir}/updates/xe.ko.zst" "${moddir}/updates/xe.ko" 2>/dev/null
    rmdir --ignore-fail-on-non-empty "${moddir}/updates" 2>/dev/null || true
    depmod -a "$kver" 2>/dev/null || true
    rm -f /var/lib/honor/xe-module.stamp 2>/dev/null || true
    rmdir --ignore-fail-on-non-empty /var/lib/honor 2>/dev/null || true
    echo "    back to the packaged module: $(modinfo -k "$kver" xe 2>/dev/null | grep -E '^filename:')"
}
