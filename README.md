# Linux on the HONOR MagicBook Pro 14 2026 AI

Fixes that make HONOR MagicBook Pro laptops usable under Linux: a patched ACPI
table for the touchpad and touchscreen, kernel-module quirks for audio and
sensors, HID-BPF programs for the touchpad gestures, a working battery charge
limit, and the Fn keys.

Built and verified on a **MagicBook Pro 14 2026 (`ZQC-P`, M1010)**. Thirteen
further profiles are recognised: the rest of the Pro line, and six machines from
the other MagicBook lines that share a platform or a part. See
[Models](#models) and [docs/hardware/](docs/hardware/).

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
| Screen garbled at boot, kernel 7.1.6 and newer | works, opt-in | [`patch/cdclk-ptl/`](patch/cdclk-ptl/) — rebuilds `xe.ko` with the upstream CDCLK fix Panther Lake needs. Merged to `drm-intel-next` on 2026-08-21, so expect it in Linux 7.3 and then a stable backport |
| Panel driven at 6 bits per colour, banding on gradients | works, opt-in | [`patch/edp-dsc/`](patch/edp-dsc/) — the link cannot carry 8 bpc and the driver drops colour depth before it will compress; a kernel patch makes it prefer DSC on eDP, with a fallback to the old behaviour |
| Battery charge limit does nothing | works | [`patch/battery/`](patch/battery/) — the EC only enforces HONOR's own preset pairs; anything else, including what the desktop sets, is stored and ignored |
| Performance and camera keys do nothing | works | [`patch/hotkey-actions/`](patch/hotkey-actions/) — a small service acts on the keys the desktop ignores |
| Keyboard backlight keys do nothing | experimental, opt-in | [`patch/keyboard-backlight/`](patch/keyboard-backlight/) — EC-backed three-level LED driver for the verified ZQC-P profile; needs a physical test on the target unit |
| Some Fn keys dead, `Unknown key pressed` in dmesg | works | [`patch/hotkeys/`](patch/hotkeys/) — adds the HONOR codes to the `huawei-wmi` keymap |
| Fan RPM readout | works | [`patch/fan/`](patch/fan/) — `honor-ec-sensors` |
| Fan speed control | curve control available, opt-in | direct PWM/RPM control is not exposed by the EC, but the validated early-engagement curves can be selected through [`patch/fan-curve/`](patch/fan-curve/). The controller forbids `0xAC`, monitors temperature and returns to stock `0xA0` on failsafe |
| SOF DSP suspend/resume panic | automatically handled | [`patch/sof-audio/`](patch/sof-audio/) — applies the backport only when the running kernel lacks the upstream fix, and removes a redundant overlay when it is already present |
| Fixes reverted by package updates | handled | [`patch/auto-rebuild/`](patch/auto-rebuild/) — package-manager hooks that rebuild them |
| Caps Lock LED | automatic from Linux 7.2 | `apply_patch.sh` detects the upstream `atkbd` quirk and removes redundant `i8042.dumbkbd=1`; older kernels keep the workaround. See [`patch/keyboard-atkbd/`](patch/keyboard-atkbd/) |
| Fn+F7 mic-mute key itself | verified in-tree | `huawei-wmi` already emits `KEY_MICMUTE`; `tools/doctor.sh` reports the input device and mic-mute LED so a broken desktop/audio stack is distinguishable from a dead key |

Speakers, headphone output, the built-in DMIC array, webcam, Wi-Fi and
Bluetooth need nothing beyond the ACPI override. One report on a BIOS 1.09 unit
says the speakers die with the same table failure; on this one, on BIOS 1.10,
the codec is on HDA and unaffected. See
[the speakers disagreement](docs/hardware/zqc-p.md#the-speakers-disagreement).

---

## Models

| Model | Machine | Platform | Profile |
|---|---|---|---|
| `ZQC-P` | MagicBook Pro 14 2026 (AI) | Panther Lake | **verified**, this is the reference unit |
| `XWC-P` | MagicBook Pro 16 2026 | Panther Lake | **reported** — and it ships the same ACPI table as ZQC-P, so the touchpad fix applies |
| `FMB-P` | MagicBook Pro 14 2025 | Arrow Lake | **reported** — from [colorcube's repo](https://github.com/colorcube/Linux-on-Honor-Magicbook-14-Pro) and 10 hardware probes |
| `FMB-PM` | MagicBook Pro 14 2025 Geek Edition | **Meteor Lake** | **reported** — from [sledeil's touchpad fix](https://github.com/sledeil/honor-fmb-pm-linux-touchpad-fix) |
| `DRB-P` | MagicBook Pro 16 2025 | Arrow Lake | draft |
| `DRB-P` | MagicBook Pro 16 HUNTER 2025, RTX 5070/5060 | Arrow Lake | **probed**, iGPU side only |
| `DRA-XX` | MagicBook Pro 16 2024 | Meteor Lake | **probed** |
| `DRA-XX` | MagicBook Pro 16 HUNTER 2024, RTX 4060 | Meteor Lake | **probed**, iGPU side only |
| `BCC-N` | MagicBook 14 2026 | Panther Lake | **probed** — same platform, same ACPI fault |
| `MRA-XXX` | MagicBook Art 14 2024 | Meteor Lake | **probed** — same touchscreen, so the mic-mute fix applies |
| `MRB-XXX` | MagicBook Art 14 2025 | Arrow Lake | **probed** — the same |
| `FRB-X` | MagicBook X14 Plus 2025 | Raptor Lake | **probed** — nothing here applies |
| `GLO-GXXX` | MagicBook 14 2023 | Raptor Lake | **probed** — nothing here applies |
| `FMI-XX` | MagicBook X14 Plus 2024 | AMD | draft — listed for the fan interface it shares with ZQC-P |

Four words, in decreasing order of how much anybody actually knows:
**verified** means the fixes were run on that machine here; **reported** means
somebody ran something on one and wrote it down, in another project;
**probed** means the device ids are genuine readings from a hardware probe but
nobody has tried a single fix; **draft** means the model is recognised and its
platform is known, and nothing else. Nobody working on this repository owns any
of these machines except the reference unit.

`DRA-XX` and `GLO-GXXX` are the literal strings HONOR's firmware reports,
whatever the marketing code on the box was: there is no `DRA-54`, `DRA-56` or
`DRA-72` in DMI, and the 2023 MagicBook 14 sold as `GLO-G561` reports
`GLO-GXXX`.

The six machines below the Pro line are there because each shares something
concrete: a platform, a touchscreen, a touchpad quirk, or a firmware method.
Three of them need nothing from here at all, and the profile exists so that
detection says "recognised, nothing to install" instead of refusing.

Note the platform column for `FMB-PM`: it is sold alongside the 2025 line but
the silicon is a Core Ultra 5 125H, which is Meteor Lake. An earlier draft here
inferred Arrow Lake from the marketing year and was wrong, which is why
`platform` is a recorded fact rather than something derived from `year`.

On anything but a `verified` profile the installer refuses by default;
`ALLOW_UNVERIFIED=1` unlocks only the fixes that cannot carry another machine's
constants.

Two models sell in both a UMA and a HUNTER variant under the same
`product_name`, so detection also looks for a discrete GPU to tell them apart.
Those machines are supported on their integrated-GPU side only: the proprietary
NVIDIA driver, PRIME and graphics switching are out of scope here.

Turning a draft into a verified profile takes one read-only dump and somebody
willing to run the fixes; see [below](#have-a-model-that-is-not-covered).

---

## Installing

```bash
git clone https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010.git HONOR_ZQC-P_M1010
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
`apply_patch.sh`. The model-specific values they need, device ids, the audio
subsystem id, the backlight floor, come out of the profile rather than being
written into the scripts.

Profiles carry a `status`. Only a `verified` one, meaning somebody actually ran
these fixes on that machine, unlocks everything. On a `reported` or `draft`
profile the run stops as well, and `ALLOW_UNVERIFIED=1` opens up just the
subset that cannot go wrong: fixes that read their inputs off the running
machine, or match on a device id and find nothing on hardware they were not
meant for. Anything carrying a measured backlight floor, an audio subsystem id
or an EC register offset stays disabled. The tiers are defined in
[`lib/profile.sh`](lib/profile.sh).

Right now exactly one profile is `verified`, the machine this was built on.

### Options

| Variable | Effect |
|---|---|
| `SKIP_OLED=1` | leave the OLED backlight floor at the firmware value |
| `SKIP_EDGE=1` | leave the touchpad left-edge brightness gesture dead |
| `SKIP_FAN=1` | no fan RPM readout |
| `FAN_CURVE=0xAA` or `0xAB` | opt into the guarded earlier fan-engagement curve; `0xA0` is stock and `0xAC` is rejected |
| `SKIP_FINGERPRINT=1` | no `libfprint` rebuild, by far the slowest step |
| `VBT_MIN=<n>` | backlight floor in n/255, default 12. Measure yours first with `patch/oled-backlight/measure-floor.sh` |
| `WITH_CDCLK=1` | rebuild `xe.ko` with the Panther Lake cdclk fix. Off by default: it downloads the distro kernel source, about 260 MB, and compiles for a few minutes |
| `WITH_DSC=1` | rebuild `xe.ko` with the eDP DSC preference. Off by default for the same kernel-source download/build reason |
| `CHARGE_PRESET="40 70"` | which battery charge preset to arm. Only the pairs the EC enforces work, see [`patch/battery/README.md`](patch/battery/README.md) |
| `FORCE_ACPI=1` | install the ACPI override even though your machine's `I2C_DEVT` table is not the one it was built from. That mismatch means a BIOS update rewrote it or this is a different machine; read [docs/RESEARCH.md](docs/RESEARCH.md) first |
| `ALLOW_UNVERIFIED=1` | run on a model whose profile is not `verified`, restricted to the fixes that derive their own inputs |
| `GUARD_ZERO=1` | add a udev rule that bounces a write of `0` to the backlight back to `1`. Writing 0 blanks the panel rather than dimming it, and no VBT value can prevent that. Off by default |

The full step-by-step, how to verify it worked, and notes for other
bootloaders: **[docs/INSTALL.md](docs/INSTALL.md)**.

For a post-reboot health check, run `sudo bash tools/doctor.sh`. It does not
change the system and can write a redacted JSON report with `--json`.

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
| [docs/ADDING-A-MODEL.md](docs/ADDING-A-MODEL.md) | dump → profile → verified, step by step |
| [docs/RESEARCH.md](docs/RESEARCH.md) | how the ACPI override was derived, and how to redo it elsewhere |
| [docs/WINDOWS-DUMP.md](docs/WINDOWS-DUMP.md) | making the Windows-side dump that answers "why does it work there" |
| [dump/](dump/) | the firmware tables and factory-OS dumps every fix was derived from |
| [CONTRIBUTING.md](CONTRIBUTING.md) | conventions for installers, how to send a patch |

---

## Have a model that is not covered?

**[Issue #11](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/11) is where this is tracked.** It lists where every model
stands, what a dump has to contain, and which numbers cannot be read off a
machine and have to be measured on it. Only `ZQC-P` is verified; everything
else is waiting on somebody who owns one.

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
[`patch/fingerprint/sensors/`](patch/fingerprint/sensors/) are third-party work
with authorship intact, each carrying its origin in the `recipe.conf` beside it;
the kernel module in [`patch/fan/`](patch/fan/) and the patch in
[`patch/keyboard-atkbd/`](patch/keyboard-atkbd/) are GPL-2.0.
