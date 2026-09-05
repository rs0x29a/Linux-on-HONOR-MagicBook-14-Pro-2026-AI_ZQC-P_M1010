# The machines

One page per model. Each holds what is known about that machine, what works,
what does not, and where every claim came from. The profile that drives the
installers is the matching file in [`devices/`](../../devices/); this is the
prose that a profile deliberately does not carry.

## What the status words mean

Almost every profile ships with **no fixes enabled**: the data below describes
the machine, it is not a report that anything was installed on it. The
exceptions are three `ZQC-P` revisions: `M1010`, measured here; `M1020`, whose
smaller safe subset was tested on a BIOS 1.09 unit; and `M1050`, whose owner sent
a hardware dump, a full set of ACPI tables and an install log from that machine.
What each rests on, fix by fix, is on [the ZQC-P page](zqc-p.md).

A status belongs to a **board revision**, not to a model. HONOR ships one
product code as several machines, so a profile has one `[board ...]` section per
revision and each carries its own status. A revision nobody has described runs
as `probed`: it keeps what is known about the product and never inherits another
board's measurements.

| Status | What somebody actually did | What the installer allows |
|---|---|---|
| **verified** | ran these fixes on that board | everything that section lists |
| **reported** | described that machine from it: a dump, a log, a report elsewhere. Not the same as having run these fixes and watched them | tier A only, and only with `ALLOW_UNVERIFIED=1` |
| **probed** | uploaded a hardware probe. The ids are real, no fix was tried | the same as reported |
| **draft** | nothing. Model and platform from published specifications | the same |

What a status allows depends on which **tier** a fix is in. The tiers are
assigned in [`lib/profile.sh`](../../lib/profile.sh):

| Tier | What the fix carries | Where it runs |
|---|---|---|
| **A** | nothing measured. It works its inputs out from the running machine, or matches on a device id and finds nothing on hardware it was not meant for | anywhere |
| **B** | constants measured on one board: a backlight floor, an audio subsystem id, EC register offsets | only on a `verified` section |
| **C** | a binary taken from one machine's firmware | only on the machine it came from |

So on an unverified board the answer to "why did it skip everything
interesting" is that nobody has confirmed those constants on that hardware yet,
and sending a dump is how that changes. This page and
[`docs/ADDING-A-MODEL.md`](../ADDING-A-MODEL.md) are the only two places that
explain this; everywhere else links here.

Moving a model up a row takes one person and one afternoon:
[ADDING-A-MODEL.md](../ADDING-A-MODEL.md).

## Index

**The MagicBook Pro line**, which is what this repository is built around:

| Model | Board | Machine | Platform | Status | Page |
|---|---|---|---|---|---|
| `ZQC-P` | `M1010` | MagicBook Pro 14 2026 (AI) | Panther Lake | verified | [zqc-p.md](zqc-p.md) |
| `ZQC-P` | `M1020` | the same, Core Ultra X9 388H, SKU C170 | Panther Lake | verified subset | [zqc-p.md](zqc-p.md#the-m1020-revision) |
| `ZQC-P` | `M1050` | the same, Core Ultra 5 338H | Panther Lake | verified | [zqc-p.md](zqc-p.md#the-m1050-revision) |
| `XWC-P` | `M1110`, `M1120` | MagicBook Pro 16 2026 | Panther Lake | reported, one section each | [xwc-p.md](xwc-p.md) |
| `FMB-P` | five, one section each | MagicBook Pro 14 2025 | Arrow Lake H | probed | [fmb-p.md](fmb-p.md) |
| `FMB-PM` | `M1030` | MagicBook Pro 14 2025 Geek Edition | Meteor Lake | reported | [fmb-pm.md](fmb-pm.md) |
| `DRB-P` | `M1020`, and unknown | MagicBook Pro 16 2025, and HUNTER | Arrow Lake H | draft / probed | [drb-p.md](drb-p.md) |
| `DRA-XX` | `M1020`, `M1030`, `M1040` | MagicBook Pro 16 2024, and HUNTER | Meteor Lake | probed, one section each | [dra-xx.md](dra-xx.md) |

**Machines from the other MagicBook lines** that share the platform or a part,
and are recognised for that reason:

| Model | Machine | Platform | Status | Page | Why it is here |
|---|---|---|---|---|---|
| `BCC-N` | MagicBook 14 2026 | Panther Lake | probed | [bcc-n.md](bcc-n.md) | same platform and the same ACPI fault as the 2026 Pro |
| `MRA-XXX` | MagicBook Art 14 2024 | Meteor Lake | probed | [mra-xxx.md](mra-xxx.md) | the same FocalTech touchscreen, so `micmute` applies |
| `MRB-XXX` | MagicBook Art 14 2025 | Arrow Lake H | probed | [mrb-xxx.md](mrb-xxx.md) | the same again |
| `FRB-X` | MagicBook X14 Plus 2025 | Raptor Lake | probed | [frb-x.md](frb-x.md) | nothing here applies, and saying so is the point |
| `GLO-GXXX` | MagicBook 14 2023 | Raptor Lake | probed | [glo-gxxx.md](glo-gxxx.md) | the machine the upstream touchpad quirk was written for |
| `FMI-XX` | MagicBook X14 Plus 2024 | AMD | draft | [fmi-xx.md](fmi-xx.md) | the model the upstream fan driver targets, using a method ZQC-P also has |

## What the firmware calls these machines

`product_name` is not the name on the box, and this trips people up:

* **`DRA-XX` and `GLO-GXXX` are literal strings.** The 2023 MagicBook 14 is
  sold as `GLO-G561` and reports `GLO-GXXX`. Every 2024 MagicBook Pro 16 reports
  `DRA-XX`,
  whatever the marketing code on the box was. There is no `DRA-54`, `DRA-56` or
  `DRA-72` in DMI, and no way found to recover which is which from firmware.
  Confirmed on three machines
  ([988dd23028](https://linux-hardware.org/?probe=988dd23028&log=dmidecode),
  [633e9bb800](https://linux-hardware.org/?probe=633e9bb800&log=dmidecode),
  [a3e7d421d4](https://linux-hardware.org/?probe=a3e7d421d4)); `dmesg` prints
  `DMI: HONOR DRA-XX/DRA-XX-PCB`. Profiles keyed on the marketing codes existed
  here until 2026-08-22 and could never have matched anything.
* **One product name covers several machines.** `DRB-P` is both the UMA laptop
  and the HUNTER with a discrete RTX; `FMB-P` spans five board revisions and two
  CPUs; `ZQC-P` covers four CPU SKUs. Detection narrows on the discrete GPU
  first, then on `board_version` (`M1010`, `M1020`, …).
* **`product_sku` identifies nothing.** `C233` is reported by ZQC-P, XWC-P, an
  FMB-P (board M1090), a DRA-XX (board M1030) and BCC-N. It is recorded, and it
  is the last tiebreaker tried, but it can only ever confirm.
* **`Family` is always `HONOR MagicBook`,** on every machine in the family.

## What is shared across the line

Worth knowing before reading any single page, because it repeats.

**The ACPI table that breaks the touchpad.** One module-level call inside an
unrelated `Device (NFC0)` runs `INT1 = GNUM (…)` at table-load time. `GNUM`
reaches `GINF`, which indexes a nested package before the namespace has
back-pointers; ACPICA aborts with `No pointer back to namespace node in package
(dsargs-364)` and then `AE_AML_INTERNAL`. The kernel rolls the whole table back,
so every I²C device it declared stops existing. Windows' interpreter tolerates
it, which is why the factory OS is fine.

Confirmed on ZQC-P, XWC-P, BCC-N, FMB-P and FMB-PM. **Not** present on DRA-XX
or DRB-P, whose touchpads work out of the box. Which table carries it differs:
the `I2C_DEVT` SSDT on the 2026 machines, the DSDT itself on the 2025 ones.

**ZQC-P and XWC-P ship the same `I2C_DEVT` table.** Byte-identical: 23708 bytes,
checksum `0xE5`, OEM revision `0x1000`, and a `diff`-clean 3862-line
disassembly, verified against phreer's published dump of an XWC-P. A 14-inch and
a 16-inch laptop on different BIOS versions, one table. So the corrected table
in [`patch/acpi-override/`](../../patch/acpi-override/) is right for both, and
the installer decides by comparing the md5 of the live table rather than by
asking which model this is. BCC-N's table is a different size (35,635 bytes) and
needs its own; nobody has published one.

Two things that look like this failure and are not:

* `ACPI Error: AE_NOT_FOUND, \_SB.PC00.I2C3.TPD0` at boot is universal across
  this whole family and harmless. It is a reference to a device slot the SKU
  does not populate.
* The bug once produced a real kernel NULL dereference. That is fixed:
  commit [`9d6c58dae8f6`](https://github.com/torvalds/linux/commit/9d6c58dae8f6590c746ac5d0012ffe14a77539f0)
  "ACPICA: Avoid walking the Namespace if start_node is NULL", written against
  `DMI: HONOR FMB-P/FMB-P-PCB, BIOS 1.13`, in v6.19 and backported to 6.18.y,
  7.0.y and 7.1.y. The table still fails to load; the kernel no longer crashes.

**The keyboard.** The embedded controller does not answer the `atkbd` command
byte, so the internal keyboard needs `i8042.dumbkbd=1` — at the cost of the
Caps Lock LED. Upstream now carries per-model quirks that do the same job
without the parameter and keep the LED:

| Model | Commit | First release |
|---|---|---|
| `FMB-P`, and `FMB-PM` by substring match | [`2aaf33c6e1e8`](https://github.com/torvalds/linux/commit/2aaf33c6e1e82561d7dce2345298a985a2483266) | 6.19 |
| `BCC-N` | [`fb402386af4c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/input/keyboard/atkbd.c) | 7.1 |
| `ZQC-P` | [`410c44b10967`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=410c44b1096789d0c40fbee706520e981dba7bc1) | 7.2, queued for 7.1.10 |
| `XWC-P` | none yet | — |

The kernel's `DMI_MATCH` is a `strstr`, not an exact comparison, which is why
the `FMB-P` entry also fires on an `FMB-PM`. `DRB-P` and `DRA-XX` are not in
the table and it is not established that they need to be.

**The battery limit that is not a limit.** `huawei-wmi` exposes charge
thresholds and the desktop writes them, but the EC only arms its limiter for
the pairs HONOR PC Manager offers. Anything else is stored and silently
ignored, and `upower` will happily report `charge-end-threshold: 80%` on a
machine charging to 100%. See [`patch/battery/`](../../patch/battery/).

**The hotkey codes.** Upstream `huawei-wmi` gained two HONOR codes in 6.18
(commit [`5c72329716d0`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=5c72329716d0858621021193330594d5d26bf44d),
`0x28b` YOYO and `0x28e` print screen). Everything else this family emits is
still missing from the in-tree keymap, and the set appears to be shared across
the line rather than per model.

**Wi-Fi needs no per-model work.** `iwlwifi`'s PPAG and TAS regulatory
allow-lists both carry a bare vendor-wide `DMI_MATCH(DMI_SYS_VENDOR, "HONOR")`
(commits `80b0c88033ff` in v6.9 and `06471b67d42e` in v6.5), so every HONOR
machine gets the full power tables already.

## Every part, across every model

The same view the profiles hold, laid out so the shared parts are visible. A
blank means nobody has read it off that machine, not that there is nothing
there. Sources are on each model's page.

| | ZQC-P | XWC-P | BCC-N | FMB-P | FMB-PM | DRB-P | DRA-XX |
|---|---|---|---|---|---|---|---|
| **touchscreen** | `2808:5662` | none fitted | ? | `2808:5662` | ? | ? | ? |
| **touchpad** | `27c6:0f9a` | ? | `36b6:c001` | `347d:7853`, some `27c6:01e0` | `347d:7853` | `347d:7853` | `347d:7853` |
| **camera** | `3277:00de` | `3277:00de` or `30c9:012c` | `3277:010d` | `3277:00b9` | ? | `3277:009f` | `3277:009f` |
| **fingerprint** | `27c6:6f94` / `1c7a:05aa` | `27c6:6f94` | `1c7a:05aa` | `10a5:9924` / `1c7a:05aa` | ? | `1c7a:05aa` | `27c6:5f10` / `10a5:a921` |
| **audio subsystem** | `1ee7:209d` | ? | `1ee7:210c` | `1ee7:2066` | ? | `1ee7:207a` | `1ee7:204d` |
| **codec** | ALC256 | ? | ? | ALC256 | ? | ALC256 | ALC256 |
| **panel** | OLED, EDO 14.55" | LCD, TL160MDMP01 | BOE NE140B90-M00 | OLED, EDO 14.55" | OLED | LCD, TL160MDMP01 | LCD, TL160MDMP01 |
| **EC fan tachos** | `0x2c`/`0x2e` | ? | ? | `0x2c`/`0x2e` | ? | ? | ? |

And the machines from the other lines:

| | MRA-XXX | MRB-XXX | FRB-X | GLO-GXXX | FMI-XX |
|---|---|---|---|---|---|
| **touchscreen** | `2808:5662` | `2808:5662` | ? | ? | ? |
| **touchpad** | `35cc:0104` | `35cc:0104` | `347d:7853` | `347d:7853` | `347d:7853` |
| **camera** | ? | ? | `3277:0045` | ? | `3277:0045` |
| **fingerprint** | `10a5:a900` | ? | `27c6:5f91` | ? | `10a5:a921` |
| **audio subsystem** | `1ee7:2059` | `1ee7:2081` | `1ee7:2074` | `1ee7:203a` | `1ee7:2053` |
| **panel** | OLED, EDO 14.55" | ? | CSW `CSW143B` | ? | ? |

FMI-XX is the odd one out in more than the CPU: its Wi-Fi is a Qualcomm
`17cb:1103`, so the vendor-wide `iwlwifi` regulatory entries that cover every
other machine here do not apply to it.

Four things fall out of those tables and are worth stating on their own.

**One camera vendor for the whole line.** Every machine here with a probed
camera uses USB vendor `0x3277`, and only the product half moves. So an unknown camera on a HONOR
MagicBook is `3277:00xx` with near-certainty — which is still not enough to
write into a profile, because the installer acts on the whole id.

**Four different touchpads, and three of them are already handled upstream.**

| Part | On | Upstream |
|---|---|---|
| `347d:7853` (ACPI `BLTP7853`) | GLO-GXXX, FMB-P, FMB-PM, DRA-XX, DRB-P, FRB-X, FMI-XX | `hid-multitouch` `MT_CLS_VTL` since **v6.7**, commit `9ffccb691adb` |
| `36b6:c001` (ACPI `CST3340`) | BCC-N | `i2c-hid` `I2C_HID_QUIRK_NO_IRQ_AFTER_RESET` since **v7.1**, commit `a991aa5e8936` |
| `35cc:0104` (ACPI `TOPS0102`) | MRA-XXX, MRB-XXX | `hid-multitouch` `MT_CLS_VTL`, commit `7a5ab8071114` |
| `27c6:0f9a` (ACPI `TOPS0102`) | ZQC-P | nothing. Works unaided once the ACPI table loads; the left-edge gesture needs [`patch/touchpad-edge/`](../../patch/touchpad-edge/) |

Note the last two share an ACPI name and are different silicon. **`TOPS0102`
is a slot name, not a part number**, and inferring a HID id from it is how this
repository once recorded a wrong `touchpad_hid` for XWC-P.

**The FocalTech touchscreen is on four machines.** `2808:5662`, ACPI
`FTSC1000`, confirmed on ZQC-P, FMB-P, MRA-XXX and MRB-XXX. It is the device
whose vendor collection `hid-input` turns into a phantom `KEY_MICMUTE`, which
[`patch/micmute/`](../../patch/micmute/) fixes, and all four profiles list it.
The fix binds to that one HID id, so on a unit without the part it matches
nothing.

**Three fingerprint readers have a recipe here, four do not.** `27c6:6f94`,
`1c7a:05aa` and `10a5:9924` are covered under
[`patch/fingerprint/`](../../patch/fingerprint/). `27c6:5f10`
and `10a5:a921` (DRA-XX), `10a5:a900` (MRA-XXX) and `27c6:5f91` (FRB-X) have
none, and not one of the seven is in upstream `libfprint`.

## Where published ACPI tables live

The one thing that cannot be reconstructed from anywhere but the machine, and
the reason most of these profiles are incomplete. What exists publicly, checked
2026-08-22:

| Model | Table | Where | Notes |
|---|---|---|---|
| `ZQC-P` | `I2C_DEVT` SSDT, stock and patched | [`dump/acpi/zqc-p/`](../../dump/acpi/zqc-p/) and [`patch/acpi-override/`](../../patch/acpi-override/) here | plus every table the factory OS sees, in [`dump/win11/zqc-p/`](../../dump/win11/zqc-p/) |
| `XWC-P` | the same table | [phreer](https://github.com/phreer/xwc-p-touchpad-ssdt-fix): full disassembly of the stock one, three corrected variants, one prebuilt `.aml` | identical to the ZQC-P table, see above |
| `FMB-P` | patched DSDT | [denis-bb](https://github.com/denis-bb/honor-fmb-p-dsdt) (also stock, as `.dsl`), [drphilth](https://github.com/drphilth/honor-magicbook-pro-14-ubuntu), [NOREIED](https://github.com/NOREIED/linux-honor-fmb-p-dsdt), [EvernightFedora](https://github.com/EvernightFedora/evernight-honor-acpi) | three distinct binaries, [fmb-p.md](fmb-p.md#three-patched-dsdts-are-in-circulation) |
| `FMB-P` BIOS 1.16 | patch only | [astenir](https://github.com/astenir/honor-fmb-p-bios-1.16-dsdt) | a `.patch` and a build script, no binary |
| `FMB-PM` | patch only | [sledeil](https://github.com/sledeil/honor-fmb-pm-linux-touchpad-fix) | `fmb-pm-bios-2.07.patch`, no binary |
| `BCC-N` | **none published** | — | one owner's `dmesg` proves the fault; the table itself has never been dumped |
| `DRA-XX`, `DRB-P` | not needed | — | no table-load failure on those machines |

If you have a BCC-N, a DRA-XX or a DRB-P, one run of
[`tools/dump-acpi.sh`](../../tools/dump-acpi.sh) is the contribution nothing
else substitutes for.

> **`acpidump` lies when an override is installed.** It reads through the
> kernel, which has already applied the override, so what comes back is the
> *patched* table. This is not theoretical: the "full acpidump from my unit"
> attached to denis-bb issue #8, offered as evidence of an undiscovered regional
> firmware variant, is byte-identical to denis-bb's own patched Chinese table
> (`7830156903fc1f43fc42d3463ec41153`). The hypothesis it was meant to support
> cannot be tested with it. [`tools/dump-acpi.sh`](../../tools/dump-acpi.sh)
> detects the situation and says so; for a genuine dump, boot once without the
> override.

## What the kernel knows about HONOR

The complete list of HONOR product codes appearing anywhere in the kernel
tree, as of 7.2:

| Where | Codes |
|---|---|
| `drivers/input/keyboard/atkbd.c` | `FMB-P`, `BCC-N`, `ZQC-P` |
| `drivers/hid/hid-multitouch.c` | `347d:7853` (`GLO-GXXX`), `35cc:0104` (MagicBook Art 14) |
| `sound/hda/codecs/realtek/alc269.c` | `1ee7:2078` (`BRB-X`), `1ee7:2081` (`MRB-XXX`) |
| `drivers/platform/x86/huawei-wmi.c` | no DMI handling at all, only the two keycodes |
| `sound/soc/amd/acp6x` | `GOH-X` (an AMD machine) |
| arm64 device tree | `honor,magicbook-art-14-snapdragon` |

`libinput` ships exactly one HONOR quirk,
[`50-system-honor.quirks`](https://gitlab.freedesktop.org/libinput/libinput/-/raw/main/quirks/50-system-honor.quirks),
gated on `pnMRA-XXX`. `systemd`'s hwdb has no HONOR keyboard or evdev entry of
any kind, which is why nothing here can collide with it.

## Other HONOR machines, and where the line is drawn

linux-hardware.org holds 336 probes across 40 HONOR product codes. The fourteen
profiles here cover twelve product codes: nine of those forty, plus `ZQC-P`,
`XWC-P` and `FMB-PM`, which have **no probe there at all**. The best documented
machine in this repository is one of the three the database has never seen,
which is worth remembering before treating probe counts as a measure of how
common a laptop is.

What is left out, and why:

| Codes | What they are |
|---|---|
| `BBR-WAX9`, `BMH-WCX9`, `BMH-WDX9`, `BOD-WXX9`, `BOHK-WAX9X`, `BRG-XXX`, `BRI-XX`, `BRN-FXX`, `BRN-FXXC`, `BRN-GXXX`, `BRN-GXXXA`, `BRN-HXX`, `BRN-HXXB` | MagicBook X, 14, 15 and Pro from 2020 to 2022, Intel 10th to 12th generation and AMD Zen 2/3 |
| `FRG-X`, `FRI-FXX`, `FRI-GXXXA`, `FRI-HXX`, `GDG-X`, `GLO-FX6P`, `GLO-NX6`, `HGE-WX6`, `HGF-WX6`, `HLYL-WXX9`, `HYM-WXX`, `NBD-WXX9`, `NBLK-WAX9X`, `NBR-WAX9`, `NMH-WCX9`, `NMH-WDX9`, `NVN-ED01` | the same, other years and regions |
| `GOH-X` | an AMD machine, already in the kernel through `sound/soc/amd/acp6x` |
| `BRB-X` | not probed on linux-hardware, but its audio subsystem id `1ee7:2078` is in `alc269.c` with the same `ALC2XX_FIXUP_HEADSET_MIC` this repository applies to ZQC-P |

None of the fixes here applies to them: no `AE_AML_INTERNAL`, a different EC
generation, different audio subsystem ids, and in most cases nothing broken that
needs fixing. They are not covered because there is nothing to cover, not
because nobody looked.

**If that turns out to be wrong for yours**, the work is small and written down:
run [`tools/collect-hwinfo.sh`](../../tools/collect-hwinfo.sh), open an issue,
and [ADDING-A-MODEL.md](../ADDING-A-MODEL.md) turns it into a profile.

## Related work

Other people's repositories on the same hardware. Where this repository takes
something from one of them, the model page says so.

| | |
|---|---|
| [colorcube/Linux-on-Honor-Magicbook-14-Pro](https://github.com/colorcube/Linux-on-Honor-Magicbook-14-Pro) | FMB-P, the most active of these by some way |
| [drphilth/honor-magicbook-pro-14-ubuntu](https://github.com/drphilth/honor-magicbook-pro-14-ubuntu) | FMB-P as Debian packages, and the clearest write-up of the DSDT root cause |
| [drphilth/honor-fmbp-libfprint-sdcp](https://github.com/drphilth/honor-fmbp-libfprint-sdcp) | the EgisTec SDCP patches carried in [`patch/fingerprint/`](../../patch/fingerprint/) |
| [denis-bb/honor-fmb-p-dsdt](https://github.com/denis-bb/honor-fmb-p-dsdt), [astenir/honor-fmb-p-bios-1.16-dsdt](https://github.com/astenir/honor-fmb-p-bios-1.16-dsdt), [NOREIED/linux-honor-fmb-p-dsdt](https://github.com/NOREIED/linux-honor-fmb-p-dsdt), [EvernightFedora/evernight-honor-acpi](https://github.com/EvernightFedora/evernight-honor-acpi) | patched FMB-P DSDTs. Four projects, three different binaries, see [fmb-p.md](fmb-p.md#three-patched-dsdts-are-in-circulation) |
| [lcrhf1999](https://github.com/lcrhf1999/HONOR-Magicbook-14-2026-dmidecode) | a full `dmidecode` and `dmesg` for BCC-N, the second source for that model |
| [sledeil/honor-fmb-pm-linux-touchpad-fix](https://github.com/sledeil/honor-fmb-pm-linux-touchpad-fix) | FMB-PM, the only report of that machine anywhere |
| [phreer/xwc-p-touchpad-ssdt-fix](https://github.com/phreer/xwc-p-touchpad-ssdt-fix) | XWC-P, with a full root-cause analysis |
| [laeo/Honor-XWC-Linux-Patch](https://github.com/laeo/Honor-XWC-Linux-Patch) | XWC-P. Its own description says it was AI-generated, and the two ACPI tables it ships are this repository's files byte for byte. Harmless, since the table is shared, but it is not a source about XWC-P hardware |
| [SamenVas/honor-magicbook-pro-zqc-p-linux-fix](https://github.com/SamenVas/honor-magicbook-pro-zqc-p-linux-fix) | the same ZQC-P, independently, on BIOS 1.09 |
| [mark-herbert42/art14-fan-daemon](https://github.com/mark-herbert42/art14-fan-daemon) | real fan *control* on a MagicBook Art 14, through an EC method ZQC-P does not have |
| [MadhiasM/HonorMagicbookArtCompatibility](https://github.com/MadhiasM/HonorMagicbookArtCompatibility) | MagicBook Art 14, a different line, with a thorough compatibility matrix |
| [aymanbagabas/Huawei-WMI](https://github.com/aymanbagabas/Huawei-WMI) | the out-of-tree driver these hotkey mappings ultimately derive from |
| [andreas-fe/goodix-27c6-6f94-linux-driver](https://github.com/andreas-fe/goodix-27c6-6f94-linux-driver) | reverse-engineering of the same fingerprint reader ZQC-P carries |

One code seen in the wild that is **not** a machine in this family:
`yuofi/honor-magicbook-pro-14-arch-fix` calls its target `FMT-B`, but the DSDT
it ships is byte-identical to denis-bb's global FMB-P dump. Treat it as an
FMB-P repository under another name.
