# Keeping the fixes applied across package updates

| | |
|---|---|
| Problem | some fixes live inside files a package update replaces |
| Fix | package-manager hooks that rebuild them automatically |
| Scope | Arch (pacman hooks), Debian/Ubuntu (`/etc/kernel/postinst.d`) and Fedora/Bazzite (systemd path unit) |

```sh
sudo bash patch/auto-rebuild/install.sh
```

## What is fragile and why

| Fix | Lives in | Replaced by |
|---|---|---|
| [`headset-mic/`](../headset-mic/) | `snd-hda-codec-alc269.ko` | any kernel package update |
| [`sof-audio/`](../sof-audio/) | `snd-sof.ko` | any kernel package update |
| [`hotkeys/`](../hotkeys/) | `huawei-wmi.ko` | any kernel package update |
| [`cdclk-ptl/`](../cdclk-ptl/) and [`edp-dsc/`](../edp-dsc/) | `xe.ko` | any kernel package update, and only if one was installed |
| [`fingerprint/`](../fingerprint/) | `libfprint` | any libfprint update |

`xe.ko` is one module with more than one patch in it, so it is rebuilt as a
set. Which patches were in it is read back from
`/var/lib/honor/xe-module.stamp` and reproduced exactly, through `XE_ONLY`,
rather than rebuilding whatever the profile would ask for today: a machine that
deliberately took one of the two should not silently acquire the other at the
next kernel update. No stamp means nothing was installed and nothing is built.

Fixes that are **not** here need nothing. `fan/` goes through DKMS, which does
its own rebuild when a kernel is installed. `micmute/` and `touchpad-edge/` are
HID-BPF programs loaded by `udev-hid-bpf` from a path that is not per kernel.
`acpi-override/`, `oled-backlight/`, `psr-band/`, `battery/` and
`hotkey-actions/` install firmware, kernel parameters, udev rules or units, and
a kernel update does not touch any of those. `tools/selftest.sh` checks that
every fix which does install into a kernel's `updates/` overlay is listed
above, because the failure mode is silent: the new kernel simply boots with the
stock module and everything looks normal until you notice it does not work.

The other fixes need nothing: the ACPI override is a firmware file, the
mic-mute fixup is a CO-RE BPF object, and the fan module uses DKMS.

**On Debian and Ubuntu only the kernel-module rebuild is hooked.** A libfprint
upgrade is not a kernel event and there is no equivalent hook directory for it,
so re-run [`patch/fingerprint/install.sh`](../fingerprint/install.sh) by hand
after one. The installer says so when it runs there.

**On Fedora and Bazzite**, the installer enables
`honor-autorebuild.path`, which watches `/usr/lib/modules` after a kernel
deployment and schedules the rebuild outside the deployment. Immutable images,
Secure Boot and signed-module policy can still reject an overlay; the log names
the exact installer to re-run and `tools/doctor.sh --json` reports the resulting
state.

Both kernel-module fixes install into `/usr/lib/modules/$KVER/updates/`, which
`depmod` searches before `kernel/`, so the packaged modules are never
overwritten. A new kernel simply has no `updates/` entry yet, which is what the
hook fills in.

## What gets installed

```
/etc/pacman.d/hooks/95-honor-kernel-modules.hook
/etc/pacman.d/hooks/96-honor-libfprint.hook
/usr/local/lib/honor/rebuild.sh     hook dispatcher
/usr/local/lib/honor/deferred.sh    runs outside the transaction
/etc/honor-autorebuild.conf         REPO= and BUILD_USER=
```

| Hook | Trigger | Action |
|---|---|---|
| `95-…-kernel-modules` | any `usr/lib/modules/*/vmlinuz` installed or upgraded | rebuilds `headset-mic`, `sof-audio`, `hotkeys` and the `xe.ko` set for each kernel named in the transaction, in `PostTransaction` |
| `96-…-libfprint` | `libfprint` installed or upgraded | re-applies the fingerprint patch |

Neither rebuild runs inside the transaction. Both are handed to a transient
systemd unit that waits for `/var/lib/pacman/db.lck` to clear, then runs the
installers. Two reasons: the fingerprint fix calls `pacman -U` and would
deadlock on the database, and every installer fetches its sources from the
matching kernel tag, which was observed to fail with an immediate connection
error when run from inside a transaction. A long build should not hold the
transaction open either. `makepkg` refuses to run as root, so `BUILD_USER`
records the account that installed the hooks.

The deferred work lives in its own script, `deferred.sh`, rather than being
passed to `systemd-run` as a command line: systemd expands `$VAR` in `ExecStart`
itself and would consume the script's own loop variables.

Every step logs to `/var/log/honor-autorebuild.log`, and the dispatcher
always exits 0, so a failure reports itself without breaking the transaction.

## Behaviour worth knowing

- Kernels without headers are skipped with a message naming the command to run
  after installing them.
- All installed kernels are rebuilt for, not only the running one, so a
  fallback LTS kernel stays fixed too.
- An installer exit code of `3` means "this fix does not apply to that kernel",
  reported as *skipped* rather than a failure.
- The repository must stay where it was when the hooks were installed. If you
  move it, re-run `install.sh` or edit `REPO` in
  `/etc/honor-autorebuild.conf`.
- The rebuild fetches sources from `raw.githubusercontent.com`. Without
  network, it logs the failure and the fix is simply missing until you re-run
  it.

## Trying it without waiting for an update

```sh
echo | sudo /usr/local/lib/honor/rebuild.sh modules
```

Empty input means "every installed kernel that has headers".

## Uninstall

```sh
sudo rm /etc/pacman.d/hooks/9[56]-honor-zqcp-*.hook \
        /usr/local/lib/honor/rebuild.sh \
        /etc/honor-autorebuild.conf
```

`uninstall_patch.sh` does this as part of the full revert.
