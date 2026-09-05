# Fn keys that reach the kernel and stop there

| | |
|---|---|
| Symptom | some Fn keys do nothing, and `dmesg` fills with `Unknown key pressed, code: 0x02xx` |
| Cause | the in-tree `huawei-wmi` keymap does not carry these HONOR codes |
| Fix | rebuild `huawei-wmi` with them added, plus a hwdb entry for the atkbd noise |

```sh
sudo bash patch/hotkeys/install.sh
```

## What is actually broken

The keys work. The EC sends them, WMI delivers them, `huawei-wmi` receives them.
Then `sparse_keymap` looks the code up, does not find it, and the driver logs:

```
input input18: Unknown key pressed, code: 0x02b3
```

Codes this machine was observed emitting, confirmed by pressing every key with
`capture-keys.sh` running:

| code | arrives as | source |
|---|---|---|
| `0x283` / `0x2a3` | `KEY_TOUCHPAD_ON` / `KEY_TOUCHPAD_OFF` | added here |
| `0x288` | `KEY_CAMERA_ACCESS_TOGGLE` | added here |
| `0x2a1` | `KEY_PROG1`, performance mode | added here |
| `0x2b1` / `0x2b2` | off / low keyboard-backlight state; M1020 reports LED levels 0 / 1 | added here |
| `0x2b3` | high keyboard-backlight state; M1020 reports LED level 2 | added here |
| `0x2e5` | ignored, an EC notification rather than a key press | added here |
| `0x287` | `KEY_MICMUTE` | already in-tree |
| `0x28a` | `KEY_CONFIG`, the vendor key | already in-tree |
| `0x28b` | `KEY_NOTIFICATION_CENTER`, YOYO | already in-tree |
| `0x28e` | `KEY_PRINT` | already in-tree |

After a full pass over the keyboard with this installed, **no code reached the
driver without a name**. Six of the mappings above are ones this fix adds, and
`0x288` in particular came from the FMB-P list and had never been seen here
until the key was pressed.

The installer also adds `0x288`, `0x2b4`, `0x2a0`, `0x2a6`, `0x2a7`, `0x2e0`,
`0x2e1` and `0x2e6`. Those come from the FMB-P work and have **not** been seen
here; they are harmless if this model never sends them, and the two models
clearly share the ABI.

That list is what this machine happened to have logged, not the full set of
keys the laptop has. Windows exposes considerably more. To find what yours
actually sends:

```sh
sudo bash patch/hotkeys/capture-keys.sh
```

It listens on the WMI hotkey device, on the PS/2 keyboard and on the kernel log
at once, and labels each press:

| what you see | what it means |
|---|---|
| `WMI UNMAPPED 0x2xx` | the driver got it and has no name for it. Send this in and it gets mapped |
| `WMI MAPPED KEY_...` | it arrived as a key event; if nothing happens, the desktop is what ignores it |
| `atkbd ...` | it came over the PS/2 keyboard rather than WMI |
| nothing at all | the EC handled it itself and told no one. Nothing to map |

The last row is worth knowing before hunting for a missing mapping: several
keys on these machines never leave the EC, and no driver change can surface
them.

## Keyboard backlight on ZQC-P M1020/C170

BIOS 1.10 was measured before this was enabled. One physical cycle emitted
`0x2b1 → 0x2b2 → 0x2b3`, meaning off, low and high. The firmware WMI methods
then returned and physically applied the same three states:

| Command | Measured result |
|---|---|
| `GKBM` (`0x1306`) | reads mode `0x02` / `0x03` / `0x04` |
| `SKBM` (`0x1406`) | physically sets off / low / high; a test value of 25 returned status `0x01` and left the mode unchanged |
| `GKBT` (`0x1206`) | read the stock timeout as 15 seconds |
| `SKBT` (`0x1106`) | a temporary 5-second value read back as 5 and physically timed out after about 5 seconds |

`add-m1020-kbdlight.py` extends the same `huawei-wmi` overlay with a standard
`platform::kbd_backlight` LED. It is gated on the exact HONOR, ZQC-P, M1020,
C170 DMI identity and checks that all four ACPI methods exist. It uses those
firmware methods, not direct EC writes. Hardware key notifications update the
LED as 0, 1 or 2, so UPower and KDE display 0%, 50% and 100% without applying a
second brightness step.

The LED uses `LED_CORE_SUSPENDRESUME`. systemd automatically attaches
`systemd-backlight@leds:platform::kbd_backlight.service`, which saves and
restores its last level across boots. Restoration after both reboot and
suspend/resume was physically verified on this unit.

The timeout defaults to 15 seconds. Set any value from 0 through 65535 by
rerunning the installer; zero means no timeout:

```sh
sudo KBDLIGHT_TIMEOUT=30 bash patch/hotkeys/install.sh
sudo KBDLIGHT_TIMEOUT=0 bash patch/hotkeys/install.sh
```

The installer keeps a custom value in
`/etc/modprobe.d/61-honor-keyboard-backlight.conf`, including when the automatic
kernel-update rebuild reruns it.

Touchpad wake was tested and is not offered. Activity reaches the correct
`TOPS0102 27c6:0f9a` input device, but repeating `SKBM` does not restart an
expired timer and `SKBL` is a firmware stub. The sibling model's raw EC `0x01`
latch is not used on M1020 without firmware evidence.

A long-press shortcut is deliberately not implemented. Holding the key for
about 5.6 seconds was visible only through companion atkbd scancode `f8`, and
that same scancode accompanies every HONOR hotkey. Treating it as a backlight
long press would therefore let another held Fn key change the timeout.

## Why this cannot be a udev rule

The obvious answer is a hwdb entry, and it does not work. `hwdb` remaps
scancodes through `EVIOCSKEYCODE`, and on a `sparse_keymap` device that ioctl
looks the scancode up in the driver's table first and returns `-EINVAL` for
anything that is not already there. hwdb can change what an existing code
means; it cannot add one. Hence a driver change.

## The atkbd noise, and the scancode that has to be written a particular way

Alongside every hotkey the EC also emits one extra PS/2 scancode, which means
nothing and produces an `atkbd serio0: Unknown key pressed` line each time.
`61-honor-keyboard.hwdb` maps it to `unknown`. Here a hwdb entry *is* the right
tool, because this is a remap of a code that already exists.

The entry says `f8`, not `e078`, and that took finding. udev applies these
through the legacy `EVIOCSKEYCODE`, where the scancode is used directly as an
index into atkbd's 512-entry keymap. atkbd in translated set 2 folds the `e0`
prefix into the high bit, so the index is `0x78 | 0x80 = 0xf8` — exactly what
the kernel prints. An `e078` entry is 57464, out of range, and udev logs:

```
event2: Failed to call EVIOCSKEYCODE with scan code 0xe078,
        and key code 240: Invalid argument
```

Quietly, into the udev log, where nobody looks. The property shows up in
`udevadm info` either way, so the rule appears to be working while the keymap
is untouched. Confirmed here by writing both forms through the same ioctl udev
uses: `e078` rejected, `f8` accepted, and the warning stops.

## How it is built

The same way as [`headset-mic/`](../headset-mic/) and [`sof-audio/`](../sof-audio/):
fetch `drivers/platform/x86/huawei-wmi.c` at the running kernel's tag, add the
entries, build that one file, and install it into
`/usr/lib/modules/$KVER/updates/`, which `depmod` searches before `kernel/`.
The packaged module is untouched and removal is one `rm`.

The insertion is idempotent and skips any code the kernel already knows, so
once these mappings land upstream this becomes a no-op rather than a conflict.

## After a kernel update

A new kernel has no `updates/` entry, so re-run this, or install
[`auto-rebuild/`](../auto-rebuild/), which does it for you.

## Where it belongs

Upstream, in `huawei-wmi`'s keymap. There is nothing model-specific about the
mechanism, only about which codes a given HONOR laptop emits, and the driver
already carries a mix of Huawei and HONOR entries.
[`zqc-p/M1010/huawei-wmi-keymap.patch`](zqc-p/M1010/huawei-wmi-keymap.patch) is the change
in submittable form.

## Credit

The FMB-P code list and the `e078` observation come from **tsukasagenesis** and
**egormanga** in
[colorcube/Linux-on-Honor-Magicbook-14-Pro#4](https://github.com/colorcube/Linux-on-Honor-Magicbook-14-Pro/issues/4),
which in turn builds on
[aymanbagabas/Huawei-WMI#93](https://github.com/aymanbagabas/Huawei-WMI/pull/93).
The codes listed as observed above were confirmed independently on the ZQC-P.

---

## Upstream status

Checked against mainline `master` and tags v6.17 through v7.2 on 2026-08-22.

**What is already in-tree.** Exactly two HONOR codes, both added by commit
[`5c72329716d0`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=5c72329716d0858621021193330594d5d26bf44d)
"platform/x86: huawei-wmi: add keys for HONOR models" (Jia Ston), first in
**v6.18**, written for "HONOR MagicBook X16/X14 models produced in 2025":
`0x28b` → `KEY_NOTIFICATION_CENTER` and `0x28e` → `KEY_PRINT`. Those are the
rows marked "already in-tree" above.

**What is not.** The in-tree `huawei_wmi_keymap[]` ends at `0x2c1`, and contains
**none** of `0x283`, `0x288`, `0x2a0`, `0x2a1`, `0x2a3`, `0x2a6`, `0x2a7`,
`0x2b1`–`0x2b4`, `0x2e0`, `0x2e1`, `0x2e5`, `0x2e6`. Every entry this
directory's patch adds is still missing from Linux 7.2, so the patch does not
conflict with anything and the module rebuild is still needed.

`huawei-wmi` also has **no HONOR DMI handling at all** — no per-model gating,
no quirks table. The keymap is shared across every machine the driver binds to.

**Somebody else is upstreaming one of these codes right now.** Ruzal Daminov
posted "[PATCH v2] platform/x86: huawei-wmi: add camera toggle keycode" on
2026-08-19 ([patchwork 14756903](https://patchwork.kernel.org/project/platform-driver-x86/patch/20260819083836.1410-1-daminovruzal7@gmail.com/)),
whose entire diff is `{ KE_KEY, 0x288, { KEY_CAMERA_ACCESS_TOGGLE } }` — the
same code and the same keycode choice as this directory. An earlier series from
the same author, "add modern Honor MagicBook hotkeys"
([patchwork 14750719](https://patchwork.kernel.org/project/platform-driver-x86/patch/20260814171324.16727-1-daminovruzal7@gmail.com/)),
covers more of the set. **Coordinate with that series before sending anything**,
rather than posting a competing patch.

**Where these codes originally come from.** The out-of-tree
[aymanbagabas/Huawei-WMI](https://github.com/aymanbagabas/Huawei-WMI) driver,
where PR 93 "Updated key assignments for new models" (merged 2024-12-24) is the
origin of `0x283`/`0x2a3` touchpad, `0x288` camera, `0x2a7` refresh-rate and
the `0x2b1`–`0x2b4` keyboard-backlight block, and PR 92 added the ambient
keyboard-backlight mode. Those are merged into *that* driver, which is not the
kernel — the in-tree `huawei-wmi` is a separate, older codebase.

> A note on patchwork: it is not a reliable indicator of state for this
> subsystem. Two HONOR `atkbd` patches still read "new" there while their
> commits have been in Linus's tree for weeks. Check git.
