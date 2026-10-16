# MRA-XXX — MagicBook Art 14 2024

| | |
|---|---|
| Product code | `MRA-XXX`, board `MRA-XXX-PCB`, board version `M1040`, SKU `C170` |
| Platform | Intel Meteor Lake — Core Ultra 7 155H |
| Profile | [`devices/mra-xxx.conf`](../../devices/mra-xxx.conf) — **probed** |
| Read from | linux-hardware probes [35a02e8c69](https://linux-hardware.org/?probe=35a02e8c69) and `5E9D307274A3` in the [linuxhw/DMI](https://github.com/linuxhw/DMI/tree/master/Notebook/HONOR/MRA-XXX) mirror |

A different line from the MagicBook Pro, and it is here for one reason: **it
carries the same FocalTech touchscreen as the reference machine**, so
[`patch/micmute/`](../../patch/micmute/) applies unchanged.

Nobody has run a single fix on one. Everything below is read off probes —
except the **M1010** section, which is measured on the machine, and the two
companion pages: [power](mra-xxx-power.md) (what Windows PC Manager does,
what Linux measures, the reachable-but-unused EC/WMI surface) and
[touchpad](mra-xxx-touchpad.md) (the firmware "Gesture To Go" layer, the
vendor hidraw protocol, and the pressure digitizer). Both are read-only
investigations on a BIOS 3.05 machine.
 
 Other models: [index](README.md).

## Hardware

| | | Note |
|---|---|---|
| **CPU** | Core Ultra 7 155H | Meteor Lake, CPUID family 6 model 170 |
| **iGPU** | `8086:7d55`, subsystem `1ee7:2059`, `i915` | |
| **Audio** | `8086:7e28` Meteor Lake-P HD Audio, subsystem **`1ee7:2059`**, `sof-audio-pci-intel-mtl` | no `alc269` quirk upstream for this id |
| **Touchscreen** | **`2808:5662`**, ACPI `FTSC1000`, on `i2c_designware.0` | the same part as ZQC-P, FMB-P and MRB-XXX |
| **Touchpad** | **`35cc:0104`**, ACPI `TOPS0102` | matched upstream in `hid-multitouch` as `MT_CLS_VTL`, commit `7a5ab8071114` |
| **Fingerprint** | `10a5:a900` | no recipe here, and not in upstream `libfprint` |
| **Panel** | EDO `EDO14.55` OLED — the same panel FMB-P's EDID declares as Organic LED | |
| **Battery** | DESAY `AP16L5J`, 59.7 Wh | |
| **BIOS** | `3.01` (09/03/2024); `3.05` (03/07/2025) also seen | |
| **Runs on** | Ubuntu 24.04, kernel 6.8.0-49 | |

## Why `micmute` is listed

The fix binds to one HID id, `2808:5662`, and rewrites that device's report
descriptor so `hid-input` stops turning its vendor collection into a phantom
`KEY_MICMUTE`. It is tier A: on hardware without that touchscreen it matches
nothing and does nothing.

Whether this machine actually shows the symptom is **not** reported. The rule
this repository follows is that a recorded `touchscreen_hid=2808:5662` is enough
to list it, because the fix cannot misfire. If you have one and the microphone
does *not* mute itself, say so and it comes off the list.

## The libinput quirk that names this machine

`libinput` ships exactly one HONOR quirk, and it is for this model:

```
[HONOR MagicBook Art 14]
MatchName=*TOPS0102*
MatchDMIModalias=dmi:*:svnHONOR:pnMRA-XXX:*
MatchUdevType=touchpad
AttrEventCode=-BTN_RIGHT
AttrInputProp=+INPUT_PROP_PRESSUREPAD
```

It describes a clickpad that wrongly announces `BTN_RIGHT`. The `MatchName`
clause alone would also catch ZQC-P and XWC-P, which share the `TOPS0102` ACPI
name with entirely different silicon behind it; only the DMI clause keeps them
apart. See [the ZQC-P page](zqc-p.md#libinput-has-a-quirk-for-this-touchpad-gated-to-another-machine).

## Not established (M1040, the probed boards)

`camera_usb`, `backlight_max`, and anything the tier B fixes would need, and
whether the internal keyboard needs anything. On M1010 both of those are now
read — see [below](#board-m1010--measured-on-the-machine). `MRA-XXX` is not in
the upstream `atkbd` quirk table and neither revision shows an `i8042`
parameter on the command line.

`panel=oled` is recorded from the panel part number, which FMB-P's EDID
independently declares as Organic LED. The backlight floor still has to be
measured on the panel before [`patch/oled-backlight/`](../../patch/oled-backlight/)
could be offered, so it is not listed.

## Board M1010 — measured on the machine

Everything above is read off other people's probes, all of them board **M1040**
with a Core Ultra 7 155H. This section is one owner's own measurements of a
board **M1010** machine (Core Ultra 5 125H, BIOS 3.05, Omarchy, kernel
7.2.5), taken 2026-10-05 with this repository's `tools/collect-hwinfo.sh` and
`tools/dump-acpi.sh`. Same product code, same `MRA-XXX-PCB` board name, a
different machine: SKU is `C233` here against `C170` on the probed M1040.

### Established on this board

| | |
|---|---|
| Camera | `3277:00a8`, the detachable magnetic FHD Camera on USB port `3-4` |
| Backlight | `intel_backlight`, `max_brightness` **704**; floor walked 18→88 (vbt 7→32) with `measure-floor.sh` — **no tint, mura or blotches at any step, including the lowest**, so `oled-backlight` has nothing to fix on this unit |
| Fingerprint | `10a5:a900` — FPC, not Goodix. Working via the community driver [cityji/honor-magickbookpro-fingerprint-driver](https://github.com/cityji/honor-magickbookpro-fingerprint-driver) (libfprint 1.94.6 + MR396 + its patch set, FW `22.26.2.43`), not via this repository's Goodix patch and not in upstream libfprint |
| Hotkeys | the [`patch/hotkeys/`](../../patch/hotkeys/) keymap additions built as a standalone `huawei-wmi.ko` overlay and verified live: the keyboard backlight key fires (codes `0x2b1`–`0x2b4` were logged unmapped before, the keyboard lights after), plus `0x2e0`/`0x2e1` observed in dmesg. `fixes=hotkeys` in the profile reflects this run |

### Audio: the codec SSID is not the PCI SSID

The PCI audio function (`00:1f.3`) reports subsystem `1ee7:2059` — the same
value the M1040 probes carry, and what `audio_ssid` records. But the ALC256
codec's own subsystem id, the one `alc269` quirks match, reads **`1ee7:2060`**
on this board. They differ here, so a quirk written against the PCI id would
never fire.

The upstream M1020 quirk ([`d9448dca4235`](https://git.kernel.org/…/d9448dca4235),
`SND_PCI_QUIRK(0x1ee7, 0x2081, "HONOR MRB-XXX M1020", ALC256_FIXUP_HONOR_MRB_XXX_M1020_AUDIO)`)
re-pointed at the codec id restores the rest of the speaker system on this
board too:

```
SND_PCI_QUIRK(0x1ee7, 0x2060, "HONOR MRA-XXX M1010", ALC256_FIXUP_HONOR_MRB_XXX_M1020_AUDIO),
```

The stock BIOS marks pins 0x14 (second speaker pair) and 0x1a (bass pair)
`0x411111f0`, so six drivers ship and two play. With the fixup: dmesg reports
`picked fixup … SSID 1ee7:2060`, `autoconfig … line_outs=2 (0x1b/0x14)`, a
`Bass Speaker Playback Switch` appears, and a blind A/B of a 40–200 Hz sweep
against the stock table (order randomised) comes out unambiguous: the patched
pass has the low end, the stock pass does not. Built as a local
`snd-hda-codec-alc269.ko` overlay here; not yet sent upstream.

### Panel: same link ceiling as ZQC-P, but `edp-dsc` does not survive it here

The panel's DPCD, read over AUX: DP 1.4, exactly two link rates (2.7 and
5.4 Gbps, no HBR3), 4 lanes — byte-for-byte the situation
[the ZQC-P page](zqc-p.md) describes, and the same outcome: `bpp=18`,
dithering on. DSC is supported by the sink: revision 1.2, decompression,
RGB only, 8 and 10 bpc decode, block prediction, 11-bit line buffer,
4 slices.

**`edp-dsc` was tried on this board and fails**: the patch applied cleanly to
`intel_dp.c`, built as an `i915.ko` overlay with matching vermagic, verified
inside the rebuilt UKI — and the machine boots to a black screen at early KMS.
The stock module boots clean. ZQC-P is Panther Lake and runs its display
through `xe`; this board is Meteor Lake on `i915`, and the shared `intel_dp.c`
does not behave the same on both. The patch's fallback (put the uncompressed
result back if DSC fails) did not save the boot, which means the failure is
before that path — most plausibly in DSC link training at KMS. Not retried
with `drm.debug` yet; until somebody does, `edp-dsc` should be treated as
**xe-only** and the tier-A description ("runtime decides, nothing can break")
needs a driver-generation condition.

### Battery: the ZQC-P EC map does not transfer — RESOLVED

Writing `70 90` to `charge_control_thresholds` lands `146 / 0 / 0x1d` at the
ZQC-P offsets `0x80` / `0x81` / `0x85`, not `70 / 90 / 2` — because on this
board those bytes are **battery telemetry**, not charge state. Live EC reads
(2026-10-08) put the armed pair at **`0xE4` / `0xE5` = `0x46` / `0x5A` = 70/90
with `0xE6=02`**, i.e. mode 2 = PC Manager's "Office 70–90 %" preset, written
through mailbox `ECCC(0x82, start, stop)`. `\GBCM` derives the mode from the
start byte alone (40→1, 70→2, 95→3, else 0 = unarmed), so **only the three
preset pairs can arm**; an invalid pair (the desktop applet's 75/80) is echoed
back through sysfs but silently ignored by the EC. `patch/battery/` can be
prepared from this. Details, sources, and the full power picture:
`mra-xxx-power.md`.

### Not established, on this board too

The backlight floor (`param_backlight_min`), the headset microphone (the
M1020 fixup configures pin 0x19 for it, but no headset was plugged in while
testing), and the `micmute` symptom (not observed here either, but absence of
observation is not a report). The fan tachometer **offsets** are also resolved
(2026-10-08): there is nothing to re-find in plain EC RAM on this board — the
RPMs live in EC mailbox registers `0x20020A00–05`, reachable through `\GFNS`
(WMI `0x00000802`) or the mailbox read `RDER`, and manual control exists via
`WTER` (unlike ZQC-P). See `mra-xxx-power.md`.
