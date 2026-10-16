# MRA-XXX touchpad: the "Gesture To Go" vendor layer, mapped

Measured 2026-10-09 on the machine itself (BIOS 3.05). Everything below is
read-only: live `evtest` captures of all four touchpad i2c-HID event nodes,
a raw `hexdump` capture of `/dev/hidraw1`, the parsed HID report descriptor
from `/sys/kernel/debug/hid/0018:35CC:0104.0002/rdesc`, and web/community
research. Nothing was written to the touchpad firmware.

## Hardware

The touchpad is `TOPS0102:00` (HID `35CC:0104`, i2c-designware.1) with **four
HID collections / four event nodes**:

| Node | Collection | What it does |
|---|---|---|
| event9 (`…-touchpad`) | TouchPad digitizer | multitouch (13 simultaneous tracking IDs), `ABS_PRESSURE` 0–536, `BTN_LEFT`; physical clicks show ~124 pressure |
| event8 (`…-consumer-control`) | Consumer Control | huge declared media-key bitmap; **stays silent** — no edge gesture ever surfaces here |
| — (`…-gesture-control`) | **Gesture Control** | **does not exist on this machine** — the Windows synthetic-key layer (`KEY_VOLUMEUP`, `KEY_BRIGHTNESSUP`, Super+H …) is firmware-disabled here; on machines where it is enabled it appears as its own node (see the MadhiasM evtest listing) |
| — (`…-unknown`, event7 slot) | FTSC1000 | the touchscreen's keyboard side-node; see `mra-xxx.md` |

## What the "extra keypresses" actually are

Windows PC Manager on this model exposes Honor's **Gesture To Go** set
(Honor's own support/marketing pages, and the community replication):

- vertical swipe on the **left edge = brightness**, on the **right edge =
  volume**
- two-finger swipe leftwards from the right edge = notification panel
- click on top-left / top-right of the pad = minimize / close window
- one-knuckle double-knock = screenshot menu; two-knuckle = instant screenshot
- three-finger drag = drag & drop (works without the service, "can have
  weird side effects, hence recommended to disable" — community note)

The firmware runs its own edge detection + a haptic actuator **on the MCU,
regardless of OS and of the gesture enable state**: on this machine, with the
gestures firmware-disabled, slow edge swipes still produce **felt vibration**
and *zero input-layer events* (verified: 60 s capture, six edge swipes, no
`KEY_*`, Consumer Control silent). Linux has **no FF (force feedback)
capability exposed anywhere** for it, and no haptic mention in the DSDT —
the actuator is reachable only through the vendor report protocol below.

## The vendor command protocol (raw hidraw capture)

`hexdump -C /dev/hidraw1` during edge contact shows a structured
**40-byte `04 03 …` vendor envelope** (report ID `0x04`, then a 2-byte
command, 2-byte subcommand, payload, trailing LE32 counter) — a command
blizzard during edge swipes only, a completely separate lane from the
digitizer HID reports. Command families seen: `30 09` (×1116), `b2 0a`
(×923), `d4 08` (×403), `c3 08` (×303), `91 09` (×270), `89 09` (×196), and
462 distinct rare signatures. The report descriptor confirms the writable
side:

- `OUTPUT(14)` — 256-byte vendor command buffer (`ff00.0000…`) — the write
  door into the same protocol
- `INPUT(14)` — matching 256-byte vendor response buffer
- `FEATURE(6)` — another 256× `ff00.00c5` buffer
- standard PTP extras: `LatencyMode` (FEATURE 7), `DeviceMode` (FEATURE 3,
  modes 0–10), `SurfaceSwitch`/`ButtonSwitch` (FEATURE 5)

So the edge-gesture/haptics logic lives in a vendor protocol no Linux driver
reads, and the touchpad's *pressure digitizer* (`0–536` per contact) is
similarly unused — Hyprland/libinput treat touchpads as binary.

## Is the feature liked?

No survey data exists, but the evidence splits:

- Two independent devs reverse-engineered it to **keep** it on Linux —
  `MadhiasM/honor-magicbook-art-touchpad-gestures` (maps the synthetic keys
  to native actions; warns about the minimize gesture typing "h" into the
  focused app) and `ZachAR3/HonorControl` (July 2026: enable/disable
  **entirely on Linux, no Windows needed**; alpha; GPL-3.0; battery
  thresholds, power profiles, fan curves, touchpad firmware settings;
  *built and tested on this exact model*, Ultra 5 125H — hardware writes
  gated on exact DMI match `HONOR`/`MRA-XXX`).
- Against: edge gestures misfire on other laptops' users (r/ASUS threads on
  disabling "Smart Gestures"; Microsoft Q&A: right-edge swipe "launches
  Edge, extremely annoying, happens each minute"), and Honor's own KB exists
  for "touchpad vibration too strong/weak". IT Pro on the 2025 Pro 14: the
  "haptic trackpad sounds like a tiny trampoline".

Verdict: **polarizing, not broken**. The dominant complaint class is
accidental edge triggers; the people who keep it are tinkerers who remap it.

## Recommendation on this board

Keep the firmware gestures **disabled** (they already are) and, if the
gestures are wanted, map them **natively in Hyprland** (hidraw daemon after
the MadhiasM pattern, adjusted for these bindings) — no firmware writes, no
"typed h" failure mode, per-gesture disable. Do not wire the hidraw vendor
protocol or `OUTPUT(14)` writes into anything a user-facing tool needs; a
bad write there is touchpad-brick territory (the descriptor's `ff00.*`
commands are undocumented vendor space). Watch `ZachAR3/HonorControl` —
it also covers the fan-curve and battery work in `mra-xxx-power.md`,
on the same hardware.

## Related pages

- `mra-xxx-power.md` — the EC/WMI vendor surface (battery, fan, power modes)
- `mra-xxx.md` — board-specific input notes (touchscreen FTSC1000, keymaps)
- `../NPU.md` — the other idle accelerator on this board