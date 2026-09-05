# Linux on the HONOR MagicBook

Fixes that make HONOR MagicBook laptops usable under Linux: a patched ACPI
table for the touchpad and touchscreen, kernel-module quirks for audio and
sensors, HID-BPF programs for the touchpad gestures, a working battery charge
limit, and the Fn keys.

Built on a **MagicBook Pro 14 2026 (`ZQC-P`, board M1010)**. Further board
revisions are recognised separately and enable only the fixes supported by
evidence from that exact revision. `ZQC-P` M1020 was verified independently on
BIOS 1.10 with CachyOS and a board-specific safe subset. See [Models](#models) and
[docs/hardware/](docs/hardware/).

```sh
sudo ./apply_patch.sh
sudo reboot
```

`apply_patch.sh` identifies the machine first and refuses if it does not
recognise it. `uninstall_patch.sh` reverts everything.

---

## Status

| Area | State | Fix |
|---|---|---|
| Touchpad, touchscreen, internal keyboard | works | [`patch/acpi-override/`](patch/acpi-override/) — patched SSDT27 plus `i8042.dumbkbd=1`. **Prerequisite for a usable machine** |
| Microphone mutes itself, mic-mute LED flickers | works | [`patch/micmute/`](patch/micmute/) — HID-BPF fixup for the touchscreen's vendor collection |
| Fingerprint reader, Goodix `27c6:6f94` | works | [`patch/fingerprint/`](patch/fingerprint/) — two-line `libfprint` id patch |
| Headset microphone, 3.5 mm jack | works | [`patch/headset-mic/`](patch/headset-mic/) — one-line `SND_PCI_QUIRK` for ALC256 |
| OLED minimum brightness too low, uneven steps | works | [`patch/oled-backlight/`](patch/oled-backlight/) — patched VBT raises the firmware's backlight floor |
| Faint wide band follows the mouse pointer | works | [`patch/psr-band/`](patch/psr-band/) — PSR2 selective update can only refresh whole scanlines, so every partial update is a full-width band; limits PSR to PSR1, which has none |
| Touchpad left-edge slide (brightness gesture) | works | [`patch/touchpad-edge/`](patch/touchpad-edge/) — HID-BPF turns the vendor gesture report into brightness keys. The right edge (volume) goes through the EC and works unaided |
| Screen garbled at boot, kernel 7.1.6 and newer | works | [`patch/cdclk-ptl/`](patch/cdclk-ptl/) — rebuilds `xe.ko` with the upstream CDCLK fix Panther Lake needs. Merged to `drm-intel-next` on 2026-08-21, so expect it in Linux 7.3 and then a stable backport |
| Panel driven at 6 bits per colour, banding on gradients | works | [`patch/edp-dsc/`](patch/edp-dsc/) — the link cannot carry 8 bpc and the driver drops colour depth before it will compress; a kernel patch makes it prefer DSC on eDP, with a fallback to the old behaviour |
| Battery charge limit does nothing | works | [`patch/battery/`](patch/battery/) — the EC only enforces HONOR's own preset pairs; anything else, including what the desktop sets, is stored and ignored |
| Performance and camera keys do nothing | works | [`patch/hotkey-actions/`](patch/hotkey-actions/) — a small service acts on the keys the desktop ignores |
| Some Fn keys dead, `Unknown key pressed` in dmesg | works | [`patch/hotkeys/`](patch/hotkeys/) — adds the HONOR codes to the `huawei-wmi` keymap |
| Keyboard backlight state, KDE OSD and persistence | works on ZQC-P M1020/C170 | [`patch/hotkeys/`](patch/hotkeys/) — exposes `platform::kbd_backlight`, reports the EC's 0/50/100 states and restores the selected level after reboot and suspend/resume |
| Fan RPM readout | works | [`patch/fan/`](patch/fan/) — `honor-ec-sensors` |
| Fan speed control | not available | every OS-side path to a duty cycle was tested and the EC ignores all of them. The EC's *curve* can be selected through `\IFCI`, which is measured but deliberately not shipped, one of its thirteen tables switches the fans off. See [`patch/fan/README.md`](patch/fan/README.md) |
| SOF DSP suspend/resume panic | preventive | [`patch/sof-audio/`](patch/sof-audio/) — upstream IPC4 backport, the race never reproduced here. Merged upstream and released in Linux 7.2 |
| Fixes reverted by package updates | handled | [`patch/auto-rebuild/`](patch/auto-rebuild/) — package-manager hooks that rebuild them |
| Caps Lock LED | works from Linux 7.2 | it was collateral of `i8042.dumbkbd=1`. The upstream `atkbd` quirk for this machine is in **7.2** and queued for **7.1.10**; there, drop the parameter. See [`patch/keyboard-atkbd/`](patch/keyboard-atkbd/) |
| Fn+F7 mic-mute key itself | works out of the box | in-tree `huawei-wmi`, nothing to install |

Speakers, headphone output, the built-in DMIC array, webcam, Wi-Fi and
Bluetooth need nothing beyond the ACPI override. One report on a BIOS 1.09 unit
says the speakers die with the same table failure; on this one, on BIOS 1.10,
the codec is on HDA and unaffected. See
[the speakers disagreement](docs/hardware/zqc-p.md#the-speakers-disagreement).

---

## Models

Trust is per **board revision**, not per model. HONOR ships one product code as
several machines: `ZQC-P` is board `M1010` here, board `M1020` on the BIOS
1.10 unit documented in this branch, and board `M1050` elsewhere with a
different CPU; `FMB-P` is five revisions across three SKUs. So a profile
has one section per revision, each with its own status, and a revision nobody
has measured never inherits another one's.

Board revisions across twelve product codes are recognised. What each one is,
what is known about it, where every claim came from and what it would take to
move it up: **[docs/hardware/](docs/hardware/)**. That is the record; this page
does not repeat it.

Three recognised boards have fixes enabled. In install order, **bold** where
the fix runs and plain where it is listed but declines, which it does by name
and with the value it is missing rather than silently:

| Board | Fixes |
|---|---|
| `ZQC-P` `M1010` | **acpi-override** · **psr-band** · **oled-backlight** · **cdclk-ptl** · **edp-dsc** · **headset-mic** · **sof-audio** · **micmute** · **touchpad-edge** · **fan** · **fingerprint** · **battery** · **hotkeys** · **hotkey-actions** · **auto-rebuild** |
| `ZQC-P` `M1020` | **acpi-override** · **cdclk-ptl** · **micmute** · **touchpad-edge** · **fan** · **fingerprint** · **battery** · **hotkeys** · **hotkey-actions** · **auto-rebuild** |
| `ZQC-P` `M1050` | **acpi-override** · **psr-band** · **oled-backlight** · **cdclk-ptl** · **edp-dsc** · **headset-mic** · **sof-audio** · **micmute** · **touchpad-edge** · **fan** · **fingerprint** · **battery** · **hotkeys** · **hotkey-actions** · **auto-rebuild** |

A board below `verified` gets only the tier A subset, and `apply_patch.sh`
refuses to start on one without `ALLOW_UNVERIFIED=1`. Every other board revision
has no fixes at all, which is deliberate and is explained with the status words
in [docs/hardware/README.md](docs/hardware/README.md#what-the-status-words-mean).

The M1010 and M1050 rows being equal is not the same as the evidence behind
them being equal. What each rests on, fix by fix, is on
[the ZQC-P page](docs/hardware/zqc-p.md#what-the-verified-on-this-section-rests-on).

The table is generated from the profiles, and `tools/selftest.sh` fails if it
drifts from them.

---

## Installing

```bash
git clone <this-repo> HONOR_ZQC-P_M1010
cd HONOR_ZQC-P_M1010
sudo ./apply_patch.sh
sudo reboot
```

That is the whole thing. It is idempotent, backs up everything it replaces into
a timestamped directory, and every step after the ACPI override only warns on
failure, so one step that cannot build never blocks the rest.

Each fix also stands alone and is safe to re-run:

```sh
sudo bash patch/touchpad-edge/install.sh
```

### It checks the machine first

Before touching anything, `apply_patch.sh` reads DMI and looks for a matching
profile in [`devices/`](devices/). If there is none it stops. Step 2 installs
an ACPI table dumped from one specific unit's firmware, and a foreign SSDT is
not a fix that fails quietly.

Each fix installer does the same check on its own, so running
`patch/fan/install.sh` directly is exactly as guarded as going through
`apply_patch.sh`, and a fix a profile does not list refuses to install either
way.

Nothing model-specific is written into the scripts. The ids of the parts fitted
come out of the profile, and are then confirmed against the bus. What a fix
needs in order to run on a particular machine, the EC tachometer offsets, the
backlight floor, the charge pairs the EC arms, lives with that fix, in
`patch/<fix>/<model>/<board>/recipe.conf`, named after the same machine the
profile names. Adding a machine to a fix is writing one file there.

Each board section of a profile carries a `status`, and only `verified`
unlocks everything. Below that, `apply_patch.sh` stops unless you pass
`ALLOW_UNVERIFIED=1`, and then runs only the fixes that cannot carry another
machine's constants. What each status word means and what it allows:
[`docs/hardware/README.md`](docs/hardware/README.md#what-the-status-words-mean).

Three board sections are `verified`: `ZQC-P` `M1010`, the machine this was
built on; `ZQC-P` `M1020`, with a board-specific subset physically verified on
BIOS 1.10 and CachyOS; and `ZQC-P` `M1050`, on the strength of a dump, an ACPI set and an install
log from that machine. Detection reports which board it decided on, and says so
plainly when that is not one the profile describes.

### Options

| Variable | Effect |
|---|---|
| `SKIP_OLED=1` | leave the OLED backlight floor at the firmware value |
| `SKIP_EDGE=1` | leave the touchpad left-edge brightness gesture dead |
| `SKIP_FAN=1` | no fan RPM readout |
| `SKIP_FINGERPRINT=1` | no `libfprint` rebuild, by far the slowest step |
| `VBT_MIN=<n>` | backlight floor in n/255, default 12. Measure yours first with `patch/oled-backlight/measure-floor.sh` |
| `SKIP_CDCLK=1` | leave the Panther Lake cdclk fix out of the `xe.ko` rebuild |
| `SKIP_DSC=1` | leave the DSC preference out of it. Both run where the profile lists them; the build downloads the distro kernel source, about 260 MB, and compiles for a few minutes, and the two together build the module once |
| `CHARGE_PRESET="40 70"` | which battery charge preset to arm. Only the pairs the EC enforces work, see [`patch/battery/README.md`](patch/battery/README.md) |
| `KBDLIGHT_TIMEOUT=<seconds>` | ZQC-P M1020/C170 keyboard-backlight timeout; default 15, `0` means no timeout. The installer persists it in modprobe configuration |
| `FORCE_ACPI=1` | install the ACPI override even though your machine's `I2C_DEVT` table is not the one it was built from. That mismatch means a BIOS update rewrote it or this is a different machine; read [docs/RESEARCH.md](docs/RESEARCH.md) first |
| `ALLOW_UNVERIFIED=1` | run on a board whose profile section is not `verified`, restricted to the fixes that derive their own inputs |
| `GUARD_ZERO=1` | add a udev rule that bounces a write of `0` to the backlight back to `1`. Writing 0 blanks the panel rather than dimming it, and no VBT value can prevent that. Off by default |

The full step-by-step, how to verify it worked, and notes for other
bootloaders: **[docs/INSTALL.md](docs/INSTALL.md)**.

---

## The fixes

Each lives in its own directory under [`patch/`](patch/) with its own README
explaining what is broken, what was measured, and which approaches were ruled
out. [`patch/README.md`](patch/README.md) is the index.

| | |
|---|---|
| [`acpi-override/`](patch/acpi-override/) | patched SSDT: touchpad, touchscreen, keyboard |
| [`oled-backlight/`](patch/oled-backlight/) | the panel's firmware minimum is too low to render evenly |
| [`psr-band/`](patch/psr-band/) | a faint full-width band follows the mouse pointer |
| [`cdclk-ptl/`](patch/cdclk-ptl/) | garbled screen at boot on kernels 7.1.6 and newer |
| [`edp-dsc/`](patch/edp-dsc/) | the internal panel is driven at 6 bits per colour |
| [`battery/`](patch/battery/) | the charge limit the EC silently ignores |
| [`hotkeys/`](patch/hotkeys/) · [`hotkey-actions/`](patch/hotkey-actions/) | Fn keys that go nowhere, and then are ignored |
| [`micmute/`](patch/micmute/) · [`headset-mic/`](patch/headset-mic/) · [`sof-audio/`](patch/sof-audio/) | audio |
| [`touchpad-edge/`](patch/touchpad-edge/) | left-edge slide → brightness |
| [`fan/`](patch/fan/) · [`fingerprint/`](patch/fingerprint/) | sensors, biometrics |
| [`auto-rebuild/`](patch/auto-rebuild/) | keeps the rest applied across package updates |

---

## Documentation

| | |
|---|---|
| [docs/INSTALL.md](docs/INSTALL.md) | every step, verification, other bootloaders |
| [docs/hardware/](docs/hardware/) | one page per model: what it is, what works, what does not, and who found out |
| [docs/TESTING.md](docs/TESTING.md) | what to try and what to report, if you have a model nobody here owns |
| [docs/SUPPORT.md](docs/SUPPORT.md) | what "supported" means here, and where to take a question |
| [docs/LIMITATIONS.md](docs/LIMITATIONS.md) | what does not work and why, including the fan behaviour |
| [docs/NPU.md](docs/NPU.md) | the neural accelerator: it works out of the box, what it is worth, and why `sensors` cannot see it |
| [docs/ADDING-A-MODEL.md](docs/ADDING-A-MODEL.md) | dump → profile → verified, step by step |
| [docs/RESEARCH.md](docs/RESEARCH.md) | how the ACPI override was derived, and how to redo it elsewhere |
| [docs/WINDOWS-DUMP.md](docs/WINDOWS-DUMP.md) | making the Windows-side dump that answers "why does it work there" |
| [dump/](dump/) | the firmware tables and factory-OS dumps every fix was derived from |
| [CONTRIBUTING.md](CONTRIBUTING.md) | conventions for installers, how to send a patch |

---

## Have a model that is not covered?

**[Issue #11](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/11) is where this is tracked.** It lists where every model
stands, what a dump has to contain, and which numbers cannot be read off a
machine and have to be measured on it. Three `ZQC-P` revisions have verified
sections: M1010 and M1050 carry the full recorded set, while M1020 deliberately
enables only the smaller subset tested on that board. Everything else is
waiting on somebody who owns one.

One read-only command produces everything needed to write a profile for it:

```sh
sudo bash tools/collect-hwinfo.sh
```

It reads sysfs, never touches the serial-number attributes, and writes a single
archive of about 200 KB.

If the touchpad is missing entirely, that is the ACPI table failing to load,
and fixing it needs the firmware itself:

```sh
sudo bash tools/dump-acpi.sh
```

See [docs/RESEARCH.md](docs/RESEARCH.md) for what to do with the result, and
[docs/WINDOWS-DUMP.md](docs/WINDOWS-DUMP.md) if you still have the factory OS. Attach it to an issue using the "Hardware dump for a
new model" template. See [docs/ADDING-A-MODEL.md](docs/ADDING-A-MODEL.md).

---

## Credits

- Linux kernel docs:
  [`Documentation/admin-guide/acpi/initrd_table_override.rst`](https://docs.kernel.org/admin-guide/acpi/initrd_table_override.html)
- ACPI 6.5 spec, §6.4.3.6 *I²C Serial Bus Connection Resource* and §9.18.1.4
  *_DSM Specific Object*
- Microsoft HID-over-I²C protocol spec (UUID
  `3CDFF6F7-4267-4555-AD05-B30A3D8938DE`) — describes the `_DSM` call
  `i2c-hid-acpi` makes to discover the HID descriptor register address.
  Not needed by *this* patch since the OEM SSDT already implements it
  correctly inside `\_SB.PC00.I2C1.TPD0._DSM`.

---

## Licence

MIT, see [LICENSE](LICENSE), with two carve-outs.

**[`dump/`](dump/) is not ours to license.** It is unmodified factory data read
off the machine: the firmware's own ACPI tables, the PnP device list and a
scoped registry extract from the factory OS. The same goes for the corrected
table in [`patch/acpi-override/`](patch/acpi-override/), which is that firmware
table with one statement moved.

**Other people's code keeps their licence.** The patches under
[`patch/fingerprint/`](patch/fingerprint/) are third-party work
with authorship intact, each carrying its origin in the `recipe.conf` beside it;
the kernel module in [`patch/fan/`](patch/fan/) and the patch in
[`patch/keyboard-atkbd/`](patch/keyboard-atkbd/) are GPL-2.0.
