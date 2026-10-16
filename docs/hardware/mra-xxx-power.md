# MRA-XXX power: what Windows does, what Linux measures, what to copy

Measured and mined 2026-10-08/09 on the machine itself (BIOS 3.05, Core Ultra 5
125H, iGPU on `xe`, s2idle). Read-only throughout: live sysfs, one-time EC RAM /
MMIO / mailbox reads through `ec_sys` + `/dev/mem`, the factory ACPI dump in
`acpi-mra-xxx-bios3.05/dsl/`, powertop in report-only mode, and upstream driver
history. Nothing on the machine was changed. Full agent evidence trails:
`~/.omp/agent/sessions/-src-circumspace/2026-10-07T23-32-30-466Z_*/` (jobs
`PublicCattle` = vendor/ACPI, `DominantReptile` = measurements).

## Measured baseline (battery, idle, screen untouched)

- Draw: median **8.13 W**, quiet floor **6.7 W** (75 % of samples), 10–17 W
  spikes under background userspace (Brave, Signal). ≈ 8.9 h from 83 % charge.
- Package (RAPL): 2.5–3.3 W quiet idle; psys 5.0–5.6 W quiet idle →
  **1.5–2.5 W** of the battery draw is panel/backlight/VR/WiFi/NVMe/USB
  outside the SoC package. Panel dominates (3120×2080 eDP, 30 bpp, DSC).
- **Idle quality is the problem: PC10 residency 0.06 %**, `slp_s0` residency
  delta zero, ~90 % of idle wall-clock in C0/C1. Per-core idling is healthy
  (C6 84–99 %) — a system-wide waker storm, not a busy core.
- Wakers over 60 s idle: LOC timer **1,902/s**, function-call (CAL) **141/s**,
  TLB shootdown **98/s**, resched IPIs 28/s; powertop: `tick_nohz_handler`
  1,944 ev/s, sched softirq 253/s, `idma64.1` (i2c DesignWare DMA) 381/s,
  INTC1083:00 GPIO ~4–70 ev/s. Cost vs a ~0.3–0.5 W PC10 floor: **≥ 2 W
  continuously.**
- xe display churn: **214,153 `Setting DC state` kernel lines in ~23.5 h**,
  ~360/min during sampling (DC5↔DC6, ~6/s at idle) — DC6 savings repeatedly
  lost. PSR1 itself healthy (enabled, IDLE, frontbuffer busy 0). Candidate
  regression vs `i915`; check a fallback-boot DC5/DC6 counter before acting.
- NVMe (1e49:1031) never runtime-parks: `runtime_suspended_time = 0` vs
  neighbours' 17–22 Ms; ~30 background IOPS (nvme0q2–6) + `default_ps_max_latency_us`
  100,000 keep it awake.
- Battery: DESAY AP16L5J, 56.19/59.67 Wh full/design = **94 % health, 130
  cycles**. Charge protection **70/90 armed** (see below). WiFi PS on. Audio
  codec PM on (`sof-hda-dsp`, `power_save=1`). `power-profiles-daemon` active,
  power-saver on battery, EPP=`power` everywhere.
- `powertop --auto-tune` equivalent already applied by
  `omarchy-powertop-tune.service`: 10 PCI devices runtime-auto (17–22 Ms
  suspended each), NMI watchdog off.
- Landmine, currently inert: `/etc/modprobe.d/omarchy-usb-autosuspend.conf`
  sets `usbcore autosuspend=-1`, but usbcore loads from the initramfs before
  modprobe.d applies, so the live parameter is 2 s. Safe to delete.

## What Windows (PC Manager) actually does — decoded from this firmware

1. **Battery Protection**: three preset pairs, EC-enforced even powered off —
   Home 40–70, Office 70–90, Travel 95–100 — plus adaptive "Smart Charge"
   (mode 4). Transport here is `\SBCM` (WMI `0x00001503`), which also writes
   charge-mode (`0x200213E6`) and actual-threshold (`0x200204CC`); the
   start/stop pair lands at **EC 0xE4/0xE5** via mailbox `ECCC(0x82,…)`.
   `\GBCM` (`0x00001603`) derives the mode from the *start* byte alone:
   40→1, 70→2, 95→3, anything else→0 (unarmed). **This board is live-armed
   as 70/90 = mode 2 = the "Office" preset** — sysfs, EC RAM (0x46/0x5A),
   and 0xE6=0x02 all agree. This **resolves the open question in
   `mra-xxx.md`**: the ZQC-P offsets 0x80/0x81/0x85 are battery telemetry
   on this board; the real pair is 0xE4/0xE5. Presets only: an invalid pair
   (e.g. 75/80, which the desktop applet wrote earlier) is reported back
   through sysfs but silently ignored by the EC.
2. **Power modes (Fn+P Performance/Balanced, the "40 W" magic)**: *not*
   WMI-settable on this board — `\SPFM` (`0x00001304`) and `\SSTP`
   (`0x00000205`) are stubs. Windows' mechanism is the `OCPM` DSDT byte
   (read by `\GPFM`, `0x00001204`) selecting which **Intel DPTF policy
   vault** `\`_SB.IETM` `GDDV` returns (SSDT2: "performance mode" vault →
   different PL/fan policy), plus EC-internal profile. Candidate levers a
   driver could write: `\SODP` (`0x00000F03`, OEM data values → `ODVP()`
   + `Notify(IETM, 0x88)` — the DPTF ODV channel is live here), `\IFCI`
   fan curve, and EC mailbox power-cap registers. Fn+P already reaches
   Linux as `0x2a1` → `KEY_PROG1` via the installed keymap overlay;
   whether the EC flips `OCPM` on the bare keypress is unmeasured.
3. **PC Manager's userspace thermal loop**: ~200 ms poll widening the
   thermal envelope, fans engaging from ~55 °C vs the stock curve's 72 °C
   (measured on ZQC-P; on MRA the analogous `\SVRF`/`\SPPM` do not exist).
   Reachable equivalents here: fan-curve index and manual fan control —
   see below.

## Reachable-but-unused surface on this board (all verified live AML)

- **Fan status**: `\GFNS` (`0x00000802`) → STAT + RPM (16-bit LE) +
   duty %×100 from mailbox `0x20020A00–05`; `\GTMP` (`0x00000202`) →
  sensor-indexed temps (TP00=48 °C CPU, TP01=39 SoC, TP08=32 ambient).
  Same ABI as the accepted upstream `FMI-XX` hwmon driver (add a
  `HONOR MRA-XXX` DMI entry) or the aymanbagabas fork (MRA-XXX quirk
  already present, PRs #92/#93, tested on this machine).
- **Fan curve**: `\IFCI` (`0x00000807`) writes the curve index to **EC
  0x79 (`ZNCJ`), currently 0xA0 stock**; `\GSFV` reads it. ZQC-P protocol
  applies by analogy: 0xAA/0xAB engage earlier, **0xAC stops both fans
  dead** — and the MRA AML has **no range guard**, so only 0xA0–0xAB are
  safe. Highest-value cooling fix; needs the fixed-load ramp protocol.
- **Manual fan control**: `WTER` **exists in this DSDT** (absent on
  ZQC-P), and the `0x2002xxxx` register space matches
  `art14-fan-daemon`'s assumptions exactly (`0x20020C20` manual/auto,
  `0x20020A07/08` duty). **Untested on this 2024 unit** — one careful
  live write (auto value first; a failed mailbox command can wedge it).
- **Smart charge** (`\SBCM` mode 4): adaptive charge mode, settable but
  only partially decoded (qu1x documents a disable payload).
- Keyboard backlight family (`\SKBT`/`\GKBT` timeout, `\SKBM` modes,
  `\SKBL` level/auto): live; used on this machine today via debugfs raw
  WMI (`/usr/local/bin/honor-kbd-backlight-timeout`).
- No `platform_profile` exists anywhere: upstream `huawei-wmi` has none,
  and no patchwork series is pending (checked 2026-10-08).

## Ranked plan (not executed)

1. **Waker storm hunt** (≥ 2 W, biggest runtime win): attribute the
   LOC/CAL/TLB storm — suspects: the same i2c/`idma64` DMA IRQ (381/s),
   the INTC1083 GPIO waker, `tick_nohz` fallout from a missed
   `nohz_full`/dyntick config, xe DC5↔DC6 churn feeding wakeups, and
   userspace timers (Hyprland `--watchdog` 48 ev/s, Brave gpu-proc
   181 ev/s). Method: perf/`powertop -i` per-waker attribution on a
   quiet boot, then per-cause fixes. Moderate effort, low risk.
2. **NVMe parking**: lower `pm_qos_latency_tolerance_us` and/or
   quiesce the background I/O keeping it awake. ~0.3–0.5 W, quick,
   low risk.
3. **Fan curve via `\IFCI`** (comfort/thermals, not runtime): 2–6 h +
   careful measurement; forbidden indices unguarded — 0xAC kills fans.
   `ZachAR3/HonorControl` (see `mra-xxx-touchpad.md`) claims curve-based
   fan control on this exact board — but its entire hardware layer is an
   adapter over an **unpublished private package** (`honor-tools`, not on
   PyPI, supplied only as an offline wheel), so there is no fan source to
   read yet; the register semantics presumably match this page's `WTER`/
   mailbox map, but that is inference, not verification. Until that wheel
   surfaces, this item stands as written.
4. **WTER manual-fan live test** then `art14-fan-daemon` port if it
   holds: 3–6 h; wedge risk on a bad mailbox write; auto-value-first.
   Corroboration that the mailbox is the vendor's own mechanism:
   `kiradzero/hfac` — "vendor removed fan control from ACPI but left it
   in the EC firmware, reachable through a mailbox" — same pattern on
   another HONOR board.
5. **Battery-threshold persistence**: pair is EC-persisted and has held
   here across reboots with nothing re-arming it; qu1x reports a full
   power-off can forget it on their board. The guarding half landed in the
   companion repo for this machine (`magicbook14-linux`): `honor-charge-limit`
   writes a preset, reads EC 0xE6 back and exits 3 when the EC did not arm,
   whitelisted in `sudoers.d` so the battery panel's "charge to full" button
   needs no password. Still unwritten: a boot/resume unit re-arming 70/90.
   ~1 h.
6. **Smart-charge mode 4** and **true `platform_profile`/DPTF vault
   parity**: days–weeks, partially decoded; only worth it after 1–2.

Realistic tuned target if 1–2 land: ~5.5–6 W idle ≈ 11–12 h, from 8.13 W
today. The vendor "magic" mostly buys thermals and battery longevity
(charge limiting — already armed), not runtime; the runtime gap is
Linux-side idle depth.
