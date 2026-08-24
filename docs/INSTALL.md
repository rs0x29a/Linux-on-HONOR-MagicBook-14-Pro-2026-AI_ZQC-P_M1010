# Installing, in detail

The short version is in the [README](../README.md). This is what each step
does, how to check it worked, and what to do on a system that is not the one
this was built on.

## What `apply_patch.sh` does

Before step 1 it identifies the machine, then checks the kernel once: five of
the steps build a module against the running kernel, and on a rolling
distribution the usual failure is a kernel installed but not yet booted, whose
headers have already been replaced. Rather than failing five times with five
different messages, it says so up front and names the steps that will be
affected.

| Step | Action |
|---|---|
| 1 | Backs up everything about to be touched |
| 2 | Installs `patch/acpi-override/SSDT27_TPD0.aml` into `/usr/lib/firmware/acpi/` and the `acpi_override` mkinitcpio hook |
| 3 | Adds `acpi_override` to `HOOKS=` in `/etc/mkinitcpio.conf`, right after `autodetect` |
| 4 | Appends `i8042.dumbkbd=1` to the kernel command line, wherever this distribution keeps it: `/etc/default/limine`, `/etc/default/grub` or `/etc/kernel/cmdline`. On Linux 7.2 and 7.1.10 the upstream `atkbd` quirk makes it unnecessary, and the step says so |
| 5 | Runs `patch/psr-band/install.sh` — puts `xe.enable_psr=1` on the cmdline so Panel Self Refresh stops at PSR1, and applies it to the running session too |
| 6 | Runs `patch/oled-backlight/install.sh` — patched VBT, `FILES=` entry and `xe.vbt_firmware=` on the cmdline |
| 7 | Rebuilds `xe.ko` into the `updates/` overlay through `lib/xe-build.sh`, carrying every patch that lives inside that module: the Panther Lake cdclk fix (`WITH_CDCLK=1`, `patch/cdclk-ptl/install.sh`) and the eDP DSC preference (`WITH_DSC=1`, `patch/edp-dsc/install.sh`). Skipped entirely when neither is asked for |
| 8 | Regenerates the initramfs and the bootloader config, once, after all the config edits |
| 9 | Runs `patch/headset-mic/install.sh` — rebuilds `snd-hda-codec-alc269.ko` with the ALC256 quirk for PCI SSID `1ee7:209d` |
| 10 | Runs `patch/sof-audio/install.sh` — builds `snd-sof.ko` with the IPC4 backport into the `updates/` overlay |
| 11 | Runs `patch/micmute/install.sh` — builds and installs the HID-BPF descriptor fixup through `udev-hid-bpf` |
| 12 | Runs `patch/touchpad-edge/install.sh` — HID-BPF program for the left-edge brightness gesture |
| 13 | Runs `patch/fan/install.sh` — `honor-ec-sensors`, EC fan tachometers, through DKMS |
| 13b | If `FAN_CURVE=0xAA` or `0xAB` is set, enables the guarded early-engagement curve with a thermal failsafe |
| 14 | Runs `patch/fingerprint/install.sh` — rebuilds `libfprint` with the Goodix `27c6:6f94` id |
| 15 | Runs `patch/battery/install.sh` — arms a charge preset the EC actually enforces, and keeps it armed across boots |
| 16 | Runs `patch/hotkeys/install.sh` — rebuilds `huawei-wmi` with the HONOR hotkey codes, plus a hwdb entry for the atkbd noise |
| 17 | Runs `patch/hotkey-actions/install.sh` — the performance key cycles power profiles, the camera key switches the webcam off |
| 18 | Runs `patch/keyboard-backlight/install.sh` — an experimental EC-backed LED driver for the verified ZQC-P profile |
| 19 | Runs `patch/auto-rebuild/install.sh` — package-manager hooks that keep steps 9, 10 and 14 applied across package updates |

Steps 9 and 10 are skipped with a warning if kernel lockdown or
`module.sig_enforce=1` would block an unsigned module. Step 2 warns about
lockdown too, for a different reason: it silently refuses ACPI table overrides,
and a machine that boots without a touchpad and without an obvious error is
worse than one that refuses loudly. Step 18 is skipped where no kernel-update
hook mechanism is known. Step 7 runs before the initramfs rebuild because the
early-KMS copy of `xe.ko` is the one that lights the panel.


## Verifying after reboot

```bash
# ACPI override loaded, no AE_AML_INTERNAL
sudo dmesg | grep -iE 'I2C_DEVT|table upgrade'

# both touch controllers enumerated
ls /sys/bus/acpi/devices/ | grep -iE 'TOPS|FTSC'
sudo dmesg | grep -iE 'i2c.hid|hid-multitouch'

# keyboard quirk on the cmdline
grep -o 'i8042.dumbkbd=1' /proc/cmdline

# no phantom KEY_MICMUTE device — must print nothing
grep -l UNKNOWN /sys/class/input/input*/name | xargs -r grep -H 2808

# the HID-BPF fixup is loaded
sudo udev-hid-bpf list-loaded

# ALC256 quirk picked up
sudo dmesg | grep 'picked fixup.*1ee7:209d'

# fan RPM readout
sensors | grep -A3 honor_ec
```


## Surviving package updates

Both kernel-module fixes install into `/usr/lib/modules/$KVER/updates/`, which
`depmod` searches before `kernel/`, so a package update never overwrites them.
What it does do is produce a *new* kernel that has no `updates/` entry yet. The
hooks from step 18 fill that in automatically, and re-apply the
fingerprint patch after a libfprint update.

Everything else needs nothing: the ACPI override is firmware data, the HID-BPF
object is CO-RE, and the fan module uses DKMS.

Check what happened after an update:

```bash
sudo tail -40 /var/log/honor-autorebuild.log
```

Details and the manual fallback are in
[`patch/auto-rebuild/README.md`](../patch/auto-rebuild/README.md).

---


## Other distributions and bootloaders

Two things have to land somewhere, and `lib/distro.sh` works out where.

### The kernel command line

Handled automatically for `/etc/default/limine`, `/etc/default/grub` (both
`GRUB_CMDLINE_LINUX_DEFAULT` and `GRUB_CMDLINE_LINUX`, either quote style,
and an empty value) and `/etc/kernel/cmdline`. Adding twice is a no-op and
`uninstall_patch.sh` removes it from whichever file it went into.

If you use something else, add ` i8042.dumbkbd=1` yourself:

- **systemd-boot**: the `options` line in `/boot/loader/entries/*.conf`
- **rEFInd**: the matching `options` line in `refind.conf`

### The ACPI table override

The kernel reads table overrides only from an **early, uncompressed CPIO**
containing `kernel/firmware/acpi/<name>.aml`
(`Documentation/admin-guide/acpi/initrd_table_override.rst`). There are two
ways to put one there and the installer picks:

| | How | Where |
|---|---|---|
| **mkinitcpio** | an install hook calls `add_file_early`, and `acpi_override` goes into `HOOKS=` | Arch, CachyOS, Manjaro, EndeavourOS |
| **early CPIO** | the CPIO is built by the installer and handed to GRUB as an extra initrd through `GRUB_EARLY_INITRD_LINUX_CUSTOM` | Debian, Ubuntu and derivatives |

Both stage from `/usr/lib/firmware/acpi/`, so the table is in the same place
either way. The Debian route writes `/boot/acpi_override.cpio` and merges its
name into any existing `GRUB_EARLY_INITRD_LINUX_CUSTOM` value rather than
overwriting it; the archive is byte-reproducible, so re-running the installer
does not churn it.

**On dracut systems** (Fedora, Bazzite, and Debian if you replaced
`initramfs-tools`) neither applies and the installer says so rather than
pretending. Build the CPIO by hand and prepend it:

```sh
mkdir -p /tmp/o/kernel/firmware/acpi
cp /usr/lib/firmware/acpi/*.aml /tmp/o/kernel/firmware/acpi/
( cd /tmp/o && find kernel | cpio -H newc --create ) > /boot/acpi_override.cpio
cat /boot/acpi_override.cpio /boot/initramfs-$(uname -r).img > /boot/initramfs-new.img
```

Check it worked after rebooting, whichever route you took:

```sh
journalctl -k -b | grep -iE 'table upgrade|I2C_DEVT|locked down'
```

You want to see the table being upgraded and **not** `kernel is locked down,
ignoring table override`. Under kernel lockdown the override is silently
discarded and the touchpad stays missing.

---
