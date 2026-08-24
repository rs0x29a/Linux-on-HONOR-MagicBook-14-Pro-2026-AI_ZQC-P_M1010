# ZQC-P — MagicBook Pro 14 2026 (AI)

| | |
|---|---|
| Product code | `ZQC-P`, DMI version `M1010`, board `ZQC-P-PCB` |
| Platform | Intel Panther Lake, Core Ultra X9 388H |
| Profile | [`devices/zqc-p.conf`](../../devices/zqc-p.conf) — **verified** |
| Verified on | BIOS 1.10, CachyOS, kernel 7.1.8 |

This is the machine the repository was built on: every value in its profile was
read off this unit and every fix was run on it. Where a statement below is not
a measurement taken here, it says whose it is.

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

Understood, measured, and not fixed. The pipe runs at 18 bits per pixel, six
per colour, with dithering on:

```
$ sudo cat /sys/kernel/debug/dri/0000:00:02.0/i915_display_info
	adjusted_mode="3120x2080": 120 900864 3120 3332 3336 3400 2080 2202 2203 2208
	pipe src=3120x2080+0+0, dither=yes, bpp=18
	port_clock=540000, lane_count=4
```

The driver says why itself, with `drm.debug=0x04` set across a modeset:

```
[CONNECTOR:512:eDP-1] Limiting target display pipe bpp to 30
    (EDID bpp 30, max requested bpp 36, max platform bpp 36)
[ENCODER:511:DDI A/PHY A][CRTC:151:pipe A] DP link limits: pixel clock 900864 kHz
    DSC off max lanes 4 max rate 540000 max pipe_bpp 30
    min link_bpp 18.0000 max link_bpp 30.0000
DP lane count 4 clock 540000 bpp input 18 compressed 0.0000 HDR no
    link rate required 2026944 available 2160000
[CRTC:151:pipe A] hw max bpp: 30, pipe bpp: 18, dithering: 1
```

The panel declares 10 bits per colour in its EDID and the platform would go to
12, so the ceiling is not the panel. It is the link: 2026944 of the 2160000
available is what 18 bpp costs, and 24 bpp would cost 2702592. There is no
`Try DSC` line anywhere in that log, because the driver never gets that far.
Compression is only considered when the uncompressed path fails:

```c
	dsc_needed = joiner_needs_dsc || intel_dp->force_dsc_en ||
		     !intel_dp_compute_config_limits(...);

	if (!dsc_needed) {
		ret = intel_dp_compute_link_config_wide(...);
		...
		if (ret || !intel_dp_dotclk_valid(...))
			dsc_needed = true;
	}
```

and the uncompressed path does not fail, because `intel_dp_min_bpp()` lets it
go down to 6 bpc for RGB. Dropping colour depth to make a mode fit is
deliberate, and old: it arrived as
[Dither down to 6bpc if it makes the mode fit](https://patchwork.kernel.org/project/intel-gfx/patch/1311174531-23070-1-git-send-email-ajax@redhat.com/)
in 2011, when the alternative was no picture at all. On a panel that also
supports DSC the alternative is no longer that.

#### There is no faster link to be had

The panel was asked directly over `/dev/drm_dp_aux0`, which is the eDP AUX
channel for this connector:

```
DPCD 0x000 DPCD_REV       0x14  ->  DP 1.4
DPCD 0x001 MAX_LINK_RATE  0x14  ->  5.4 Gbps
DPCD 0x002 MAX_LANE_COUNT 0x84  ->  4 lanes, enhanced framing, no TPS3
DPCD 0x010 eDP SUPPORTED_LINK_RATES, 16-bit LE, units of 200 kHz:
           13500 -> 2.70 Gbps        27000 -> 5.40 Gbps        (rest zero)
```

Two rates, and the higher one is HBR2. There is no HBR3 on this panel, so
17.28 Gbit/s of payload is the hard ceiling and no configuration reaches 8 bpc
uncompressed at this pixel clock.

The 60 Hz mode does not help either, which is worth writing down because it
looks like it should. It is the same pixel clock with the vertical blanking
doubled, `vtotal` 2208 becomes 4416 and `clock` stays 900864, so the link
carries exactly the same load and the pipe stays at 18 bpp. Measured, not
assumed.

#### DSC works on this panel

Forced on through `i915_dsc_fec_support` and committed with a real modeset, at
the 120 Hz mode that is actually in use:

| | stock | DSC forced |
|---|---|---|
| pipe bpp | 18 (6 bpc) | **30 (10 bpc)** |
| dithering | yes | **no** |
| link rate required | 2026944 of 2160000 | **900864 of 2160000** |

```
DP DSC computed with Input Bpp = 30 Compressed Bpp = 8.0000 Slice Count = 4
```

4 slices of 780x130, block prediction on, line buffer 11 bits, RGB. The link
was then read back from the panel while compression was live:

```
DPCD 0x202/0x203 LANE0..3   CR=1 EQ=1 SYM_LOCK=1 on all four lanes
DPCD 0x204                  INTERLANE_ALIGN_DONE=1
DPCD 0x210..0x216           SYMBOL_ERROR_COUNT = 0 on all four lanes
Sink PSR error status       0x0
```

and the picture was checked by eye: no artefacts, no flicker, correct colours.

The firmware does not object either. `edp_dsc_disable` in VBT block 27
(`BDB_EDP`) reads `0x0000`, and in fact every byte of that region of the block
is zero, so no panel type is excluded:

```
block 40 (BDB_LFP_OPTIONS): panel_type = 2
block 27 (BDB_EDP), offsets 740..848: all zero
edp_dsc_disable = 0x0000
```

So all three parties agree DSC is available and it demonstrably works. The
driver simply never asks, because 6 bpc satisfied it first.

#### The fix, and what it produces

Measured on the reference unit after the change, at the 120 Hz mode in use:

| | stock | shipped |
|---|---|---|
| pipe bpp | 18, six per colour | **30, ten per colour** |
| dithering | yes | **no** |
| DSC | `DSC_Enabled: no` | `DSC_Enabled: yes`, `Force_DSC_Enable: no` |
| link rate required | 2026944 of 2160000 | 900864 of 2160000 |
| sink PSR error latch | `0x1 PSR Link CRC error` | `0x0` |

`Force_DSC_Enable: no` alongside `DSC_Enabled: yes` is the point: compression is
being chosen by the driver, not forced through debugfs. The panel's own link
status agrees, read back over AUX: clock recovery, equalisation and symbol lock
on all four lanes, interlane alignment done, and zero symbol errors.

`Force_DSC_Enable` lives in debugfs and nowhere else, and there is no module
parameter for it, so making this stick means changing the driver.
[`patch/edp-dsc/`](../../patch/edp-dsc/) carries a patch that, on eDP, prefers
compression over settling below 8 bits per colour, and puts the uncompressed
result back if the DSC pass fails so it can never turn a working mode into a
rejected one. It is opt-in, because it rebuilds `xe.ko`.

That module is shared with [`patch/cdclk-ptl/`](../../patch/cdclk-ptl/), so
both patches are built together by
[`lib/xe-build.sh`](../../lib/xe-build.sh) and neither installer can silently
drop the other's change. What went into the installed module is recorded in
`/var/lib/honor/xe-module.stamp`.

One detail took a second attempt to get right and is worth knowing if anybody
rebases this. `intel_dp_compute_config_limits()` derives the DSC input depth
from `crtc_state->pipe_bpp`, which by then holds whatever the uncompressed
search settled for. Handing that back produced 8 bits per colour instead of 10,
because 18 clamps up to the DSC minimum of 24 and stops. The patch restores the
depth the modeset arrived with before computing the DSC limits.

Two things are still unknown and are worth knowing before relying on it.
Suspend and resume with compression live has not been tested. And under DSC the
PSR2 selective update region has to align to the DSC slice height rather than
the panel's own granularity, 130 lines here instead of a handful, which would
make [the band](#the-panel-is-driven-at-6-bits-per-colour) taller rather than
smaller; that is moot while PSR is held at PSR1, which this machine needs
anyway.

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
2 of the argument buffer. That is exactly the interface of
[patch 14751797](https://patchwork.kernel.org/project/linux-hwmon/patch/20260815234041.2262291-1-testname142@gmail.com/),
"hwmon: Add fan monitoring support for HONOR FMI-XX" by Nikita Dubrovskih,
**accepted on linux-hwmon** 2026-08-15. When that driver reaches mainline it
should read this machine's fans without any out-of-tree module, and
`patch/fan/` becomes redundant. Its DMI gate will need a `ZQC-P` entry.

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

Recorded as an open opportunity, not as something that works today.

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

The repository now contains an **experimental, opt-in** DMI-gated driver in
[`patch/keyboard-backlight/`](../../patch/keyboard-backlight/). It must be
tested on a real ZQC-P before its status can be upgraded from experimental.

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
