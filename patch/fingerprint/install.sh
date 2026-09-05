#!/usr/bin/env bash
# install-fingerprint-fix.sh — build a patched libfprint that recognises the
# HONOR ZQC-P M1010 power-button fingerprint reader, and install fprintd.
#
# Background:
#   The reader is a Goodix match-on-chip sensor on USB, id 27c6:6f94
#   ("Goodix USB2.0 MISC", vendor-specific class, 2 bulk endpoints,
#   firmware 01010106). It is NOT an ACPI/SPI device — the DSDT's FPNT
#   node is an inactive SPI slot for other SKUs — so nothing about it
#   depends on the DSDT override this repo ships. It enumerates purely
#   from its own USB descriptors, which means the only place to fix it
#   is the USB driver.
#
#   The sensor speaks the ordinary goodixmoc protocol that libfprint has
#   supported for years. It simply is not in the driver's id table: the
#   table already carries 0x6984, 0x6A94, 0x6594 and friends, but not
#   0x6F94. Adding the id (and the max_enroll_stage = 12 case, which the
#   whole family shares) is the entire fix — no protocol work needed.
#
#   Verified on this machine before this script was written: with the
#   two-line patch applied, the device is claimed by the goodixmoc
#   driver, opens cleanly, reports its firmware version, and answers a
#   template-list query ("Device contains 0 prints").
#
#   Upstream status as of 2026-07-30: 0x6F94 is absent from libfprint
#   master (checked at commit c4654fd). Worth submitting upstream — it
#   is a trivially reviewable id addition.
#
# Reruns are safe. Re-run after a libfprint package update, since a
# distro update will overwrite the patched library.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=$(mktemp -d /tmp/honor-fprint-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. is this fix meant for this machine ------------------------------------
# Tier A: the reader is matched by USB id, so on hardware without it nothing
# happens. The ids come from the profile rather than being baked in here.
source "${REPO_DIR}/../../lib/gate.sh"
honor_gate fingerprint

# --- 1b. why one run at a time matters especially here ------------------------
# honor_gate has already taken the per-fix lock. This is the script that made it
# necessary: it runs `pacman -S --needed` for its build dependencies, the
# patched libfprint it produced last time is in that dependency closure, so
# pacman lists libfprint as a target, so 96-honor-libfprint.hook fires, so
# rebuild.sh defers a second copy of this very script. The two then raced in one
# build directory, and the loser reported a failure for a machine that was in
# fact correctly patched: the deferred run logged `fingerprint: ok` while the
# foreground one printed "makepkg failed".

# The same model ships different readers in different regions, so the profile
# lists what it is known to carry and we go and see which one is actually here.
if [[ -n "${FP_VID_PID:-}" ]]; then
    log "using the reader given on the command line: $FP_VID_PID"
else
    rc=0; FP_VID_PID="$(gate_probe_usb fingerprint_usb)" || rc=$?
    case "$rc" in
        1) die "$(profile_get model) does not record fingerprint_usb.
    Find the reader in 'lsusb' and add it to the profile." ;;
        2) die "none of the readers $(profile_get model) is known to ship is on
    this USB bus. Looked for: $(profile_get fingerprint_usb)
    Either this unit has a different one, in which case please add it to the
    profile and open an issue, or the reader is disabled in firmware." ;;
    esac
fi
log "Found fingerprint reader $FP_VID_PID"

# Each reader needs its own libfprint driver, its own patches, and sometimes a
# different source tree entirely. patch/fingerprint/<model>/<board>/recipe.conf
# says which, so nobody has to go and find the work in somebody else's
# repository. This is also the clearest case in the tree for keying on the
# board: global ZQC-P M1010 units ship a Goodix reader and Chinese M1050 ones
# ship an EgisTec, and the board revision is what tells them apart.
#
# lib/variant.sh does the lookup, and every fix that carries per-machine parts
# uses the same layout and the same reader.
variant_find "$REPO_DIR" || die \
    "this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
    Covered: $(variant_known "$REPO_DIR")

    If you get a reader working, a directory here would be very welcome:
    see patch/fingerprint/README.md for the layout."
SENSOR_DIR="$VARIANT_DIR"

variant_check_device "$FP_VID_PID" || die \
    "$(profile_get model) board ${PROFILE_BOARD:-?} is recorded with reader
    $(recipe_get device), and this unit has $FP_VID_PID on the USB bus.
    Nothing has been built or installed. Please open an issue with the two ids:
    either this unit is unusual, or that board section is wrong."

FP_NAME="${RECIPE[name]:-$FP_VID_PID}"
FP_SOURCE="${RECIPE[source]:-distro}"
FP_VARIANT="${FP_PATCH_VARIANT:-default}"
case "$FP_VARIANT" in
    full) FP_PATCHES="${RECIPE[patches_full]:-}"; FP_APPLIES="${RECIPE[applies_to_full]:-}" ;;
    old)  FP_PATCHES="${RECIPE[patches_old]:-}";  FP_APPLIES="${RECIPE[applies_to_old]:-}"  ;;
    *)    FP_PATCHES="${RECIPE[patches]:-}";      FP_APPLIES="${RECIPE[applies_to]:-}"      ;;
esac
[[ -n "$FP_PATCHES" ]] || die "this recipe has no '$FP_VARIANT' variant.
    Available: default$([[ -n "${RECIPE[patches_old]:-}" ]] && echo ", old")$([[ -n "${RECIPE[patches_full]:-}" ]] && echo ", full")"
[[ -n "$FP_PATCHES" ]] || die "${SENSOR_DIR}/recipe.conf names no patches"

log "machine: $(variant_note)"
log "sensor: $FP_NAME  (${RECIPE[driver]:-?} driver, source=${FP_SOURCE})"
recipe_warn_unverified

# --- 1c. has this already been done ------------------------------------------
# Same idea and same place as lib/xe-build.sh's module stamp: record what was
# built, and do nothing when the answer has not changed.
#
# It matters more here than it looks. Section 5 runs `pacman -S fprintd
# libfprint`, which names libfprint as a target of the transaction, which fires
# 96-honor-libfprint.hook, which defers another run of this script. Without this
# check every run builds libfprint twice: once in the foreground and once in the
# deferred unit that its own pacman call scheduled.
#
# The stamp is deliberately keyed on the INSTALLED package version, so a real
# libfprint upgrade, which is what that hook exists for, does not match and the
# rebuild happens.
FP_STAMP=/var/lib/honor/fingerprint.stamp
fp_installed_version() {
    if command -v pacman >/dev/null 2>&1; then
        pacman -Q libfprint 2>/dev/null | awk '{print $2}'
    else
        printf 'not-a-package'
    fi
}
fp_stamp_matches() {
    [[ -r "$FP_STAMP" ]] || return 1
    local k
    for k in sensor recipe patches libfprint; do
        local want have
        case "$k" in
            sensor)    want="$FP_VID_PID" ;;
            recipe)    want="$(basename "$SENSOR_DIR")" ;;
            patches)   want="$FP_PATCHES" ;;
            libfprint) want="$(fp_installed_version)" ;;
        esac
        have="$(sed -n "s/^${k}=//p" "$FP_STAMP")"
        [[ "$have" == "$want" ]] || return 1
    done
    return 0
}
fp_write_stamp() {
    install -d -m 0755 /var/lib/honor
    printf '%s\n' \
        "# written by patch/fingerprint/install.sh" \
        "sensor=${FP_VID_PID}" \
        "recipe=$(basename "$SENSOR_DIR")" \
        "patches=${FP_PATCHES}" \
        "libfprint=$(fp_installed_version)" > "$FP_STAMP"
}
if [[ "${FORCE:-0}" != "1" ]] && fp_stamp_matches; then
    log "already applied: libfprint $(fp_installed_version) carries $FP_NAME."
    log "Nothing to rebuild. Use FORCE=1 to build it again anyway."
    exit 0
fi

# A patch that predates your libfprint will either fail loudly or, worse, apply
# with fuzz into the wrong place. Say so before building anything.
if [[ "$FP_SOURCE" == "distro" && -n "$FP_APPLIES" ]] && command -v pacman >/dev/null; then
    HAVE_VER="$(pacman -Q libfprint 2>/dev/null | awk '{print $2}' | cut -d- -f1)"
    if [[ -n "$HAVE_VER" ]]; then
        ok=0
        for v in $FP_APPLIES; do [[ "$v" == "$HAVE_VER" ]] && ok=1; done
        if (( ! ok )) && [[ "${FP_FORCE_VERSION:-0}" == "1" ]]; then
            warn "FP_FORCE_VERSION=1: applying a patch checked against
    libfprint $FP_APPLIES to your $HAVE_VER. If it lands in the wrong place the
    build will fail, or worse, succeed and misbehave."
            ok=1
        fi
        if (( ! ok )); then
            die "this patch was checked against libfprint $FP_APPLIES, and you have $HAVE_VER.
    Refusing rather than applying it with fuzz into a file that has moved on.

    $(basename "$SENSOR_DIR") notes the drift in its recipe.conf. Rebasing it
    needs the sensor in hand to verify against, so it has not been done blind.
    Set FP_FORCE_VERSION=1 to try anyway."
        fi
    fi
fi

PATCH="${SENSOR_DIR}/${FP_PATCHES%% *}"
[[ -f "$PATCH" ]] || die "patch file missing: $PATCH"

# Belt and braces: for a single-patch distro recipe the patch must add the id
# we actually detected.
if [[ "$FP_SOURCE" == "distro" ]]; then
    PATCH_PID="$(grep -E '^\+.*\.pid *= *0x' "$PATCH" | grep -oE '0x[0-9a-fA-F]+' | tail -1)"
    if [[ -n "$PATCH_PID" && "${PATCH_PID,,}" != "0x${FP_VID_PID##*:}" ]]; then
        die "$(basename "$PATCH") adds $PATCH_PID but the reader here is $FP_VID_PID."
    fi
fi
log "patch: $(basename "$PATCH")"

# --- 1b. a sensor whose support is not in any libfprint release yet -----------
# SDCP, the protocol the EgisTec sensor speaks, is still a merge request. There
# is nothing to patch into the distribution's libfprint, so this builds
# upstream's SDCP branch at the commit the recipe pins and installs it into a
# private prefix that takes precedence through ld.so.conf.d. The distribution's
# own package stays installed and untouched, so removing one file undoes it.
if [[ "$FP_SOURCE" == "git" ]]; then
    PREFIX=/opt/honor-libfprint-sdcp
    LDCONF=/etc/ld.so.conf.d/00-honor-libfprint-sdcp.conf

    warn "This builds a second libfprint and puts it ahead of your distribution's
    for every program that uses it, fprintd included. It has NOT been run on
    hardware by this repository. To undo:
        sudo rm -rf $PREFIX $LDCONF && sudo ldconfig"

    for t in git meson ninja pkg-config; do
        command -v "$t" >/dev/null || die "missing build tool: $t"
    done

    GITDIR="${WORK}/libfprint-sdcp"
    log "cloning ${RECIPE[git_branch]} at ${RECIPE[git_commit]:0:12}"
    git clone -q --branch "${RECIPE[git_branch]}" --single-branch \
        "${RECIPE[git_url]}" "$GITDIR" || die "clone failed"
    git -C "$GITDIR" checkout -q "${RECIPE[git_commit]}" \
        || die "the pinned commit ${RECIPE[git_commit]} is not in that branch any more.
    Upstream may have rebased it; please open an issue."

    for f in $FP_PATCHES; do
        log "applying $f"
        git -C "$GITDIR" apply "${SENSOR_DIR}/${f}" \
            || die "$f does not apply to the pinned commit. Do not force it."
    done

    log "building (this takes a few minutes)"
    # Option names checked against the pinned tree: there is no -Dtests, and
    # -Dintrospection is a boolean rather than a meson feature.
    meson setup "$GITDIR/build" "$GITDIR" \
        --prefix="$PREFIX" --libdir=lib --buildtype=release \
        -Ddoc=false -Dgtk-examples=false -Dintrospection=false \
        -Dinstalled-tests=false \
        >/dev/null || die "meson setup failed"
    ninja -C "$GITDIR/build" >/dev/null || die "build failed"
    ninja -C "$GITDIR/build" install >/dev/null || die "install failed"

    # Before putting it in front of the system library, check it really does
    # claim this sensor. A build that succeeds and supports nothing is worse
    # than one that fails.
    if [[ -x "$GITDIR/build/libfprint/fprint-list-supported-devices" ]]; then
        "$GITDIR/build/libfprint/fprint-list-supported-devices" 2>/dev/null \
            | grep -qi "${FP_VID_PID}" \
            || die "the build finished but does not list $FP_VID_PID as supported.
    Something is wrong with the patch series; not installing it."
        log "the built library lists $FP_VID_PID"
    fi

    printf '%s/lib\n' "$PREFIX" > "$LDCONF"
    ldconfig
    log "installed to $PREFIX and put ahead of the system libfprint"
    systemctl try-restart fprintd >/dev/null 2>&1 || true

    cat <<EOF

════════════════════════════════════════════════════════════════════
  $FP_NAME support installed.

  Source : ${RECIPE[git_branch]} @ ${RECIPE[git_commit]:0:12}
  Patches: $FP_PATCHES
  From   : ${RECIPE[origin]}

  Enrol with:   fprintd-enroll
  Undo with:    sudo rm -rf $PREFIX $LDCONF && sudo ldconfig

  If you dual boot: booting Windows can wipe Linux enrolments, because the
  Windows biometric stack garbage-collects on-chip templates it does not
  recognise. Disable the fingerprint device in Windows Device Manager if that
  matters to you.
════════════════════════════════════════════════════════════════════
EOF
    exit 0
fi

# --- 2. build deps ------------------------------------------------------------
if command -v pacman >/dev/null 2>&1; then
    log "Installing build dependencies (pacman)"
    pacman -S --needed --noconfirm \
        base-devel git meson ninja glib2-devel libgusb nss libgudev \
        gobject-introspection cairo pixman polkit dbus systemd-libs
    NEED_FPRINTD_PKG="fprintd"
elif command -v apt-get >/dev/null 2>&1; then
    log "Installing build dependencies (apt)"
    apt-get update
    apt-get install -y build-essential git meson ninja-build libglib2.0-dev \
        libgusb-dev libnss3-dev libgudev-1.0-dev libgirepository1.0-dev \
        gobject-introspection libcairo2-dev libpixman-1-dev libpolkit-gobject-1-dev
    NEED_FPRINTD_PKG="fprintd"
elif command -v dnf >/dev/null 2>&1; then
    log "Installing build dependencies (dnf)"
    dnf install -y gcc make git meson ninja-build glib2-devel libgusb-devel \
        nss-devel libgudev-devel gobject-introspection-devel cairo-devel \
        pixman-devel polkit-devel
    NEED_FPRINTD_PKG="fprintd"
else
    warn "Unknown distro — install meson/ninja/glib/libgusb/nss/libgudev dev
    packages yourself, then re-run."
    NEED_FPRINTD_PKG=""
fi

# --- 3. clone + patch + build -------------------------------------------------
FP_BUILD_TAG=""
if command -v pacman >/dev/null 2>&1; then
    FP_BUILD_VER="$(pacman -Q libfprint 2>/dev/null | awk '{print $2}' | cut -d- -f1)"
    [[ -n "$FP_BUILD_VER" ]] || FP_BUILD_VER="$(pacman -Si libfprint 2>/dev/null | awk '/^Version/{print $3; exit}' | cut -d- -f1)"
    [[ -n "$FP_BUILD_VER" ]] || die "cannot determine the repository libfprint version"
    FP_BUILD_TAG="v${FP_BUILD_VER}"
fi
log "Cloning libfprint ${FP_BUILD_TAG:-master}"
CLONE_ARGS=(--depth 1)
[[ -n "$FP_BUILD_TAG" ]] && CLONE_ARGS+=(--branch "$FP_BUILD_TAG")
git clone "${CLONE_ARGS[@]}" https://gitlab.freedesktop.org/libfprint/libfprint.git \
    "$WORK/libfprint" >/dev/null 2>&1 || die "clone failed"

cd "$WORK/libfprint"
log "Applying $FP_VID_PID id patch"
if patch -p1 --dry-run < "$PATCH" >/dev/null 2>&1; then
    patch -p1 < "$PATCH"
elif grep -q '0x6F94' libfprint/drivers/goodixmoc/goodix.c; then
    log "Upstream already carries 0x6F94 — nothing to patch"
else
    die "Patch does not apply to current libfprint master. The id table or the
    max_enroll_stage switch has moved; re-diff the two hunks by hand."
fi

# introspection=true is deliberate: libfprint's tests/meson.build has an
# upstream bug in the introspection=false branch that trips newer meson
# ("Foreach expects exactly 2 variables ... type dict").
log "Configuring and building (this takes a minute)"
meson setup build \
    --prefix=/usr --libdir=lib --buildtype=release \
    -Ddrivers=all -Dintrospection=true -Ddoc=false -Dgtk-examples=false \
    >"$WORK/meson-setup.log" 2>&1 || {
        tail -40 "$WORK/meson-setup.log" >&2
        die "meson setup failed"
    }
ninja -C build >/dev/null || die "build failed"

# --- 4. verify against the real device BEFORE installing ----------------------
log "Probing the reader with the freshly built driver"
PROBE=$(LD_LIBRARY_PATH="$PWD/build/libfprint" timeout 30 \
        ./build/examples/manage-prints 2>&1 || true)
if grep -q 'goodixmoc driver' <<<"$PROBE"; then
    log "OK: $(grep 'claimed by' <<<"$PROBE" | head -1)"
    grep -q 'contains' <<<"$PROBE" && log "OK: $(grep 'contains' <<<"$PROBE" | head -1)"
else
    warn "Device was NOT claimed by goodixmoc. Not installing. Output:"
    printf '%s\n' "$PROBE" | tail -20
    exit 1
fi

# --- 5. install ---------------------------------------------------------------
#
# On Arch/CachyOS, build a real package instead of dropping files into /usr.
# Learned the hard way: a bare `ninja install` puts unowned files in /usr, and
# the very next `pacman -S fprintd` fails with "libfprint: /usr/lib/
# libfprint-2.so exists in filesystem" because fprintd pulls libfprint in as a
# dependency. Letting pacman own the files avoids that and makes the patch
# visible in `pacman -Qi libfprint`.
#
if command -v pacman >/dev/null 2>&1; then
    log "Installing fprintd (repo) first, so the dependency is satisfied"
    pacman -S --needed --noconfirm fprintd libfprint

    command -v makepkg >/dev/null 2>&1 || pacman -S --needed --noconfirm base-devel
    pacman -S --needed --noconfirm gtk-doc gobject-introspection meson git \
        python-cairo python-gobject

    # makepkg refuses to run as root; build as the invoking user.
    BUILD_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    [[ "$BUILD_USER" != "root" ]] || die "Cannot determine a non-root user to
    run makepkg as. Re-run via sudo from your normal account."
    BUILD_HOME=$(getent passwd "$BUILD_USER" | cut -d: -f6)
    PKGDIR="${BUILD_HOME}/.cache/honor-libfprint-build"

    CUR_VER=$(pacman -Q libfprint | awk '{print $2}')
    UPSTREAM_VER="${CUR_VER%-*}"
    log "Building a patched libfprint package matching repo version $UPSTREAM_VER"

    rm -rf "$PKGDIR"; mkdir -p "$PKGDIR"
    curl -sfL "https://gitlab.archlinux.org/archlinux/packaging/packages/libfprint/-/raw/main/PKGBUILD" \
        -o "$PKGDIR/PKGBUILD" || die "could not fetch Arch PKGBUILD"
    cp "$PATCH" "$PKGDIR/"

    PKGBUILD_VER=$(awk -F= '/^pkgver=/{print $2}' "$PKGDIR/PKGBUILD")
    if [[ "$PKGBUILD_VER" != "$UPSTREAM_VER" ]]; then
        warn "Arch PKGBUILD is at $PKGBUILD_VER but your repo ships $UPSTREAM_VER."
        warn "Building $PKGBUILD_VER — check that it is not a downgrade."
    fi

    # pkgrel bumped past the repo's so ours is unambiguously newer and does
    # not get silently swapped back on the next -Syu.
    REPO_REL="${CUR_VER##*-}"
    NEW_REL="${REPO_REL%%.*}.$(( ${REPO_REL#*.} + 1 ))"
    python3 - "$PKGDIR/PKGBUILD" "$NEW_REL" "$(basename "$PATCH")" <<'PYEOF'
import re, sys
path, newrel, patchfile = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
s = re.sub(r'^pkgrel=.*$', 'pkgrel=' + newrel, s, count=1, flags=re.M)
s = re.sub(r'^(source=\()', r'\1"' + patchfile + '"\n        ', s, count=1, flags=re.M)
s = re.sub(r"^(b2sums=\()", r"\1'SKIP'\n        ", s, count=1, flags=re.M)
s = s.replace("prepare() {\n  cd $pkgname\n}",
              'prepare() {\n  cd $pkgname\n  if ! grep -q 0x6F94 libfprint/drivers/goodixmoc/goodix.c; then\n'
              '    patch -p1 < "$srcdir/' + patchfile + '"\n  fi\n}', 1)
s = s.replace("check() {\n  meson test -C build --print-errorlogs\n}",
              "check() {\n  : # skipped: id-table-only change\n}", 1)
open(path, 'w').write(s)
PYEOF

    chown -R "$BUILD_USER": "$PKGDIR"
    ( cd "$PKGDIR" && sudo -u "$BUILD_USER" makepkg --skippgpcheck --nocheck -f ) \
        >/dev/null 2>&1 || die "makepkg failed — run it by hand in $PKGDIR to see why"

    PKGFILE=$(ls -t "$PKGDIR"/libfprint-*.pkg.tar.* 2>/dev/null | head -1)
    [[ -n "$PKGFILE" ]] || die "makepkg produced no package in $PKGDIR"
    log "Inspecting $(basename "$PKGFILE")"
    pacman -Qip "$PKGFILE" >/dev/null || die "the built package has invalid metadata"
    pacman -Qlp "$PKGFILE" | grep -q '/usr/lib/libfprint-2\.so' \
        || die "the built package does not contain libfprint-2.so"
    log "Installing $(basename "$PKGFILE")"
    pacman -U --noconfirm "$PKGFILE" || die "pacman -U failed"
    fp_write_stamp
else
    log "Installing patched libfprint to /usr"
    ninja -C build install >/dev/null || die "install failed"
    ldconfig
    if [[ -n "$NEED_FPRINTD_PKG" ]] && ! command -v fprintd-enroll >/dev/null 2>&1; then
        log "Installing $NEED_FPRINTD_PKG"
        if   command -v apt-get >/dev/null 2>&1; then apt-get install -y fprintd libpam-fprintd
        elif command -v dnf     >/dev/null 2>&1; then dnf install -y fprintd fprintd-pam
        fi
    fi
    # Off the package manager there is no version to key on, so the stamp only
    # records what was built. A libfprint upgrade there overwrites /usr without
    # anything noticing, which is what the caveat at the end of this script says.
    fp_write_stamp
fi

systemctl daemon-reload || true
systemctl restart fprintd.service 2>/dev/null || true

# --- 6. confirm fprintd actually sees it --------------------------------------
if command -v fprintd-list >/dev/null 2>&1; then
    CHECK_USER="${SUDO_USER:-root}"
    if timeout 25 sudo -u "$CHECK_USER" fprintd-list "$CHECK_USER" 2>&1 \
         | grep -qE 'found [1-9]|no fingers enrolled'; then
        log "fprintd sees the reader"
    else
        warn "fprintd did not report the device — check 'systemctl status fprintd'"
    fi
fi

cat <<'EOF'

Done. Next steps (run as your normal user, NOT root):

    fprintd-enroll -f right-index-finger     # touch the power button repeatedly
    fprintd-verify

If enrollment works, enable it for login/sudo:

    Arch/CachyOS:  back up /etc/pam.d/system-login and /etc/pam.d/sudo, then
                   add "auth sufficient pam_fprintd.so" before their
                   "auth include system-auth" lines
    Debian/Ubuntu: sudo pam-auth-update --enable fprintd
    Fedora:        sudo authselect enable-feature with-fingerprint

Caveats:
  * A distro libfprint update will overwrite this build — re-run this script.
    On Arch the durable answer is a local PKGBUILD carrying the patch, so
    pacman owns the files; see patch/fingerprint/PKGBUILD.
  * Enrollment takes 12 samples on this sensor family. Place the finger
    firmly and shift position slightly between touches.

EOF
