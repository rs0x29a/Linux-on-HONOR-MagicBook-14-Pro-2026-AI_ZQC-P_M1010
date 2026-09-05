#!/usr/bin/env bash
# Install the package-manager hooks that re-apply the fixes a package update
# would revert: pacman hooks on Arch, /etc/kernel/postinst.d on Debian.
#
# See README.md in this directory for what is fragile and why.
#
# Reruns are safe.

set -euo pipefail

if (( EUID != 0 )); then
    echo "Must be run as root. Use: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB_DIR="/usr/local/lib/honor"
HOOK_DIR="/etc/pacman.d/hooks"
CONF="/etc/honor-autorebuild.conf"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# Tier A: the hooks only re-run the other installers, and each of those gates
# itself. Nothing model specific is written here.
source "${SCRIPT_DIR}/../../lib/gate.sh"
honor_gate auto-rebuild

# Every fix is looked up the same way, including the ones that carry no
# numbers of their own: patch/auto-rebuild/<model>/<board>/ records that this
# machine was considered and on what evidence. See lib/variant.sh.
variant_find "$SCRIPT_DIR" || die \
    "this fix has nothing for $(profile_get model) board ${PROFILE_BOARD:-?}.
    Covered: $(variant_known "$SCRIPT_DIR")"
log "machine: $(variant_note)"

legacy_move /usr/local/lib/honor-zqcp /usr/local/lib/honor
legacy_move /etc/honor-zqcp-autorebuild.conf /etc/honor-autorebuild.conf
legacy_drop /etc/pacman.d/hooks/95-honor-zqcp-kernel-modules.hook \
            /etc/pacman.d/hooks/96-honor-zqcp-libfprint.hook

# Arch has pacman hooks, Debian has /etc/kernel/postinst.d. They are the same
# idea: run something after the package manager has put a new kernel in place.
HOOK_STYLE="$(distro_family)"
case "$HOOK_STYLE" in
    arch)   command -v pacman >/dev/null || die "pacman not found" ;;
    debian) [[ -d /etc/kernel ]] || die "no /etc/kernel; cannot install a kernel hook" ;;
    *)      die "No kernel-update hook mechanism is known for this distribution.
    Re-run the installers in patch/headset-mic/ and patch/sof-audio/ after each
    kernel update by hand." ;;
esac

[[ -d "${REPO}/patch" ]] || die "cannot locate the repository from ${SCRIPT_DIR}"

# The fingerprint rebuild has to run makepkg, which refuses to run as root.
BUILD_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [[ -z "$BUILD_USER" || "$BUILD_USER" == "root" ]]; then
    warn "Cannot determine a non-root user for makepkg. The libfprint hook will"
    warn "be installed but the fingerprint rebuild will fail until you set"
    warn "BUILD_USER in ${CONF} by hand."
    BUILD_USER="root"
fi

log "repository = ${REPO}"
log "build user = ${BUILD_USER}"

install -d -m 0755 "$LIB_DIR"
install -m 0755 "${SCRIPT_DIR}/rebuild.sh" "${SCRIPT_DIR}/deferred.sh" "${LIB_DIR}/"

if [[ "$HOOK_STYLE" == arch ]]; then
    install -d -m 0755 "$HOOK_DIR"
    install -m 0644 "${SCRIPT_DIR}/95-honor-kernel-modules.hook" "$HOOK_DIR/"
    install -m 0644 "${SCRIPT_DIR}/96-honor-libfprint.hook"      "$HOOK_DIR/"
else
    # Debian passes the new kernel version as $1 and runs these after the
    # kernel package is unpacked, which is exactly when the modules overlay
    # needs rebuilding. There is no libfprint equivalent: a libfprint upgrade
    # is not a kernel event, so that one has to be re-run by hand there.
    HOOK_DIR=/etc/kernel/postinst.d
    install -d -m 0755 "$HOOK_DIR"
    cat > "${HOOK_DIR}/95-honor-kernel-modules" <<HOOKEOF
#!/bin/sh
# Installed by patch/auto-rebuild/install.sh. Debian passes the new kernel
# version in \$1. rebuild.sh reads the changed paths from stdin, the same way
# the pacman hook feeds them, so hand it one path in that shape rather than an
# argument it would ignore.
echo "usr/lib/modules/\$1/vmlinuz" | exec ${LIB_DIR}/rebuild.sh modules
HOOKEOF
    chmod 0755 "${HOOK_DIR}/95-honor-kernel-modules"
    warn "on this distribution only the kernel-module rebuild is hooked."
    warn "Re-run patch/fingerprint/install.sh by hand after a libfprint update."
fi

cat > "$CONF" <<EOF
# Written by patch/auto-rebuild/install.sh. Read by
# ${LIB_DIR}/rebuild.sh, which the package-manager hooks in
# ${HOOK_DIR} invoke.
REPO=${REPO}
BUILD_USER=${BUILD_USER}
EOF
chmod 0644 "$CONF"

if [[ "$HOOK_STYLE" == arch ]]; then
    INSTALLED_HOOKS="  ${HOOK_DIR}/95-honor-kernel-modules.hook
  ${HOOK_DIR}/96-honor-libfprint.hook"
    WHAT_IS_HOOKED="  From now on a kernel update rebuilds the module overlays listed for this
  board automatically, and a libfprint update re-applies patch/fingerprint/
  shortly after the transaction."
    UNINSTALL_HOOKS="${HOOK_DIR}/9[56]-honor-*.hook"
else
    INSTALLED_HOOKS="  ${HOOK_DIR}/95-honor-kernel-modules"
    WHAT_IS_HOOKED="  From now on a kernel update rebuilds patch/headset-mic/ and
  patch/sof-audio/ for the new kernel automatically.

  There is NO libfprint hook on this distribution: a libfprint upgrade is
  not a kernel event, so re-run patch/fingerprint/install.sh by hand after
  one."
    UNINSTALL_HOOKS="${HOOK_DIR}/95-honor-kernel-modules"
fi

cat <<EOF

════════════════════════════════════════════════════════════════════
  Auto-rebuild hooks installed.

${INSTALLED_HOOKS}
  ${LIB_DIR}/rebuild.sh
  ${LIB_DIR}/deferred.sh
  ${CONF}

${WHAT_IS_HOOKED}

  Log: /var/log/honor-autorebuild.log

  The repository must stay at ${REPO}. If you move it, re-run this
  script, or edit REPO in ${CONF}.

  Dry run without waiting for an update:
      echo | sudo ${LIB_DIR}/rebuild.sh modules

  Uninstall:
      sudo rm ${UNINSTALL_HOOKS} \\
              ${LIB_DIR}/rebuild.sh ${LIB_DIR}/deferred.sh ${CONF}
════════════════════════════════════════════════════════════════════
EOF
