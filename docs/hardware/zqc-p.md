# ZQC-P — MagicBook Pro 14 2026 (AI)

| | |
|---|---|
| Product code | `ZQC-P`, board versions `M1010`, `M1020`, `M1050`, board `ZQC-P-PCB` |
| Platform | Intel Panther Lake, Core Ultra X9 388H or Core Ultra 5 338H |
| Profile | [`devices/zqc-p.conf`](../../devices/zqc-p.conf) — three verified sections: `[board M1010]` measured here, [`[board M1020]`](#the-m1020-revision) with a smaller tested subset, and [`[board M1050]`](#the-m1050-revision) from its owner |
| Verified on | M1010: BIOS 1.10, CachyOS, kernel 7.1.8; M1020: BIOS 1.10, CachyOS, kernel 7.2.2 |

This is the machine the repository was built on: every value in the `[board
M1010]` section of its profile was read off this unit and every fix was run on
it. Where a statement below is not a measurement taken here, it says whose it
is.

**`ZQC-P` is more than one machine.** Everything on this page is board `M1010`
unless it says otherwise; see [the M1020 revision](#the-m1020-revision) and
[the M1050 revision](#the-m1050-revision).

Other models: [index](README.md).

## The machine

| | |
|---|---|
| **Manufacturer** | HONOR |
| **Product name** | ZQC-P |
| **Marketing name** | HONOR MagicBook Pro 14 AI (2026) |
| **DMI version** | M1010 |
| **CPU** | Intel® Core™ Ultra X9 388H ("Panther Lake") |
| **PCH GPIO ID** | `INTC10BC` (five communities, gpiochip0..4) |
| **BIOS** | HONOR 1.10 (2026-06-03) |
| **Panel** | EDO 14.55" OLED, 3120x2080 at 120 Hz, backlight on native PWM at 200 Hz |
| **Touchpad** | Goodix **TOPS0102** on `\_SB.PC00.I2C1.TPD0` (I²C HID, addr `0x5D`) |
| **Touchscreen** | FocalTech **FTSC1000** on `\_SB.PC00.I2C2.TPL1` (I²C HID) |
| **Fingerprint** | Goodix USB `27c6:6f94` — works with a two-line `libfprint` patch, see [`patch/fingerprint/`](../../patch/fingerprint/) |
| **Webcam (built-in)** | Shinetech FHD over USB (`3277:00de`) — works out of the box |

Both touch devices are advertised in firmware with `_HID/_CID = PNP0C50`
(Microsoft HID-over-I²C), so the in-kernel `i2c-hid-acpi` driver is the
correct binding — there is no need for a vendor-specific driver.

---

## Tested on

| | |
|---|---|
| OS | CachyOS (Arch-based, rolling) |
| Kernel | `linux-cachyos 7.1.5-1`, earlier work on 7.0.x and `linux-cachyos-lts 6.18.31-1` |
| initramfs | `mkinitcpio 41-x` |
| Bootloader | `limine 11.x` with `limine-mkinitcpio-hook` |
| Desktop | GNOME 50 on Wayland, PipeWire 1.6.6 |

Kernel requirements: `CONFIG_ACPI_TABLE_UPGRADE=y` and
`CONFIG_ARCH_HAS_ACPI_TABLE_UPGRADE=y` for the ACPI override, `CONFIG_HID_BPF=y`
and `CONFIG_DEBUG_INFO_BTF=y` for the mic-mute fixup. Anything from 6.10 on
qualifies. Other bootloaders work, see [Other bootloaders](../INSTALL.md#other-distributions-and-bootloaders).

The same patches should apply to any HONOR ZQC-P/M1010 unit regardless of
distro, as long as the kernel supports initrd ACPI table overrides and you have
a way to put the patched SSDT into an *early*, uncompressed CPIO.

---

## Device support matrix

Legend: ✅ works · ⚠️ works partially / driver missing in mainline · ❌ broken
or unavailable · ➖ not applicable / OEM placeholder device

After running `apply_patch.sh` and rebooting, the following has been verified
on `linux-cachyos 7.0.8` (Panther Lake-aware) under CachyOS.

### Core platform

| Component | Linux identifier / driver | Windows identifier / driver | Status |
|---|---|---|---|
| CPU — Intel Core Ultra X9 388H (Panther Lake) | `intel_pstate`, `intel_idle`, `coretemp` | Intel Processor | ✅ |
| Integrated GPU — Intel Arc B390 | PCI `8086:b080`, `xe` (modern Xe driver) | Intel Arc Graphics | ✅ |
| Internal panel — EDO 14.55" OLED, 3120x2080 120 Hz | eDP-1, `intel_backlight` (native PWM, 200 Hz, `max_brightness` 704) | Intel Arc Graphics | ✅ *needs two patches* — the VBT declares a 2.4% minimum this panel cannot render evenly ([`patch/oled-backlight/`](../../patch/oled-backlight/)), and PSR2 selective update paints a visible band that follows the pointer ([`patch/psr-band/`](../../patch/psr-band/)). It is also running at 6 bpc, see [below](#the-panel-is-driven-at-6-bits-per-colour) |
| Intel NPU (AI accelerator) | PCI `8086:b03e`, `intel_vpu` | Intel AI Boost | ✅ |
| Intel Platform Monitoring Telemetry | PCI `8086:b07d`, `intel_vsec`, `intel_pmc_ssram_telemetry` | Intel PMT | ✅ |
| Intel Innovation Platform Framework (DTT) | PCI `8086:b01d`, `proc_thermal_pci` | Intel Dynamic Tuning | ✅ |
| EDAC memory controller | PCI `8086:b001`, `igen6_edac` | (none) | ✅ |
| LPSS I²C controllers ×3 | PCI `8086:e478/e479/e47a`, `intel-lpss` | Intel Serial IO I²C #0/1/2 | ✅ |
| eSPI / LPC bridge | PCI `8086:e402` | Intel LPC/eSPI E402 | ✅ |
| SMBus controller | PCI `8086:e422`, `i801_smbus` | Intel SMBus E422 | ✅ |
| SPI controller (BIOS flash) | PCI `8086:e423`, `intel-spi` | Intel SPI E423 | ✅ |
| Intel CSE / ME | PCI `8086:e470`, `mei_me` | Intel Management Engine | ✅ |
| TPM 2.0 | ACPI `INTC7002`, `tpm_crb` | Trusted Platform Module 2.0 | ✅ |
| PCH watchdog | ACPI `INTC109D`, `iTCO_wdt` | Intel CWDT | ✅ |

### Storage / power / chassis

| Component | Linux identifier / driver | Windows identifier / driver | Status |
|---|---|---|---|
| NVMe SSD — YMTC PC411 (DRAM-less) | PCI `1e49:1071`, `nvme` | Standard NVM Express Controller | ✅ |
| AC adapter | ACPI `ACPI0003`, `ac` | Microsoft AC Adapter | ✅ |
| Battery | ACPI `PNP0C0A`, `battery` (+ `huawei_battery` hook) | Microsoft ACPI-Compliant Control Method Battery | ✅ |
| Lid switch | ACPI `PNP0C0D`, `button` | ACPI Lid | ✅ |
| Power button | ACPI `PNP0C0C`, `button` | ACPI Power Button | ✅ |
| Embedded Controller (EC) | ACPI `PNP0C09`, `acpi_ec` | Microsoft ACPI-Compliant EC | ✅ |

### Networking

| Component | Linux identifier / driver | Windows identifier / driver | Status |
|---|---|---|---|
| Wi-Fi — Intel CNVi (Panther Lake) | PCI `8086:e440`, `iwlwifi` | Intel(R) Wi-Fi 6E AX211 160MHz | ✅ |
| Bluetooth — Intel CNVi | PCI `8086:e476`, `btintel_pcie` | Intel Wireless Bluetooth | ✅ |
| Thunderbolt 4 / USB4 | PCI `8086:e433` + `8086:e462`, `thunderbolt` | Thunderbolt 4 Controller | ✅ |

### USB

| Component | Linux identifier / driver | Windows identifier / driver | Status |
|---|---|---|---|
| xHCI controller (TCSS) | PCI `8086:e431`, `xhci_hcd` | Intel USB 3.2 xHCI Controller | ✅ |
| xHCI controller (USB2/3 ports) | PCI `8086:e47d`, `xhci_hcd` | Intel USB 3.2 xHCI Controller | ✅ |
| Built-in webcam — Shinetech FHD | USB `3277:00de`, `uvcvideo` | USB Video Device | ✅ |

### Input

| Component | Linux identifier / driver | Windows identifier / driver | Status |
|---|---|---|---|
| **Touchpad — Goodix TOPS0102** | ACPI `\_SB.PC00.I2C1.TPD0` → `i2c-TOPS0102:00`, `i2c_hid_acpi` + `hid-multitouch` (HID `27C6:0F9A`) | `\_SB.PC00.I2C1.TPD0`, `hidi2c.inf` (HID I²C Device) | ✅ *needs this patch* |
| **Touchscreen — FocalTech FTSC1000** | ACPI `\_SB.PC00.I2C2.TPL1` → `i2c-FTSC1000:00`, `i2c_hid_acpi` + `hid-multitouch` (HID `2808:5662`) | `\_SB.PC00.I2C2.TPL1`, `hidi2c.inf` (HID I²C Device) | ✅ *needs this patch* |
| **Built-in keyboard** | ACPI `MSFT0001`/`PNP0303` → `i8042`, "AT Translated Set 2 keyboard" | Microsoft PS/2 Keyboard | ✅ *needs `i8042.dumbkbd=1` below kernel 7.2* |
| Caps Lock LED | (keyboard-internal, driven via atkbd `SET_LEDS`) | (same) | ✅ *from kernel 7.2, or 7.1.10* — the upstream `atkbd` quirk removes the need for `i8042.dumbkbd=1`, see [the keyboard](#the-keyboard-and-the-caps-lock-led) |
| Hotkey / function-key WMI | `huawei_wmi`, "Huawei WMI hotkeys" input | Huawei PC Manager hotkey driver | ✅ |
| **Touchpad edge slide, right (volume)** | touchpad → EC → i8042 → `atkbd`, `KEY_VOLUMEUP/DOWN` on the internal keyboard device | HONOR PC Manager | ✅ works out of the box |
| **Touchpad edge slide, left (brightness)** | vendor HID collection `0xff00`, report `0x0e`, ignored by `hid-input` | HONOR PC Manager | ✅ *needs this patch* — see [`patch/touchpad-edge/`](../../patch/touchpad-edge/) |
| **Fn+F7 mic-mute key** | `huawei_wmi` WMI hot-key → `KEY_MICMUTE`; LED at `/sys/class/leds/platform::micmute` with `audio-micmute` trigger | Huawei PC Manager mic toggle | ✅ *works out of the box*; the LED only follows DMIC mute, not the analog headset mic |
| **Phantom `KEY_MICMUTE`** | `hid-multitouch` exported the FTSC1000 touchscreen's `0xff01` vendor collection, which `hid-input` maps to `KEY_MICMUTE` | none — a FocalTech driver claims the collection | ✅ fixed by [`patch/micmute/`](../../patch/micmute/); without it the mic mutes itself continuously |
| PS/2 mouse port (legacy) | ACPI `MSFT0003`, status=0 | (disabled by firmware) | ➖ disabled in firmware (correctly) |
| ACPI Video / brightness | `acpi-video`, "Video Bus" input | Intel Display Control | ✅ |

### Audio

| Component | Linux identifier / driver | Windows identifier / driver | Status |
|---|---|---|---|
| HD-Audio + DSP (SOF) | PCI `8086:e428`, `sof-audio-pci-intel-ptl`, card `sofhdadsp` (HDA Analog + 3× HDMI) | Realtek HD Audio + Intel SST | ✅ *needs this patch* — see [`patch/sof-audio/`](../../patch/sof-audio/) (suspend/resume reliability) |
| Phantom `KEY_MICMUTE` | the FTSC1000 touchscreen's `0xff01` vendor collection, which `hid-input` maps to `KEY_MICMUTE` | none, a FocalTech driver claims the collection | ✅ *needs this patch* — see [`patch/micmute/`](../../patch/micmute/); without it the mic mutes itself |
| Speakers / headphone jack | ALSA `sof-hda-dsp Headphone` | (same as above) | ✅ |
| Microphone array (DMIC) | SOF DMIC capture, `HiFi__Mic1__source` (4ch) | Intel Smart Sound DMIC | ✅ |
| 3.5mm-jack headset microphone | ALC256 pin 0x19, `HiFi__Mic2__source` (2ch stereo) | Intel SST + Realtek HD Audio | ✅ *needs this patch* — see [`patch/headset-mic/`](../../patch/headset-mic/) |

### Sensors / thermal

| Component | Linux identifier / driver | Windows identifier / driver | Status |
|---|---|---|---|
| Intel DTT — `IETM` root | ACPI `INTC10D4`, `int3400_thermal` (thermal_zone1) | Intel Dynamic Tuning Technology | ✅ |
| Thermal sensors SEN1..SEN7 | ACPI `INTC10D5`, `int3403_thermal` (thermal_zone2..8) | Intel DTT virtual thermal sensors | ✅ |
| Thermal fan participant TFN1 | ACPI `INTC10D6`, `int3404_fan` | Intel DTT fan | ✅ |
| **CPU/exhaust fans (physical)** | EC tachometers at ECF0 `0x2C-0x2F` via `honor-ec-sensors`, or `\GFNS` in ACPI; PWM duty `F0PD`/`F1PD` locked behind `MFGM` | HONOR PC Manager fan control | ⚠️ *RPM readout works; no control route was found on this machine, and the EC only ramps hard above ~85 °C CDTS — see [the fans](#the-fans) and [Cooling and fan behaviour](../LIMITATIONS.md#cooling-and-fan-behaviour)* |
| Battery charge participant | ACPI `INTC10D5` (CHRG) | Intel DTT charger | ✅ |
| CPU package / per-core temp | `coretemp`, `x86_pkg_temp_thermal` (thermal_zone9..12) | hwmon equivalents | ✅ |
| WiFi thermal | `iwlwifi_1` (thermal_zone11) | (vendor private) | ✅ |
| Power-budget participant TPWR | ACPI `INTC10D8`, status=0 | Intel DTT TPWR | ➖ disabled in firmware |
| Battery DTT participant BAT1 | ACPI `INTC10D9`, status=0 | Intel DTT BAT1 | ➖ disabled in firmware |
| Touch-screen enable (TSE) helper | ACPI `INTC10DF` (`\_SB.PC00.TSE_`), status=0 | Intel TSE | ➖ disabled in firmware |

### Bio / NFC / OEM helpers

| Component | Linux identifier / driver | Windows identifier / driver | Status |
|---|---|---|---|
| **Fingerprint — Goodix USB** | USB `27c6:6f94`, "Goodix USB2.0 MISC" → `libfprint` `goodixmoc` driver | `oem32.inf` Goodix Biometric (custom MOC driver) | ✅ works after a [two-line `libfprint` id patch](../../patch/fingerprint/) |
| NFC — NXP NTAG | ACPI `NTAG0001` → `i2c-NTAG0001:00`, no driver bound | `\Driver\SpbNfcDriver` | ❌ no in-tree Linux driver — appears as bare I²C device |
| Microsoft HID button helper (HIDD) | ACPI `INTC10CC`, status=0 | Microsoft HID button collection | ➖ disabled in firmware |
| Intel Acoustic Context Mgr (ACM) | ACPI `INTC1025`, status=null | Intel Acoustic Context Manager | ➖ no `_STA` returned by firmware |

### Reserved / not present

| Component | Linux identifier | Windows identifier | Status |
|---|---|---|---|
| MIPI CSI camera modules (FLM1, F1Mx) | ACPI `\_SB.FLM1`, `_HID="TXNW3643"`, status=15 — but no MIPI sensor connected | (not used; the working webcam is USB) | ➖ template device, no physical sensor on this SKU |
| Other MIPI templates (FLM0/2/3/4/5) | ACPI `TXNW3643`, status=0 | (disabled) | ➖ disabled in firmware |
| INT3472 PMIC clusters (CLP0-5, DSC0-5) | ACPI `INT3472`, status=0 | (disabled) | ➖ disabled — these only matter when a MIPI sensor is wired |

See [what does not work](../LIMITATIONS.md) for what is not fixed.

---

## One product name, four machines

`ZQC-P` is sold with at least four CPUs: the Core Ultra X9 388H measured here
(Arc B390), an X7 358H (this repository's issue #4, inko32), and a Core Ultra 5
338H (denis-bb #6, and Notebookcheck's review unit, Arc B370) and 5 336H
(honor.com CN). All report `product_name ZQC-P`, and the iGPU PCI id is
`8086:b080` regardless.

Two fingerprint readers, split by region: global units carry the Goodix
`27c6:6f94`, Chinese ones a LighTuning/EgisTec `1c7a:05aa` (issue #3, inko32;
full `lsusb` in issue #8, pilgrim1990). The profile lists both and the installer
probes the USB bus.

Nothing in the profile depends on which CPU is fitted, and no fix here has been
tried on anything but the X9.

`product_sku` is `C233`, which is also what an XWC-P, an FMB-P board M1090, a
DRA-XX board M1030 and a BCC-N report. It is recorded and it is never the
deciding value.

## Board revisions, and why the profile lists only one

`devices/zqc-p.conf` records `dmi_board_version=M1010`. That is not a claim that
M1010 is the only one HONOR builds. It is the only one anybody has reported.

| Source | `product_name` | `board_version` | BIOS |
|---|---|---|---|
| this machine, measured | `ZQC-P` | `M1010` | 1.10 |
| Wusanggg, [issue #10](../../../../issues/10) | `ZQC-P` | `M1010` | 1.09 |
| SamenVas | `ZQC-P` / `ZQC-P-PCB` | not stated | 1.09 |
| overbah98, [bugzilla 221787](https://bugzilla.kernel.org/show_bug.cgi?id=221787) | `ZQC-P` | not stated | not stated |

Two units, one revision. Compare [FMB-P](fmb-p.md#the-board-revisions), where
ten hardware probes turned up five: `M1010`, `M1020`, `M1030`, `M1070`, `M1090`,
all under one product name and all on the same BIOS. There is no reason to think
ZQC-P is different in kind; there is only less data.

The field is a list, so adding one costs nothing:

```
dmi_board_version=M1010 M1020
```

`cat /sys/class/dmi/id/board_version` on any ZQC-P settles it, and detection
only consults the field when two profiles would otherwise tie, so an unlisted
revision does not stop the machine being recognised today. It becomes load
bearing the moment HONOR ships two variants that need different values.

**There is still no ZQC-P hardware probe on linux-hardware.org**, which is where
FMB-P's five revisions came from. That remains the single highest-value thing an
owner of this machine can contribute.

## Other people with this machine

Independent reports, all of which agree on the root cause and the fix:

| Who | Where | What |
|---|---|---|
| SamenVas | [honor-magicbook-pro-zqc-p-linux-fix](https://github.com/SamenVas/honor-magicbook-pro-zqc-p-linux-fix) | BIOS 1.09. Same defect, a different one-line correction, and the speakers report below. Their `SSDT27.aml` is 23708 bytes, the same table as here on BIOS 1.10 |
| overbah98 | [kernel bugzilla 221787](https://bugzilla.kernel.org/show_bug.cgi?id=221787) | Ubuntu, kernel 7.0.0-28, filed 2026-07-25, with the exact `SSDT … I2C_DEVT` and `AE_AML_INTERNAL` lines |
| pilgrim1990 | issues #8 and #9 here | a Chinese variant, with the `lsusb` that confirms `3277:00de` and `1c7a:05aa`; and the cdclk garbling on CachyOS |
| Wusanggg | issue #10 here | Ubuntu 24.04 on BIOS 1.09, and the older-libfprint recipe below |
| inko32 | issues #3 and #4 here | the X7 358H, and the fingerprint region split |

**There is no ZQC-P hardware probe on linux-hardware.org.** Searching for
`ZQC-P`, `ZQC`, `M1010` and "MagicBook Pro" all return nothing, and the
`linuxhw` GitHub mirrors have 24 HONOR notebook directories and none of them is
this machine. Meanwhile a single BCC-N probe was enough to fill in that model's
entire inventory. Running `hw-probe` here is five minutes and would do more for
the next owner of this laptop than anything else on this page.

## The panel is driven at 6 bits per colour

Two separate things are wrong with how this panel is driven, and only one of
them has a fix here.

### The band that follows the pointer

A wide, faint, darker band crosses the whole screen and tracks the mouse
pointer as it moves up and down. It is PSR2 selective update: the hardware can
only refresh a *range of scanlines*, never a rectangle, so every partial update
is full width, and on this OLED the re-sent lines do not come out matching the
lines the panel is still driving from its own buffer.

Measured by switching PSR mode at run time through
`/sys/kernel/debug/dri/*/i915_edp_psr_debug`, in this order:

| psr_debug | mode | band | sink error latch |
|---|---|---|---|
| 1 | PSR disabled | no | n/a |
| 3 | PSR1 | no | `0x0` |
| 0 | PSR2 + selective fetch | **yes** | `0x1 PSR Link CRC error` |

PSR2 was restored last on purpose, and the band came back, which is what makes
this a cause rather than a coincidence. The fix is `xe.enable_psr=1`; the whole
trace, with the driver source it rests on, is in
[`patch/psr-band/README.md`](../../patch/psr-band/README.md).

The driver also logs, once per boot:

```
xe 0000:00:02.0: [drm] Selective fetch area calculation failed in pipe A
```

### 6 bpc with dithering, because DSC is off

The pipe runs at 18 bits per pixel, six per colour, with dithering on:

```
$ sudo cat /sys/kernel/debug/dri/0000:00:02.0/i915_display_info
	adjusted_mode="3120x2080": 120 900864 3120 3332 3336 3400 2080 2202 2203 2208
	pipe src=3120x2080+0+0, dither=yes, bpp=18
	port_clock=540000, lane_count=4
```

The ceiling is the link, not the panel: the EDID declares 10 bits per colour
and the platform would go to 12. Asked directly over the eDP AUX channel at
`/dev/drm_dp_aux0`, the panel offers two link rates and the faster is HBR2:

```
DPCD 0x000 DPCD_REV       0x14  ->  DP 1.4
DPCD 0x001 MAX_LINK_RATE  0x14  ->  5.4 Gbps
DPCD 0x002 MAX_LANE_COUNT 0x84  ->  4 lanes, enhanced framing, no TPS3
DPCD 0x010 eDP SUPPORTED_LINK_RATES, 16-bit LE, units of 200 kHz:
           13500 -> 2.70 Gbps        27000 -> 5.40 Gbps        (rest zero)
```

No HBR3, so 17.28 Gbit/s of payload is the hard ceiling and nothing reaches 8
bpc uncompressed at this pixel clock. Dropping to the 60 Hz mode does not help either: it
carries the same link load, measured rather than assumed, and the reason is
worked through in the fix's README.

The panel does support DSC and the firmware does not object. Why the driver
never asks, and the patch that makes it, are in
[`patch/edp-dsc/README.md`](../../patch/edp-dsc/README.md); it rebuilds
`xe.ko`, so `SKIP_DSC=1` is there if the build is unwelcome. Measured on this unit before and after, at the
120 Hz mode in use:

| | stock | with the fix |
|---|---|---|
| pipe bpp | 18, six per colour | **30, ten per colour** |
| dithering | yes | **no** |
| DSC | `DSC_Enabled: no` | `DSC_Enabled: yes`, `Force_DSC_Enable: no` |
| link rate required | 2026944 of 2160000 | 900864 of 2160000 |
| sink PSR error latch | `0x1 PSR Link CRC error` | `0x0` |

`Force_DSC_Enable: no` alongside `DSC_Enabled: yes` is the point: compression is
being chosen by the driver, not forced through debugfs.

Two things about this machine are still unknown. Suspend and resume with
compression live has not been tested here. And under DSC the PSR2 selective
update region has to align to the DSC slice height, 130 lines on this panel
instead of a handful, which would make [the band](#the-band-that-follows-the-pointer)
taller rather than smaller; moot while PSR is held at PSR1, which this machine
needs anyway.

## The keyboard and the Caps Lock LED

The embedded controller does not answer the `atkbd` command byte, so the
internal keyboard needed `i8042.dumbkbd=1`, which costs the Caps Lock LED.

**That is fixed upstream.** Commit
[`410c44b1096789d0c40fbee706520e981dba7bc1`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=410c44b1096789d0c40fbee706520e981dba7bc1),
"Input: atkbd - skip deactivate for HONOR ZQC-P", by Donglin Lyu, applied by
Dmitry Torokhov with `Tested-by: Ruslan Shevchenko <adefka@gmail.com>` and
`Cc: stable`. It is in **Linux 7.2**, verified absent from 7.1. The stable queue
holds `queue-7.1/input-atkbd-skip-deactivate-for-honor-zqc-p.patch`, added
2026-08-20, so **7.1.10** is the first 7.1.y with it — 7.1.9 does not have it.

On such a kernel: drop `i8042.dumbkbd=1` and the LED works. Below it, keep the
parameter, or build [`patch/keyboard-atkbd/`](../../patch/keyboard-atkbd/),
which is the same three lines.

> Patchwork still shows this patch as state "new" even though it has been in
> Linus's tree since 2026-08-02. The `linux-input` tracker is not kept in sync.
> Check git, not the tracker.

## The fans

RPM readout works two ways on this machine, and neither is fan *control*.

**EC RAM.** [`patch/fan/honor-ec-sensors.c`](../../patch/fan/) reads two 16-bit
little-endian tachometers at ECF0 `0x2C` and `0x2E`. Idle is roughly 2280 and
2000 RPM; both read 0 when the fans are genuinely off, which is most of the
time, because the EC does not engage them until around 72 °C.

**ACPI.** The DSDT declares a global `Method (GFNS, 1, Serialized)` that returns
`FA0L`/`FA0R` for fan 0 and `FA1L`/`FA1R` for fan 1, selected by a byte at offset
2 of the argument buffer. That is byte for byte the contract an accepted
upstream driver already implements for another HONOR machine, which is why
[`fmi-xx.md`](fmi-xx.md#why-this-machine-matters-to-a-magicbook-pro) is in this
directory at all. When that driver reaches mainline it should read this
machine's fans with no out-of-tree module, and `patch/fan/` becomes redundant;
its DMI gate will need a `ZQC-P` entry.

**Setting a speed: no.** `SFNS` is gated behind `MFGM`, which no AML path ever
sets; the DPTF fan participant `TFN1` accepts writes and does nothing; and
`F0PD`/`F1PD` are only ever read from AML. There is a documented ACPI route on
another HONOR machine —
[art14-fan-daemon](https://github.com/mark-herbert42/art14-fan-daemon) drives a
MagicBook Art 14 through `\_SB.PC00.LPCB.H_EC.WTER 0x20020C20 0x0a` for manual
mode and `0x20020A07`/`0x20020A08` for per-fan speed — but **`WTER` does not
exist in this machine's DSDT**, checked against
[`dump/win11/zqc-p/OEM/DSDT.dsl`](../../dump/win11/zqc-p/OEM/DSDT.dsl).

**Choosing the curve: yes.** The EC holds thirteen fan tables and `\IFCI`
selects between them by writing `FTSL` at ECF5 `0x30`. Stock is `0xA0`;
`0xAA` and `0xAB` engage the fans 6-20 °C earlier, which is the Windows-like
behaviour people ask for; and **`0xAC` stops the fans altogether**. Measured
here, twice, but the thresholds scattered enough between runs that nothing in
this repository sets it for you. The mechanism, the numbers, the warning and
the measurement to redo are in
[`patch/fan/README.md`](../../patch/fan/README.md#choosing-the-ecs-fan-curve-yes-and-it-is-not-shipped).

## The keyboard backlight is reachable

Implemented and physically verified on ZQC-P M1020/C170, BIOS 1.10 and Linux
7.2.2. Other ZQC-P revisions remain gated out until tested on their hardware.

It has been stated here that the backlight keys arrive but there is no LED
device to drive. The firmware says otherwise. This machine's DSDT declares an
8-bit EC field `KBBL` at offset `0x41` (followed by a 16-bit `KBTO` timeout),
and two methods around it:

* `\GKBM` reads `KBBL` and maps `0x02→0x03`, `0x03→0x04`, `0x04→0x02` into a
  return buffer
* `\SKBM` takes a level at offset 2 of its argument buffer and writes the
  inverse mapping into `KBBL`

So three levels, readable and writable, through a plain ACPI method. The WMI
dispatcher reaches the same thing at MFID `0x06` / SFID `0x13` and `0x14`
([`dump/win11/zqc-p/OEM/SSDT21.dsl`](../../dump/win11/zqc-p/OEM/SSDT21.dsl)).
`drphilth`'s FMB-P packages already ship a keyboard-backlight EC driver on the
same principle.

Two more things make this an easy job rather than a research project.

`huawei-wmi` already creates the LED on this machine and cannot drive it. From a
boot log in [issue #6](../../../../issues/6):

```
leds huawei::kbd_backlight: Setting an LED's brightness failed (-19)
```

`-ENODEV`, every time. The device node is there, the write goes nowhere.

And the driver has effectively been written. drphilth's
[`honor-fmbp-kbdlight`](https://github.com/drphilth/honor-magicbook-pro-14-ubuntu/blob/main/honor-fmbp/src/honor-fmbp-kbdlight/honor-fmbp-kbdlight.c)
is a GPL `leds-class` module for the sibling FMB-P that does exactly this:
`ec_write(0x41, …)` with `0x04` off, `0x02` low, `0x03` high, and `0x01` to
latch the level so it stops timing out. That is the same mapping `\SKBM`
implements here, arrived at independently. What it would need is a DMI entry
for this machine and somebody willing to test it.

The M1020 overlay now uses those firmware methods rather than raw EC writes.
The physical key emitted `0x2b1`, `0x2b2`, `0x2b3` for off, low and high.
`GKBM/SKBM` read and physically applied all three levels. An attempted `SKBM`
value of 25 returned status `0x01` and left the mode unchanged, confirming that
there are only two nonzero hardware levels, exposed to KDE as 50% and 100%.
`GKBT` reported the stock 15-second timeout; setting `SKBT` to 5 read back as 5
and physically switched the light off after about five seconds, after which 15
was restored.

The driver registers `/sys/class/leds/platform::kbd_backlight` with levels
0/1/2 and hardware-change notification. After restarting UPower and PowerDevil,
KDE showed the native keyboard OSD at 0%, 50% and 100%. systemd attached its
standard backlight save/restore service, and the selected level was physically
confirmed to survive a reboot. The installer accepts
`KBDLIGHT_TIMEOUT=<0..65535>`, default 15; zero disables the timeout. A custom
value is persisted in `/etc/modprobe.d/61-honor-keyboard-backlight.conf`.
Touchpad activity cannot safely rearm a timed-out backlight: `SKBM` changes the
level but does not restart the timer, and `SKBL` is a firmware stub. The known
raw EC `0x01` latch from a sibling model is not used. The selected level was
physically confirmed to survive suspend/resume as well as a full reboot.

## The speakers disagreement

SamenVas reports that on their BIOS 1.09 unit **the speakers and the internal
microphone die with the same table failure**, which is not what happens here on
BIOS 1.10, where the codec is on HDA and unaffected.

Their README names the mechanism, and it is plausible: the Realtek **ALC1308**
amplifier is declared as ACPI `10EC1308` at `\_SB.PC00.I2C3.HDC1` — inside the
same `I2C_DEVT` table. On a unit where the amplifier is wired that way, the
table rolling back takes the speakers with it. On this unit it does not.

Either a BIOS difference or a hardware revision. Still unresolved, but it is no
longer "unexplained": if your speakers are silent *and* your touchpad is
missing, the ACPI override is likely to fix both.

For contrast: on [XWC-P](xwc-p.md#audio-is-unaffected-by-the-table-failure) the
same table fails and audio is entirely unaffected.

## Two installation traps

**Kernel lockdown may or may not defeat the ACPI override, and it is worth
checking rather than assuming.** Mainline `acpi_table_initrd_init()` does carry
`security_locked_down(LOCKDOWN_ACPI_TABLES)` and logs `kernel is locked down,
ignoring table override` when it fires, and that is the reported experience on
at least one ZQC-P. But a BCC-N on Fedora 44 and kernel 7.1.5, booting with
Secure Boot on and `Kernel is locked down from EFI Secure Boot mode` in its log,
applied a HONOR `I2C_DEVT` override anyway (linux-hardware probe c33ebd2b1c).
Both cannot be predicted from the outside, so `apply_patch.sh` notes the state
and names the two log lines to look for afterwards instead of refusing.

**The backlight PWM figure.** [LIMITATIONS.md](../LIMITATIONS.md) records
200 Hz, derived from `BXT_BLC_PWM_FREQ` as the BIOS programmed it.
Notebookcheck's instrumented review of the same panel reports 120 Hz worst case
with flicker detected at and below 85% brightness. These are probably measuring
different things — a programmed PWM period against an observed optical
modulation, which on an OLED includes the panel's own duty behaviour — but both
numbers are in circulation and only one of them is ours.

## The fingerprint patch on older libfprint

Wusanggg (issue #10) ran Ubuntu 24.04 with `libfprint 1.94.7+tod1`, where
[`patch/fingerprint/`](../../patch/fingerprint/)'s patch does not apply: that
`goodix.c` has no `0x6984` line for it to anchor on. Their working substitute is
to add `case 0x6F94:` to the `max_enroll_stage = 12` group and
`{ .vid = 0x27c6, .pid = 0x6F94 }` to the id table by hand.

`27c6:6f94` has **never been submitted upstream** — no merge request, no issue.
`goodixmoc`'s id table on master ends at `0x6984`. The Chinese variant's
`1c7a:05aa` is not in `egismoc.c` either, and its
[issue #776](https://gitlab.freedesktop.org/libfprint/libfprint/-/issues/776)
has been open since March 2026 with no answer. Both need a local patch on every
distribution until somebody sends them.

There is also independent reverse-engineering of this exact reader:
[andreas-fe/goodix-27c6-6f94-linux-driver](https://github.com/andreas-fe/goodix-27c6-6f94-linux-driver)
identifies it as a Goodix GF3268 SDCP sensor speaking TLS 1.2 PSK, and reports
that verify, identify, list and delete work through a purpose-written driver
while enrolment does not. That contradicts what the `goodixmoc` id-table patch
achieves here, where enrolment works. Different code paths; worth knowing before
anybody concludes the sensor cannot enrol.

## libinput has a quirk for this touchpad, gated to another machine

`libinput` ships
[`quirks/50-system-honor.quirks`](https://gitlab.freedesktop.org/libinput/libinput/-/raw/main/quirks/50-system-honor.quirks)
with a single stanza, `[HONOR MagicBook Art 14]`, matching
`MatchName=*TOPS0102*`, `MatchDMIModalias=dmi:*:svnHONOR:pnMRA-XXX:*` and
`MatchUdevType=touchpad`, applying `AttrEventCode=-BTN_RIGHT` and
`AttrInputProp=+INPUT_PROP_PRESSUREPAD`.

This machine's touchpad has the same `TOPS0102` ACPI name, so only the DMI
clause keeps the quirk away. Whether ZQC-P wants it is a separate question —
it describes a clickpad that wrongly announces `BTN_RIGHT` — and nobody has
reported that symptom here. Recorded because the next person to grep libinput
for HONOR will find it and wonder.

## The M1020 revision

A global unit reports the same product and board names as M1010 but a different
board revision and SKU. It was first measured on BIOS 1.09 with Kubuntu, then
verified again after the BIOS 1.10 update and clean CachyOS installation:

| | `M1020` measurement |
|---|---|
| DMI | `HONOR / ZQC-P / ZQC-P-PCB`, board `M1020`, SKU `C170` |
| CPU / GPU | Core Ultra X9 388H / Arc B390 `8086:b080`, `xe` |
| BIOS tested | 1.10, 2026-06-03 |
| OS tested | CachyOS, `linux-cachyos 7.2.2-1` with `linux-cachyos-lts 6.18.48-1` retained as fallback |
| Touchscreen | FocalTech `2808:5662` |
| Touchpad | Goodix `27c6:0f9a` |
| Fingerprint | Goodix `27c6:6f94` |
| Webcam | Luxvisions `30c9:012c`, unlike M1010/M1050 `3277:00de` |
| Audio | ALC256, subsystem `1ee7:209d` |
| Battery | NVT `HB7075R5EHW-41T1` |
| SSD in the unit seen | KIOXIA `KBG60ZNV1T02` |
| Status | verified for the board-specific subset in the profile |

The stock live `I2C_DEVT` table remained 23,708 bytes with MD5
`27bb4879b5af49ac2b613a73cf1ffa0b` after the BIOS 1.10 update, exactly the
table the M1010 override was built from. The installer accepted it through the table hash gate rather than
through the board name. After reboot the kernel logged:

```text
ACPI: Table Upgrade: override [SSDT- HONOR-I2C_DEVT]
```

`TOPS0102:00` and `FTSC1000:00` appeared, and the internal keyboard, touchpad
and touchscreen worked. This is the evidence behind the M1020
`acpi-override` recipe; after a BIOS update the live table must be hashed again
before reusing it.

The 243,659-byte DSDT had SHA-256
`a73e83433f2500702d7da50947a49267fccd5d1de0cab86cd87c4232da7bc075`, byte
for byte the same as the M1010 DSDT in this repository. In particular it places
`FA0L/FA0R` at EC offsets `0x2c/0x2d` and `FA1L/FA1R` at `0x2e/0x2f`. The
read-only fan module was installed with those offsets and reported two
plausible RPM values, approximately 2300 and 2000 during the check.

The two HID-BPF fixes were also physically verified. Removing the FTSC1000
vendor collection eliminated the phantom `KEY_MICMUTE` input without affecting
touch, and the TOPS0102 program made the left-edge brightness gesture work.
The right-edge volume gesture remained unchanged.

A hotkey capture recorded WMI `0x288` for the camera toggle, `0x2a3` for
touchpad-off, and the companion atkbd `f8` scancode. The patched `huawei-wmi`
and board-specific hwdb removed the unknown-key reports. The action service
was pointed at this unit's actual `30c9:012c` camera; F8 deauthorised and
reauthorised only that USB device. Native Plasma OSD was added for both camera
states, with `POWER_PROFILE_KEY=0` retained.

Stock `linux-cachyos 7.2.2-1` produced a garbled display during boot and logged
`*ERROR* CPU pipe A FIFO underrun`. Rebuilding only `xe.ko` from the exact
CachyOS release tree with `cdclk-ptl` removed the underrun and the machine then
booted cleanly. The LTS kernel remains an unmodified fallback.

The Goodix `27c6:6f94` reader reported no devices with stock libfprint
`1.94.100-1.1`. A pacman-owned `1.94.100-1.2` package carrying the two-line
Goodix MOC ID patch enrolled `right-index-finger`, returned `verify-match`, and
authenticated `sudo`. Password authentication remains as fallback.

The battery limit was later brought up on this board, on BIOS 1.10 and
`linux-cachyos 7.2.2-1`. Out of the box, writing `70 90` through `huawei-wmi`
left EC charge mode `0` on both BIOS 1.09 and 1.10, and `GBCM` (WMI `0x1603`)
read back `mode 0x00, 0x86 = 0x48, start 75, stop 90`, the pair the desktop
had written. One `\SBCM` call (WMI `0x1503`, payload `0x5a4648021503`) set
mode `2`; a second, `0x462848011503`, set mode `1`. With `40 70` armed and the
pack at 65% on the adapter, it charged at about 2.1 A to exactly 70% and
stopped: `status` `Not charging`, `current_now` 0, held for several minutes.
After that first `\SBCM`, plain sysfs writes behaved like the M1010: `75 90`
gave mode 0, `0 100` gave mode 0, `70 90` gave mode 2, immediately and not
after a delay. The state survived a reboot: the EC came up with `70 90 / mode
2`, and `0 100` then `70 90` through sysfs disarmed and re-armed it without
`\SBCM`. `patch/battery/` gained the `\SBCM` fallback and an M1020 recipe on
the strength of this, and `battery` was added to the board's fix list. Whether
the latch survives a full power-off with the adapter removed is not yet
measured; the fallback makes that immaterial for the fix.

The following results are deliberately not promoted into the M1020 fix list:
- **Headset microphone:** an out-of-tree `snd-hda-codec-alc269` built from
  vanilla v7.0 source crashed Ubuntu's backported HDA stack in
  `try_assign_dacs()` during boot. The overlay and temporary M1020 recipe were
  removed. Matching codec IDs are not enough to make that mixed-source module
  safe.
- **Other display patches:** no PSR band or low-brightness OLED defect was
  reported, so `psr-band`, `oled-backlight` and `edp-dsc` remain disabled.

The verified CachyOS results and the earlier Kubuntu kernel Oops are preserved
in this M1020 section.

## The M1050 revision

`ZQC-P` is not one machine. A second board revision reports the same
`sys_vendor` and the same `product_name`, and until August 2026 that was nearly
all anybody here knew about it. It now has a hardware dump and a full set of
ACPI tables, both taken on the machine itself, so most of this section is a
measurement rather than an inference.

| | `M1010`, this unit | `M1050` |
|---|---|---|
| CPU | Core Ultra X9 388H, 16 logical CPUs | Core Ultra 5 338H, 12 logical CPUs |
| iGPU | Arc B390, PCI `8086:b080` | Arc B370, PCI `8086:b081` |
| Host bridge | PCI `8086:b001` | PCI `8086:b004` (PTL-H444) |
| BIOS seen | 1.10 (2026-06-03) | 1.10 (2026-06-03) |
| Panel | EDO 14.55" OLED, 3120x2080 at 120 Hz | the same, and the same VBT byte for byte |
| Backlight | `intel_backlight`, `max_brightness` 704 | the same |
| Audio codec | ALC256, subsystem `1ee7:209d` | the same |
| Touchscreen | FocalTech `2808:5662` | the same |
| Touchpad | Goodix `27c6:0f9a` | the same |
| Fingerprint | Goodix `27c6:6f94` | LighTuning EgisTec `1c7a:05aa` |
| Webcam | Shinetech `3277:00de` | the same |
| SSD in the unit seen | YMTC PC411 `1e49:1071` | KIOXIA BG6 `1e0f:001a` |
| Status | verified | verified |

Sources, all from @pilgrim1990:
[issue 1](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/1)
(the first `/proc/bus/input/devices` listing),
[issue 8](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/8)
(the board revision, the CPU and the fingerprint reader),
[issue 9](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/9)
(boot-time screen corruption) and
[issue 11](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/11)
(`collect-hwinfo` archive, `dump-acpi` tables and a full `apply_patch.sh` log).

The SSD is in the table to be discounted: it is a build option, not a property
of the board, and nothing in this repository looks at it.

### What the dump settled: it is the same firmware

The two machines were expected to differ in more than the CPU. They do not. The
ACPI tables from `M1050` were compared against the `M1010` set in
[`dump/win11/zqc-p/OEM/`](../../dump/win11/zqc-p/OEM/), matched by OEM table id
rather than by file number, because `acpidump` and the Windows-side dump number
them differently.

* **DSDT: 243659 bytes, and 11 of them differ.** One is the header checksum.
  The other ten are runtime base addresses the firmware stamps in at boot: the
  `GNVS`, `OGNS` and `MDBG` operation regions and the `TCNB`, `IPNB`, `IGNB`,
  `HBNB`, `VMNB`, `TSNB` and `PNVB` name constants. Disassembled and diffed, the
  eleven differing lines are all of that shape, and no operator, method or field
  declaration differs anywhere. Every method this repository touches, `IFCI`,
  `GFCI`, `SBCM`, `GBCM`, `SFNS`, is the same code.
* **Of his 30 SSDTs, 17 are byte-identical** and 10 more differ only in the
  checksum and the same kind of address stamp. `WmiTable`, which carries the
  hotkey dispatcher, is in the second group: its one difference is
  `OperationRegion (HNVS, SystemMemory, ...)` pointing 0x20000 higher. Of the
  remaining three, `Cpu0Ist` is the CPU (below), `I2C_DEVT` is his copy of our
  override rather than his firmware's table, and `Cnv_Ssdt` has no counterpart
  because the `M1010` set was dumped from Windows and does not contain it.
* **What genuinely differs is the CPU.** `Cpu0Ist` carries a different P-state
  table (top state 0x0FA1 against 0x0E75, 4001 MHz against 3701 MHz), and `APIC`
  lists 16 processor entries against 12.
* **The panel VBT is byte-identical.** His 7680-byte VBT differs from the
  factory blob saved on this machine at exactly two offsets, 3772 and 3957,
  which are the two bytes `patch/oled-backlight/` writes, and both his read 6
  before it wrote 12. The rest matches: version 266, panel type 2, DDI native
  PWM at 200 Hz, 8 precision bits, default level 35/255. Same panel, same
  backlight controller.

So the EC field map is not an assumption on this board. The `ec_fan0=0x2c` and
`ec_fan1=0x2e` in [`patch/fan/zqc-p/M1050/`](../../patch/fan/zqc-p/M1050/) are
read straight out of his own DSDT, where `Offset (0x2C)` is
followed by `FA0L`, `FA0R`, `FA1L`, `FA1R`, and `Offset (0x85)` by `CHMD`, which
is the charge-mode byte `patch/battery/` checks.

`I2C_DEVT` could not be compared. The dump was taken with the ACPI override
already installed, so what came back is this repository's patched table rather
than his firmware's, which `dump-acpi.sh` said at the time and `MACHINE.txt`
records. It is not needed: `patch/acpi-override/` decides from the md5 of the
live table and refuses on a mismatch, and his install log shows it recognising
the override it had already placed.

### What the `verified` on this section rests on

Firmware being identical is not the same as a fix having been run and watched.
Both things are true here, and they are not equally true of all fifteen fixes,
so this is worth setting out plainly rather than behind one word.

**Its owner had already been running the whole set.** Before boards were split,
`ZQC-P` was one flat profile and everything in it was applied to this machine
too. The install log in
[issue 11](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/11)
is that run, and nothing in it was reported as having gone wrong.

That log is also the reason the evidence is uneven. Five of the eighteen steps
failed in it, on the upstream tag bug described [below](#what-was-fixed-because-of-this-report),
so those fixes have never actually installed on this machine.

| Fix | What it rests on here |
|---|---|
| `acpi-override` | ran; the log shows it recognising the patched table as already active, and the md5 check settles it at run time regardless |
| `psr-band` | ran; this board's own eDP reports `PSR mode: PSR1 enabled` afterwards |
| `oled-backlight` | ran; patched this machine's own factory VBT from 6/255 to 12/255 and installed the blob. Nobody has stepped through `measure-floor.sh` on this panel, so 12 is inherited rather than measured, on a panel proven byte-identical |
| `cdclk-ptl` | was opt-in at the time, so the log skipped it. The defect it fixes is [issue 9](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/9), which is this owner's |
| `edp-dsc` | was opt-in at the time, so the log skipped it. The 6 bpc arithmetic is confirmed from this board's own eDP debugfs |
| `headset-mic` | **never installed here**: the fetch 404ed. Same ALC256, same `1ee7:209d`, same empty `inputs:` in this machine's own codec autoconfig, and the installer re-checks the subsystem id at run time |
| `sof-audio` | **never installed here**: the fetch 404ed. It carries nothing measured on any machine; it is a backport against the running kernel |
| `micmute` | worked here in an earlier release, and its owner is the one who noticed when it regressed. Failed in this log for the same 404 |
| `touchpad-edge` | **never installed here**: the fetch 404ed. Same Goodix touchpad with all three collections in this machine's own listing |
| `fan` | ran, and reported OK. Its offsets are read from this board's own DSDT, not copied. The module also refuses to register if the EC does not answer plausibly |
| `fingerprint` | ran; the log shows the SDCP branch built and the library listing `1c7a:05aa`. Whether enrolment works has not been reported |
| `battery` | ran, and reported OK. Which pairs this EC arms is decided in EC firmware and is not visible in the ACPI tables, so the pairs are still inherited from `M1010` |
| `hotkeys` | **never installed here**: the fetch 404ed. `WmiTable` is byte-identical firmware, so the seven codes are very probably the same, but they have not been captured on this machine |
| `hotkey-actions` | ran; the log shows it reporting both the performance key and the camera key |
| `auto-rebuild` | ran |

Three fixes have therefore never run on this board, and one constant, the
backlight floor, is inherited rather than measured. `verified` here is a
maintainer's judgement that the firmware evidence plus a clean run of the rest
is enough, not a claim that every one of the fifteen was watched working. The
things that would remove the remaining doubt are small and all belong to
whoever has the machine:

* `patch/hotkeys/capture-keys.sh`, to replace "probably the same codes" with the
  codes.
* write a pair to `charge_control_thresholds` and read EC `0x85`: nonzero means
  that EC armed itself, which is the only way to establish the preset list. The
  hardware dump now records `0x85`, so a dump taken with a limit set shows which
  preset is active, but not which others would be accepted.
* `patch/oled-backlight/measure-floor.sh`, to say where the tint actually stops
  on this panel.

### What was fixed because of this report

All of it applies to every board, not just this one.

**Five fixes failed on one wrong string.** His kernel is `7.2.0-1-cachyos`, and
five installers each built their own upstream tag as `v${KVER%%-*}`, giving
`v7.2.0`. Mainline tags the first release of a series without the trailing zero,
so the tag is `v7.2` and every one of those fetches returned 404. `micmute`,
`touchpad-edge`, `headset-mic`, `sof-audio` and `hotkeys` all failed in the same
run, each reporting its own unrelated-looking error, which is why the
self-toggling microphone came back. This is what took the fix off a machine it
had been working on. The tag is now resolved once, in
[`lib/ksrc.sh`](../../lib/ksrc.sh), and it is confirmed rather than guessed: the
candidate is accepted only if the `Makefile` at that tag names the release being
run. Two of the five use the tree to decide whether to skip themselves, and a
tag silently pointing at a newer tree would make them skip a fix the kernel
still needs.

**The EDID section was empty in every dump ever collected.** The collector
tested `[[ -s $edid ]]` before reading, and a sysfs binary attribute reports a
size of zero whether or not it has anything to give. Every connector was skipped
on every machine, this one included. It reads the file now, which is the only
way to know, and the panel's identity arrives with each report: re-run here, it
produced a hundred lines that had never been collected before, down to the
`Display Product Name`.

**The fingerprint reader was not recognised on a machine that has one.** The
collector matched vendor names against `goodix|elan|synaptics|fingerprint|
validity`, and his reader announces itself as `LighTuning Technology Inc.
Egistec-ETU906Axx`, so the summary said "no obvious reader in lsusb". It now
matches ids from the recipes under `patch/fingerprint/`, so a reader
this repository already supports is named by the file that supports it, and
falls back to the vendor ids that make these sensors rather than to how a
marketing department spelled itself in a descriptor.

**The EC page is now collected.** See above.

**A Bluetooth mouse was offered as a touchpad.** The HID candidate list printed
bare ids and told the reader to go and cross-reference the input section by
hand. His `339b:4702` is a HONOR mouse paired over Bluetooth and sat in that
list looking exactly like a built-in device. Each candidate now carries its bus
and the kernel's own names for it.

**`Battery charge limit (EC preset)` reported `OK` and then nothing.** The line
that was meant to print the pair carried a single-quote escape that is correct
inside a `sed` expression and is not correct inside a double-quoted `echo`.
There it fell apart into a pattern made of its own quote characters plus a
second file argument that does not exist, so `grep` matched nothing and its
error went to `/dev/null`. It had never worked. `tools/selftest.sh` now refuses
that escape inside double quotes anywhere in the tree.

Earlier, and separately: the boot-time re-apply service for `micmute` was
pointing at a directory a rename had removed, so it failed at every boot and the
phantom `KEY_MICMUTE` device came back. The symptom was reported returning on
`M1050` and then reproduced on `M1010`. The installer now starts the unit and
fails loudly if it cannot, and `tools/selftest.sh` checks that every unit in
this repository runs a file its own installer puts there.
